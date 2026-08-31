import Foundation

enum ReportSearchFilters {
    static func filterWorkOrders(_ entries: [WorkOrderReportEntry], query: String) -> [WorkOrderReportEntry] {
        filter(entries, query: query) { entry in
            [
                entry.workOrderNumber,
                entry.customerName,
                entry.workplace,
                entry.technicianName,
                entry.priority.displayName,
                entry.status.displayName,
                entry.deviceLabel,
                entry.workType.displayName,
                entry.signatureStatusLabel,
                WorkOrderPresentationMapping.formatDate(entry.scheduledDate)
            ]
        }
    }

    static func filterSignatures(_ entries: [SignatureReportEntry], query: String) -> [SignatureReportEntry] {
        filter(entries, query: query) { entry in
            [
                entry.displayTitle,
                entry.signerName,
                entry.customerName,
                entry.workplace,
                entry.workOrderNumber,
                entry.technicianName,
                entry.statusLabel,
                WorkOrderPresentationMapping.formatDate(entry.capturedAt),
                WorkOrderPresentationMapping.formatDateTime(entry.capturedAt)
            ]
        }
    }

    static func filterPhotos(_ entries: [PhotoReportEntry], query: String) -> [PhotoReportEntry] {
        filter(entries, query: query) { entry in
            [
                entry.customerName,
                entry.workplace,
                entry.workOrderNumber,
                entry.technicianName,
                entry.categoryLabel,
                WorkOrderPresentationMapping.formatDate(entry.capturedAt),
                WorkOrderPresentationMapping.formatDateTime(entry.capturedAt)
            ]
        }
    }

    static func filterPauses(_ entries: [PauseReportEntry], query: String) -> [PauseReportEntry] {
        filter(entries, query: query) { entry in
            [
                entry.customerName,
                entry.workplace,
                entry.workOrderNumber,
                entry.technicianName,
                entry.pauseReason.displayName,
                WorkOrderPresentationMapping.formatDateTime(entry.startedAt)
            ]
        }
    }

    static func filterTechnicians(_ entries: [TechnicianPerformanceEntry], query: String) -> [TechnicianPerformanceEntry] {
        filter(entries, query: query) { entry in
            [entry.name]
        }
    }

    static func filterCustomersForAnalytics(_ customers: [Customer], query: String) -> [Customer] {
        filter(customers, query: query) { customer in
            [
                customer.name,
                customer.address,
                customer.city,
                customer.id.rawValue
            ]
        }
    }

    static func filterFaultRecurrenceEntries(
        _ entries: [FaultRecurrenceEntry],
        query: String,
        workType: WorkType?,
        dateFrom: Date?,
        dateTo: Date?
    ) -> [FaultRecurrenceEntry] {
        var result = filter(entries, query: query) { entry in
            [
                entry.customerName,
                entry.workplace,
                entry.serialNumber,
                entry.deviceLabel,
                entry.issueLabel,
                entry.workType.displayName,
                entry.technicianSummary
            ] + entry.technicianNames
        }

        if let workType {
            result = result.filter { $0.workType == workType }
        }

        if let dateFrom {
            let start = Calendar.current.startOfDay(for: dateFrom)
            result = result.filter { $0.lastOccurrenceDate >= start }
        }

        if let dateTo {
            let end = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: Calendar.current.startOfDay(for: dateTo)) ?? dateTo
            result = result.filter { $0.lastOccurrenceDate <= end }
        }

        return result
    }

    private static func filter<T>(
        _ items: [T],
        query: String,
        fields: (T) -> [String?]
    ) -> [T] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { item in
            TurkishSearchFilter.matches(query: trimmed, in: fields(item).compactMap { $0 })
        }
    }
}
