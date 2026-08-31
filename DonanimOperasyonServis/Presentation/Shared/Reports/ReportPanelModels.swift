import Foundation

struct AdminReportMetric: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let value: String
}

struct AdminStatusBreakdown: Identifiable, Equatable, Sendable {
    let id: String
    let status: WorkOrderStatus
    let count: Int
    let percentage: Double
}

struct WorkOrderReportEntry: Identifiable, Equatable, Sendable {
    let id: WorkOrderID
    let workOrderNumber: String
    let customerName: String
    let workplace: String
    let technicianName: String
    let priority: WorkOrderPriority
    let status: WorkOrderStatus
    let scheduledDate: Date
    let deviceLabel: String
    let workType: WorkType
    let signatureStatusLabel: String
    let photoCount: Int

    var subtitle: String {
        [
            customerName,
            workplace,
            technicianName,
            priority.displayName,
            status.displayName,
            WorkOrderPresentationMapping.formatDate(scheduledDate),
            deviceLabel,
            workType.displayName,
            signatureStatusLabel,
            photoCount > 0 ? "Fotoğraf: \(photoCount)" : nil
        ].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }
}

struct SignatureReportEntry: Identifiable, Equatable, Sendable {
    let id: String
    let signature: Signature
    let workOrderId: WorkOrderID
    let workOrderNumber: String
    let customerName: String
    let workplace: String
    let technicianName: String
    let signerName: String?
    let capturedAt: Date
    let statusLabel: String

    var displayTitle: String {
        signerName?.isEmpty == false ? signerName! : signature.kind.displayName
    }

    var subtitle: String {
        [
            customerName,
            workplace,
            workOrderNumber,
            technicianName,
            WorkOrderPresentationMapping.formatDateTime(capturedAt),
            statusLabel
        ].joined(separator: " · ")
    }
}

struct PhotoReportEntry: Identifiable, Equatable, Sendable {
    let id: String
    let photo: WorkOrderPhoto
    let workOrderId: WorkOrderID
    let workOrderNumber: String
    let customerName: String
    let workplace: String
    let technicianName: String
    let capturedAt: Date
    let categoryLabel: String

    var subtitle: String {
        [
            customerName,
            workplace,
            workOrderNumber,
            technicianName,
            WorkOrderPresentationMapping.formatDateTime(capturedAt),
            categoryLabel
        ].joined(separator: " · ")
    }
}

struct PauseReportEntry: Identifiable, Equatable, Sendable {
    let id: String
    let workOrderId: WorkOrderID
    let workOrderNumber: String
    let customerName: String
    let workplace: String
    let technicianName: String
    let pauseReason: PauseReason
    let startedAt: Date
    let endedAt: Date?
    let isActive: Bool

    var durationLabel: String {
        let end = endedAt ?? Date()
        let seconds = max(0, end.timeIntervalSince(startedAt))
        let hours = Int(seconds / 3600)
        let minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        if hours > 0 { return "\(hours) sa \(minutes) dk" }
        return "\(minutes) dk"
    }

    var subtitle: String {
        [
            pauseReason.displayName,
            workOrderNumber,
            customerName,
            technicianName,
            WorkOrderPresentationMapping.formatDateTime(startedAt),
            isActive ? "Devam ediyor" : durationLabel
        ].joined(separator: " · ")
    }
}

struct TechnicianPerformanceEntry: Identifiable, Equatable, Sendable {
    let id: UserID
    let name: String
    let totalAssigned: Int
    let completed: Int
    let inProgress: Int
    let paused: Int
    let rejected: Int
    let urgent: Int
    let high: Int
    let normal: Int
    let completionRate: Double
    let averageCompletionDays: Double?

    var workloadSummary: String {
        "Acil: \(urgent) · Yüksek: \(high) · Normal: \(normal)"
    }

    var statusSummary: String {
        "Tamamlanan: \(completed) · Devam: \(inProgress) · Beklemede: \(paused)"
    }
}

struct CustomerAnalyticsPickerCard: Identifiable, Equatable, Sendable {
    let id: CustomerID
    let customer: Customer
    let workplace: String
    let totalVisits: Int
    let shortSummary: String
}

struct CustomerAnalyticsSummary: Equatable, Sendable {
    let customerId: CustomerID
    let customerName: String
    let workplace: String
    let totalVisits: Int
    let completedVisits: Int
    let totalOrders: Int
    let completedOrders: Int
    let pausedOrders: Int
    let inProgressOrders: Int
    let lastVisitDate: Date?
}

struct CustomerTechnicianVisitEntry: Identifiable, Equatable, Sendable {
    let id: String
    let technicianId: UserID
    let technicianName: String
    let visitCount: Int
    let lastVisit: Date?
}

struct CustomerOperationEntry: Identifiable, Equatable, Sendable {
    let id: String
    let workType: WorkType
    let count: Int
}

struct CustomerDeviceEntry: Identifiable, Equatable, Sendable {
    let id: String
    let deviceCategory: DeviceCategory
    let count: Int
}

struct CustomerTimelineEntry: Identifiable, Equatable, Sendable {
    let id: WorkOrderID
    let date: Date
    let workOrderNumber: String
    let technicianName: String
    let workType: WorkType
    let deviceCategory: DeviceCategory
    let status: WorkOrderStatus
}

struct FaultRecurrenceKPIs: Equatable, Sendable {
    let recurringFaultCount: Int
    let topDeviceLabel: String?
    let topDeviceRecurrence: Int
    let topCustomerName: String?
    let topCustomerRecurrence: Int
}

struct FaultRecurrenceEntry: Identifiable, Equatable, Sendable, Hashable {
    let id: String
    let customerId: CustomerID
    let customerName: String
    let workplace: String
    let serialNumber: String
    let deviceLabel: String
    let workType: WorkType
    let issueLabel: String
    let recurrenceCount: Int
    let lastOccurrenceDate: Date
    let technicianNames: [String]
    let workOrderIds: [WorkOrderID]

    var technicianSummary: String {
        technicianNames.joined(separator: ", ")
    }

    var subtitle: String {
        [
            deviceLabel,
            "Arıza: \(issueLabel)",
            "Tekrar: \(recurrenceCount)",
            "Son işlem: \(WorkOrderPresentationMapping.formatDate(lastOccurrenceDate))",
            technicianNames.isEmpty ? nil : "Teknisyenler: \(technicianSummary)"
        ].compactMap { $0 }.joined(separator: " · ")
    }
}

struct FaultRecurrenceCustomerSummary: Identifiable, Equatable, Sendable {
    let id: CustomerID
    let customerName: String
    let workplace: String
    let recurrenceCount: Int
    let deviceCount: Int
    let lastOccurrenceDate: Date
    let technicianNames: [String]
    let workTypeCounts: [WorkType: Int]
}

struct FaultRecurrenceWorkTypeSummary: Identifiable, Equatable, Sendable {
    let id: String
    let workType: WorkType
    let count: Int
}

struct FaultRecurrenceDetailRow: Identifiable, Equatable, Sendable {
    let id: WorkOrderID
    let workOrderNumber: String
    let occurredAt: Date
    let technicianName: String
    let issueDescription: String
    let status: WorkOrderStatus
    let deviceLabel: String
}

struct DailyOperationsKPIs: Equatable, Sendable {
    let openedCount: Int
    let completedCount: Int
    let inProgressCount: Int
    let pausedCount: Int
    let urgentCount: Int
    let delayedCount: Int
    let rejectedCount: Int
    let completionRate: Double
    let activeTechnicianCount: Int
    let assignedTechnicianCount: Int
}

struct DailyTechnicianSummary: Identifiable, Equatable, Sendable {
    let id: UserID
    let name: String
    let assignedCount: Int
    let completedCount: Int
    let inProgressCount: Int
    let pausedCount: Int
    let urgentCount: Int
    let highCount: Int
    let normalCount: Int
    let completionRate: Double
    let averageCompletionHours: Double?
}

struct DailyCustomerOperationSummary: Equatable, Sendable {
    let uniqueCustomerCount: Int
    let workTypeCounts: [WorkType: Int]
    let deviceCategoryCounts: [DeviceCategory: Int]
}

struct DailyWorkflowEntry: Identifiable, Equatable, Sendable {
    let id: WorkOrderID
    let plannedTime: Date
    let workOrderNumber: String
    let customerName: String
    let technicianName: String
    let workType: WorkType
    let priority: WorkOrderPriority
    let status: WorkOrderStatus
}

struct DailyDelayedEntry: Identifiable, Equatable, Sendable {
    let id: WorkOrderID
    let workOrderNumber: String
    let customerName: String
    let technicianName: String
}

struct DailyPauseSummary: Equatable, Sendable {
    let pausedCount: Int
    let reasonCounts: [PauseReason: Int]
    let averagePauseDurationSeconds: Double?
    let entries: [PauseReportEntry]
}

struct DailyOperationsReport: Equatable, Sendable {
    let selectedDay: Date
    let kpis: DailyOperationsKPIs
    let technicianSummaries: [DailyTechnicianSummary]
    let customerSummary: DailyCustomerOperationSummary
    let workflowEntries: [DailyWorkflowEntry]
    let delayedEntries: [DailyDelayedEntry]
    let pauseSummary: DailyPauseSummary

    var isEmpty: Bool {
        kpis.openedCount == 0
            && kpis.completedCount == 0
            && workflowEntries.isEmpty
            && kpis.rejectedCount == 0
    }
}

struct ReportDetailPayload: Equatable, Sendable {
    var metrics: [AdminReportMetric] = []
    var statusBreakdown: [AdminStatusBreakdown] = []
    var workOrderEntries: [WorkOrderReportEntry] = []
    var signatureEntries: [SignatureReportEntry] = []
    var photoEntries: [PhotoReportEntry] = []
    var pauseEntries: [PauseReportEntry] = []
    var technicianEntries: [TechnicianPerformanceEntry] = []
    var faultRecurrenceEntries: [FaultRecurrenceEntry] = []

    var isEmpty: Bool {
        metrics.isEmpty && statusBreakdown.isEmpty
            && workOrderEntries.isEmpty && signatureEntries.isEmpty
            && photoEntries.isEmpty && pauseEntries.isEmpty
            && technicianEntries.isEmpty
            && faultRecurrenceEntries.isEmpty
    }
}
