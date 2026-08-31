import Foundation

enum TechnicianLocationFreshness: Equatable, Sendable {
    case current
    case stale
    case unknown
}

struct TechnicianLocationInfo: Equatable, Sendable {
    let coordinate: LocationCoordinate
    let capturedAt: Date
    let freshness: TechnicianLocationFreshness
}

struct TechnicianAssignmentLocationContext: Equatable, Sendable {
    let workOrderSite: LocationCoordinate?
    let technicianLocations: [UserID: TechnicianLocationInfo]

    func locationInfo(for technicianId: UserID) -> TechnicianLocationInfo? {
        technicianLocations[technicianId]
    }

    /// Distance used for sorting. Unknown/stale locations are excluded from proximity ranking.
    func sortableDistanceMeters(for technicianId: UserID) -> Double? {
        guard let site = workOrderSite,
              let info = technicianLocations[technicianId],
              info.freshness == .current,
              info.coordinate.isValid,
              site.isValid
        else { return nil }
        return info.coordinate.distanceMeters(to: site)
    }

    func displayLabel(for technicianId: UserID) -> String {
        guard workOrderSite != nil else { return "" }
        guard let info = technicianLocations[technicianId] else {
            return "Konum bilinmiyor"
        }
        switch info.freshness {
        case .current:
            guard let site = workOrderSite else { return "Konum bilinmiyor" }
            return info.coordinate.formattedDistance(to: site)
        case .stale:
            return "Konum güncel değil"
        case .unknown:
            return "Konum bilinmiyor"
        }
    }

    /// Location label for assignment UI — always returns a human-readable status.
    func assignmentLocationLabel(for technicianId: UserID) -> String {
        if workOrderSite != nil {
            return displayLabel(for: technicianId)
        }
        guard let info = technicianLocations[technicianId] else {
            return "Konum bilinmiyor"
        }
        switch info.freshness {
        case .current:
            return "Konum mevcut"
        case .stale:
            return "Konum güncel değil"
        case .unknown:
            return "Konum bilinmiyor"
        }
    }
}

enum TechnicianAssignmentLocationBuilder {
    /// No prior domain stale rule existed. Four hours keeps proximity ranking conservative for field GPS samples.
    static let staleLocationThreshold: TimeInterval = 4 * 3600

    static func resolveWorkOrderSite(
        customerId: CustomerID?,
        workOrderId: WorkOrderID?,
        orders: [WorkOrder],
        locationsByWorkOrderId: [WorkOrderID: [WorkOrderLocation]]
    ) -> LocationCoordinate? {
        if let workOrderId,
           let coordinate = latestCoordinate(in: locationsByWorkOrderId[workOrderId] ?? []) {
            return coordinate
        }

        guard let customerId else { return nil }

        let customerOrderIds = orders.filter { $0.customerId == customerId }.map(\.id)
        var latest: WorkOrderLocation?
        for orderId in customerOrderIds {
            for location in locationsByWorkOrderId[orderId] ?? [] {
                if latest.map({ location.capturedAt > $0.capturedAt }) ?? true {
                    latest = location
                }
            }
        }
        return latest?.coordinate
    }

    /// Resolves a reference site for bulk assignment across one or many selected orders.
    static func resolveBulkAssignmentSite(
        selectedOrders: [WorkOrder],
        locationsByWorkOrderId: [WorkOrderID: [WorkOrderLocation]]
    ) -> LocationCoordinate? {
        guard !selectedOrders.isEmpty else { return nil }

        if selectedOrders.count == 1, let order = selectedOrders.first {
            return resolveWorkOrderSite(
                customerId: order.customerId,
                workOrderId: order.id,
                orders: selectedOrders,
                locationsByWorkOrderId: locationsByWorkOrderId
            )
        }

        let customers = Set(selectedOrders.map(\.customerId))
        if customers.count == 1 {
            return resolveWorkOrderSite(
                customerId: customers.first,
                workOrderId: nil,
                orders: selectedOrders,
                locationsByWorkOrderId: locationsByWorkOrderId
            )
        }

        guard let primary = selectedOrders.sorted(by: {
            if $0.scheduledDate != $1.scheduledDate { return $0.scheduledDate > $1.scheduledDate }
            return $0.id.rawValue < $1.id.rawValue
        }).first else { return nil }

        return resolveWorkOrderSite(
            customerId: primary.customerId,
            workOrderId: primary.id,
            orders: selectedOrders,
            locationsByWorkOrderId: locationsByWorkOrderId
        )
    }

    static func buildContext(
        workOrderSite: LocationCoordinate?,
        technicians: [User],
        locationsByWorkOrderId: [WorkOrderID: [WorkOrderLocation]],
        now: Date = Date(),
        staleThreshold: TimeInterval = staleLocationThreshold
    ) -> TechnicianAssignmentLocationContext {
        var technicianLocations: [UserID: TechnicianLocationInfo] = [:]

        for technician in technicians {
            if let info = latestLocation(
                for: technician.id,
                locationsByWorkOrderId: locationsByWorkOrderId,
                now: now,
                staleThreshold: staleThreshold
            ) {
                technicianLocations[technician.id] = info
            }
        }

        return TechnicianAssignmentLocationContext(
            workOrderSite: workOrderSite,
            technicianLocations: technicianLocations
        )
    }

    private static func latestLocation(
        for technicianId: UserID,
        locationsByWorkOrderId: [WorkOrderID: [WorkOrderLocation]],
        now: Date,
        staleThreshold: TimeInterval
    ) -> TechnicianLocationInfo? {
        var latest: WorkOrderLocation?
        for locations in locationsByWorkOrderId.values {
            for location in locations where location.capturedByUserId == technicianId {
                if latest.map({ location.capturedAt > $0.capturedAt }) ?? true {
                    latest = location
                }
            }
        }

        guard let latest else { return nil }

        let age = now.timeIntervalSince(latest.capturedAt)
        let freshness: TechnicianLocationFreshness
        if age <= staleThreshold {
            freshness = .current
        } else {
            freshness = .stale
        }

        return TechnicianLocationInfo(
            coordinate: latest.coordinate,
            capturedAt: latest.capturedAt,
            freshness: freshness
        )
    }

    private static func latestCoordinate(in locations: [WorkOrderLocation]) -> LocationCoordinate? {
        locations.max(by: { $0.capturedAt < $1.capturedAt })?.coordinate
    }
}

enum TechnicianAssignmentLocationLoader {
    static func loadLocations(
        for workOrderIds: [WorkOrderID],
        repository: WorkOrderLocationRepository
    ) async -> [WorkOrderID: [WorkOrderLocation]] {
        let uniqueIds = Array(Set(workOrderIds))
        guard !uniqueIds.isEmpty else { return [:] }

        return await withTaskGroup(of: (WorkOrderID, [WorkOrderLocation]).self) { group in
            for workOrderId in uniqueIds {
                group.addTask {
                    let locations = (try? await repository.list(for: workOrderId)) ?? []
                    return (workOrderId, locations)
                }
            }

            var result: [WorkOrderID: [WorkOrderLocation]] = [:]
            for await (workOrderId, locations) in group where !locations.isEmpty {
                result[workOrderId] = locations
            }
            return result
        }
    }

    static func merge(
        _ base: [WorkOrderID: [WorkOrderLocation]],
        with overlay: [WorkOrderID: [WorkOrderLocation]]
    ) -> [WorkOrderID: [WorkOrderLocation]] {
        var merged = base
        for (orderId, locations) in overlay {
            if var existing = merged[orderId] {
                existing.append(contentsOf: locations)
                merged[orderId] = existing
            } else {
                merged[orderId] = locations
            }
        }
        return merged
    }
}
