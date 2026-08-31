import Foundation

enum FaultRecurrenceAggregator {
    private struct GroupKey: Hashable {
        let customerId: CustomerID
        let serialNumber: String
    }

    static func deviceEntries(
        orders: [WorkOrder],
        customers: [CustomerID: Customer],
        technicians: [UserID: User]
    ) -> [FaultRecurrenceEntry] {
        let repairOrders = orders.filter { $0.workType == .repair && $0.status != .rejected }
        let grouped = Dictionary(grouping: repairOrders) { order in
            GroupKey(
                customerId: order.customerId,
                serialNumber: normalizedSerial(order.serialNumber)
            )
        }

        return grouped.compactMap { key, groupedOrders in
            let uniqueOrders = deduplicatedOrders(groupedOrders)
            guard uniqueOrders.count >= 2 else { return nil }

            let sorted = uniqueOrders.sorted {
                occurrenceDate(for: $0) > occurrenceDate(for: $1)
            }
            let latest = sorted[0]
            let customer = customers[key.customerId]

            return FaultRecurrenceEntry(
                id: "\(key.customerId.rawValue)-\(key.serialNumber)",
                customerId: key.customerId,
                customerName: customer?.name ?? "Bilinmeyen müşteri",
                workplace: workplaceLabel(for: customer),
                serialNumber: key.serialNumber,
                deviceLabel: deviceLabel(for: latest),
                workType: .repair,
                issueLabel: issueLabel(from: sorted),
                recurrenceCount: uniqueOrders.count,
                lastOccurrenceDate: occurrenceDate(for: latest),
                technicianNames: technicianNames(from: uniqueOrders, technicians: technicians),
                workOrderIds: sorted.map(\.id)
            )
        }
        .sorted(by: sortEntries)
    }

    static func customerSummaries(from entries: [FaultRecurrenceEntry]) -> [FaultRecurrenceCustomerSummary] {
        let grouped = Dictionary(grouping: entries, by: \.customerId)
        return grouped.map { customerId, items in
            let sortedItems = items.sorted(by: sortEntries)
            let latest = sortedItems[0]
            let technicians = Array(Set(items.flatMap(\.technicianNames))).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            let workTypeCounts = Dictionary(grouping: items, by: \.workType).mapValues(\.count)

            return FaultRecurrenceCustomerSummary(
                id: customerId,
                customerName: latest.customerName,
                workplace: latest.workplace,
                recurrenceCount: items.reduce(0) { $0 + $1.recurrenceCount },
                deviceCount: items.count,
                lastOccurrenceDate: items.map(\.lastOccurrenceDate).max() ?? latest.lastOccurrenceDate,
                technicianNames: technicians,
                workTypeCounts: workTypeCounts
            )
        }
        .sorted {
            if $0.recurrenceCount != $1.recurrenceCount { return $0.recurrenceCount > $1.recurrenceCount }
            return $0.lastOccurrenceDate > $1.lastOccurrenceDate
        }
    }

    static func workTypeSummaries(from entries: [FaultRecurrenceEntry]) -> [FaultRecurrenceWorkTypeSummary] {
        let grouped = Dictionary(grouping: entries, by: \.workType)
        return grouped.map { workType, items in
            FaultRecurrenceWorkTypeSummary(
                id: workType.rawValue,
                workType: workType,
                count: items.reduce(0) { $0 + $1.recurrenceCount }
            )
        }
        .sorted { $0.count > $1.count }
    }

    static func kpis(from entries: [FaultRecurrenceEntry]) -> FaultRecurrenceKPIs {
        let topDevice = entries.max(by: { lhs, rhs in
            if lhs.recurrenceCount != rhs.recurrenceCount {
                return lhs.recurrenceCount < rhs.recurrenceCount
            }
            return lhs.lastOccurrenceDate < rhs.lastOccurrenceDate
        })
        let customerSummaries = customerSummaries(from: entries)
        let topCustomer = customerSummaries.first

        return FaultRecurrenceKPIs(
            recurringFaultCount: entries.count,
            topDeviceLabel: topDevice.map { "\($0.deviceLabel) (\($0.serialNumber))" },
            topDeviceRecurrence: topDevice?.recurrenceCount ?? 0,
            topCustomerName: topCustomer?.customerName,
            topCustomerRecurrence: topCustomer?.recurrenceCount ?? 0
        )
    }

    static func detailRows(
        for entry: FaultRecurrenceEntry,
        orders: [WorkOrder],
        technicians: [UserID: User]
    ) -> [FaultRecurrenceDetailRow] {
        let orderMap = Dictionary(uniqueKeysWithValues: orders.map { ($0.id, $0) })
        return entry.workOrderIds.compactMap { orderMap[$0] }
            .sorted { occurrenceDate(for: $0) > occurrenceDate(for: $1) }
            .map { order in
                FaultRecurrenceDetailRow(
                    id: order.id,
                    workOrderNumber: order.workOrderNumber,
                    occurredAt: occurrenceDate(for: order),
                    technicianName: technicians[order.assignedTechnicianId]?.fullName ?? "Bilinmeyen",
                    issueDescription: order.issueDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? order.issueDescription!.trimmingCharacters(in: .whitespacesAndNewlines)
                        : "Belirtilmedi",
                    status: order.status,
                    deviceLabel: deviceLabel(for: order)
                )
            }
    }

    static func workplaceLabel(for customer: Customer?) -> String {
        guard let customer else { return "—" }
        if let city = customer.city, !city.isEmpty {
            return "\(customer.name) · \(city)"
        }
        return customer.address.isEmpty ? customer.name : customer.address
    }

    private static func deduplicatedOrders(_ orders: [WorkOrder]) -> [WorkOrder] {
        var seen = Set<WorkOrderID>()
        var result: [WorkOrder] = []
        for order in orders where seen.insert(order.id).inserted {
            result.append(order)
        }
        return result
    }

    private static func normalizedSerial(_ serialNumber: String) -> String {
        serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func occurrenceDate(for order: WorkOrder) -> Date {
        order.completedAt ?? order.scheduledDate
    }

    private static func issueLabel(from orders: [WorkOrder]) -> String {
        for order in orders {
            let trimmed = order.issueDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return "Belirtilmedi"
    }

    private static func deviceLabel(for order: WorkOrder) -> String {
        "\(order.deviceCategory.displayName) · \(order.serialNumber)"
    }

    private static func technicianNames(
        from orders: [WorkOrder],
        technicians: [UserID: User]
    ) -> [String] {
        Array(Set(orders.map { technicians[$0.assignedTechnicianId]?.fullName ?? "Bilinmeyen" }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func sortEntries(_ lhs: FaultRecurrenceEntry, _ rhs: FaultRecurrenceEntry) -> Bool {
        if lhs.recurrenceCount != rhs.recurrenceCount { return lhs.recurrenceCount > rhs.recurrenceCount }
        return lhs.lastOccurrenceDate > rhs.lastOccurrenceDate
    }
}
