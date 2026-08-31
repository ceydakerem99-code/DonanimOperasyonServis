import Foundation

struct OperatorTechnicianIdentityPreview: Equatable, Sendable {
    var count = 0
    var previewNames: [String] = []
    var overflowCount = 0

    static let empty = OperatorTechnicianIdentityPreview()

    static func make(from technicians: [User], previewLimit: Int = 2) -> OperatorTechnicianIdentityPreview {
        let names = technicians.map(\.fullName)
        let preview = Array(names.prefix(previewLimit))
        return OperatorTechnicianIdentityPreview(
            count: names.count,
            previewNames: preview,
            overflowCount: max(0, names.count - preview.count)
        )
    }
}

struct OperatorOperationsKPIs: Equatable, Sendable {
    var openWorkOrders = 0
    var urgentWorkOrders = 0
    var overdueWorkOrders = 0
    var pausedWorkOrders = 0
    var availableTechnicians = 0
    var busyTechnicians = 0
    var availableTechnicianPreview = OperatorTechnicianIdentityPreview.empty
    var busyTechnicianPreview = OperatorTechnicianIdentityPreview.empty
}

enum OperatorDashboardOperations {
    static func computeKPIs(
        orders: [WorkOrder],
        technicians: [User],
        now: Date,
        calendar: Calendar = .current
    ) -> OperatorOperationsKPIs {
        let openOrders = orders.filter { !$0.status.isTerminal }
        let technicianGroups = groupedTechnicians(orders: orders, technicians: technicians)

        return OperatorOperationsKPIs(
            openWorkOrders: openOrders.count,
            urgentWorkOrders: openOrders.filter { $0.priority == .urgent }.count,
            overdueWorkOrders: openOrders.filter { isOverdue($0, now: now, calendar: calendar) }.count,
            pausedWorkOrders: orders.filter { $0.status == .paused }.count,
            availableTechnicians: technicianGroups.available.count,
            busyTechnicians: technicianGroups.busy.count,
            availableTechnicianPreview: .make(from: technicianGroups.available),
            busyTechnicianPreview: .make(from: technicianGroups.busy)
        )
    }

    static func groupedTechnicians(
        orders: [WorkOrder],
        technicians: [User]
    ) -> (available: [User], busy: [User]) {
        let sorted = TechnicianAssignmentSupport.sortedTechniciansForAssignment(
            technicians.filter(\.isActive),
            orders: orders
        )
        var available: [User] = []
        var busy: [User] = []

        for technician in sorted {
            switch TechnicianAssignmentSupport.workingStatus(for: technician.id, orders: orders) {
            case .available, .paused:
                available.append(technician)
            case .busy:
                busy.append(technician)
            }
        }

        return (available, busy)
    }

    /// Overdue when the planned window has passed and the job is not terminal.
    /// Same-calendar-day jobs without an explicit end time are not overdue until the day ends.
    static func isOverdue(
        _ order: WorkOrder,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        WorkOrderTimeStatusPolicy.isOverdue(order, now: now, calendar: calendar)
    }
}

enum OperatorDashboardKPISelection: Hashable, Sendable {
    case openWorkOrders
    case urgentWorkOrders
    case overdueWorkOrders
    case pausedWorkOrders
    case availableTechnicians
    case busyTechnicians
}

enum OperatorTechnicianListFilter: String, CaseIterable, Hashable, Sendable {
    case all
    case available
    case busy

    var title: String {
        switch self {
        case .all: return "Tümü"
        case .available: return "Müsait"
        case .busy: return "Meşgul"
        }
    }

    var workingStatus: TechnicianWorkingStatus? {
        switch self {
        case .all: return nil
        case .available: return .available
        case .busy: return .busy
        }
    }
}

enum OperatorTechnicianDashboardScope: Equatable, Sendable {
    case none
    case available
    case busy

    var listFilter: OperatorTechnicianListFilter {
        switch self {
        case .none: return .all
        case .available: return .available
        case .busy: return .busy
        }
    }
}

enum OperatorWorkOrderDashboardScope: Equatable, Sendable {
    case none
    case open
    case urgent
    case overdue
    case paused
    case completed

    var listFilter: OperatorWorkOrderListFilter {
        switch self {
        case .paused: return .paused
        case .completed: return .completed
        default: return .all
        }
    }

    var priorityFilter: WorkOrderPriority? {
        self == .urgent ? .urgent : nil
    }
}
