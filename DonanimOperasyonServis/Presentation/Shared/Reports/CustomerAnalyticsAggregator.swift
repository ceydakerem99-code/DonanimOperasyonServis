import Foundation

enum CustomerAnalyticsAggregator {
    static func summary(
        customer: Customer,
        orders: [WorkOrder]
    ) -> CustomerAnalyticsSummary {
        let scoped = orders.filter { $0.customerId == customer.id }
        let nonRejected = scoped.filter { $0.status != .rejected }
        let completed = scoped.filter { $0.status == .completed }
        let visitDates = nonRejected.map { $0.completedAt ?? $0.scheduledDate }

        return CustomerAnalyticsSummary(
            customerId: customer.id,
            customerName: customer.name,
            workplace: workplaceLabel(for: customer),
            totalVisits: nonRejected.count,
            completedVisits: completed.count,
            totalOrders: scoped.count,
            completedOrders: completed.count,
            pausedOrders: scoped.filter { $0.status == .paused }.count,
            inProgressOrders: scoped.filter { !$0.status.isTerminal && $0.status != .paused && $0.status != .assigned }.count,
            lastVisitDate: visitDates.max()
        )
    }

    static func technicianHistory(
        orders: [WorkOrder],
        technicians: [UserID: User]
    ) -> [CustomerTechnicianVisitEntry] {
        let grouped = Dictionary(grouping: orders, by: \.assignedTechnicianId)
        return grouped.map { techId, items in
            let dates = items.map { $0.completedAt ?? $0.scheduledDate }
            return CustomerTechnicianVisitEntry(
                id: techId.rawValue,
                technicianId: techId,
                technicianName: technicians[techId]?.fullName ?? techId.rawValue,
                visitCount: items.filter { $0.status != .rejected }.count,
                lastVisit: dates.max()
            )
        }
        .sorted {
            if $0.visitCount != $1.visitCount { return $0.visitCount > $1.visitCount }
            return $0.technicianName.localizedCaseInsensitiveCompare($1.technicianName) == .orderedAscending
        }
    }

    static func operationHistory(orders: [WorkOrder]) -> [CustomerOperationEntry] {
        let grouped = Dictionary(grouping: orders, by: \.workType)
        return WorkType.allCases.compactMap { workType in
            let count = grouped[workType]?.count ?? 0
            guard count > 0 else { return nil }
            return CustomerOperationEntry(id: workType.rawValue, workType: workType, count: count)
        }
        .sorted { $0.count > $1.count }
    }

    static func deviceHistory(orders: [WorkOrder]) -> [CustomerDeviceEntry] {
        let grouped = Dictionary(grouping: orders, by: \.deviceCategory)
        return DeviceCategory.allCases.compactMap { category in
            let count = grouped[category]?.count ?? 0
            guard count > 0 else { return nil }
            return CustomerDeviceEntry(id: category.rawValue, deviceCategory: category, count: count)
        }
        .sorted { $0.count > $1.count }
    }

    static func timeline(
        orders: [WorkOrder],
        technicians: [UserID: User]
    ) -> [CustomerTimelineEntry] {
        orders
            .sorted { ($0.completedAt ?? $0.scheduledDate) > ($1.completedAt ?? $1.scheduledDate) }
            .map { order in
                CustomerTimelineEntry(
                    id: order.id,
                    date: order.completedAt ?? order.scheduledDate,
                    workOrderNumber: order.workOrderNumber,
                    technicianName: technicians[order.assignedTechnicianId]?.fullName ?? "Bilinmeyen",
                    workType: order.workType,
                    deviceCategory: order.deviceCategory,
                    status: order.status
                )
            }
    }

    static func workplaceLabel(for customer: Customer) -> String {
        if let city = customer.city, !city.isEmpty {
            return "\(customer.name) · \(city)"
        }
        return customer.address.isEmpty ? customer.name : customer.address
    }

    static func pickerShortSummary(from summary: CustomerAnalyticsSummary) -> String {
        var parts = ["\(summary.completedOrders) tamamlanan"]
        if summary.inProgressOrders > 0 {
            parts.append("\(summary.inProgressOrders) devam eden")
        }
        if summary.pausedOrders > 0 {
            parts.append("\(summary.pausedOrders) beklemede")
        }
        return parts.joined(separator: " · ")
    }
}
