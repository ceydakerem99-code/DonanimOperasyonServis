import Foundation

enum TechnicianWorkingStatus: Equatable, Sendable {
    case available
    case busy
    case paused

    var displayName: String {
        switch self {
        case .available: return "Müsait"
        case .busy: return "Meşgul"
        case .paused: return "Beklemede"
        }
    }

    /// Lower values appear first in recommendation ordering.
    var recommendationSortOrder: Int {
        switch self {
        case .available: return 0
        case .busy: return 1
        case .paused: return 2
        }
    }
}

struct TechnicianWorkloadCounts: Equatable, Sendable {
    var urgent = 0
    var high = 0
    var normal = 0
    var activeTotal = 0

    var compactSummary: String {
        "Acil: \(urgent) · Yüksek: \(high) · Normal: \(normal) · Aktif: \(activeTotal)"
    }
}

enum TechnicianAssignmentSupport {
    static func nameSearchFields(for user: User) -> [String] {
        var fields = [user.fullName]
        fields.append(contentsOf: user.fullName.split(separator: " ").map(String.init))
        return fields
    }

    static func matchesTechnicianNameSearch(_ user: User, query: String) -> Bool {
        TurkishSearchFilter.matches(query: query, in: nameSearchFields(for: user))
    }

    static func filterTechniciansByName(_ technicians: [User], query: String) -> [User] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return technicians }
        return technicians.filter { matchesTechnicianNameSearch($0, query: trimmed) }
    }

    static func workingStatus(for technicianId: UserID, orders: [WorkOrder]) -> TechnicianWorkingStatus {
        let activeOrders = orders.filter {
            $0.assignedTechnicianId == technicianId && !$0.status.isTerminal
        }
        if activeOrders.contains(where: { $0.status.isActivelyInField }) {
            return .busy
        }
        return .available
    }

    static func workload(for technicianId: UserID, orders: [WorkOrder]) -> TechnicianWorkloadCounts {
        let activeOrders = orders.filter {
            $0.assignedTechnicianId == technicianId && !$0.status.isTerminal
        }
        return TechnicianWorkloadCounts(
            urgent: activeOrders.filter { $0.priority == .urgent }.count,
            high: activeOrders.filter { $0.priority == .high }.count,
            normal: activeOrders.filter { $0.priority == .normal }.count,
            activeTotal: activeOrders.count
        )
    }

    static func recommendedTechnicianSort(
        _ lhs: User,
        _ rhs: User,
        orders: [WorkOrder],
        locationContext: TechnicianAssignmentLocationContext? = nil
    ) -> Bool {
        let lhsStatus = workingStatus(for: lhs.id, orders: orders)
        let rhsStatus = workingStatus(for: rhs.id, orders: orders)
        if lhsStatus.recommendationSortOrder != rhsStatus.recommendationSortOrder {
            return lhsStatus.recommendationSortOrder < rhsStatus.recommendationSortOrder
        }

        let lhsLoad = workload(for: lhs.id, orders: orders)
        let rhsLoad = workload(for: rhs.id, orders: orders)
        if lhsLoad.activeTotal != rhsLoad.activeTotal {
            return lhsLoad.activeTotal < rhsLoad.activeTotal
        }
        if lhsLoad.urgent != rhsLoad.urgent { return lhsLoad.urgent < rhsLoad.urgent }
        if lhsLoad.high != rhsLoad.high { return lhsLoad.high < rhsLoad.high }
        if lhsLoad.normal != rhsLoad.normal { return lhsLoad.normal < rhsLoad.normal }

        if let locationContext, locationContext.workOrderSite != nil {
            let lhsDistance = locationContext.sortableDistanceMeters(for: lhs.id)
            let rhsDistance = locationContext.sortableDistanceMeters(for: rhs.id)
            switch (lhsDistance, rhsDistance) {
            case let (left?, right?) where left != right:
                return left < right
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                break
            }
        }

        return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
    }

    static func sortedTechniciansForAssignment(
        _ technicians: [User],
        orders: [WorkOrder],
        locationContext: TechnicianAssignmentLocationContext? = nil
    ) -> [User] {
        technicians.sorted {
            recommendedTechnicianSort($0, $1, orders: orders, locationContext: locationContext)
        }
    }

    static let defaultRecommendationLimit = 3

    /// Top-ranked technicians for assignment suggestion badges (does not assign).
    static func recommendedTechnicianIDs(
        from technicians: [User],
        orders: [WorkOrder],
        locationContext: TechnicianAssignmentLocationContext? = nil,
        limit: Int = defaultRecommendationLimit
    ) -> Set<UserID> {
        guard limit > 0 else { return [] }
        let sorted = sortedTechniciansForAssignment(
            technicians,
            orders: orders,
            locationContext: locationContext
        )
        return Set(sorted.prefix(limit).map(\.id))
    }

    static func isRecommended(
        technicianId: UserID,
        among technicians: [User],
        orders: [WorkOrder],
        locationContext: TechnicianAssignmentLocationContext? = nil,
        limit: Int = defaultRecommendationLimit
    ) -> Bool {
        recommendedTechnicianIDs(
            from: technicians,
            orders: orders,
            locationContext: locationContext,
            limit: limit
        ).contains(technicianId)
    }
}
