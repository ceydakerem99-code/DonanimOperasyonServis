import Foundation

enum WorkOrderPresentationMapping {

    static func appStatus(from status: WorkOrderStatus) -> AppStatus {
        switch status {
        case .assigned:   return .assigned
        case .accepted:   return .accepted
        case .rejected:   return .rejected
        case .enRoute:    return .enRoute
        case .arrived:    return .arrived
        case .inProgress: return .inProgress
        case .paused:     return .paused
        case .completed:  return .completed
        }
    }

    static func appPriority(from priority: WorkOrderPriority) -> AppPriority {
        switch priority {
        case .normal: return .normal
        case .high:   return .high
        case .urgent: return .urgent
        }
    }

    static func statusStepIndex(for status: WorkOrderStatus) -> Int {
        switch status {
        case .assigned:   return 1
        case .accepted:   return 2
        case .rejected:   return 1
        case .enRoute:    return 3
        case .arrived:    return 4
        case .inProgress: return 5
        case .paused:     return 5
        case .completed:  return 6
        }
    }

    static let statusFlowTitles = [
        "Açıldı",
        "Kabul Edildi",
        "Yola Çıktı",
        "Müşteriye Varış",
        "İşlemde",
        "Tamamlandı"
    ]

    static func cardData(
        from order: WorkOrder,
        customerName: String,
        technicianName: String?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WorkOrderCardData {
        WorkOrderCardData(
            id: order.id.rawValue,
            workOrderNumber: order.workOrderNumber,
            customerName: customerName,
            workTypeLabel: order.workType.displayName,
            deviceLabel: order.deviceCategory.displayName,
            status: appStatus(from: order.status),
            priority: appPriority(from: order.priority),
            timeStatus: WorkOrderTimeStatusPolicy.timeStatus(for: order, now: now, calendar: calendar),
            plannedDateLabel: formatDate(order.scheduledDate),
            plannedTimeLabel: formatTimeRange(order.scheduledTimeRange, fallback: order.scheduledDate),
            technicianName: technicianName
        )
    }

    static func plannedScheduleLabel(for order: WorkOrder) -> String {
        if let range = order.scheduledTimeRange {
            return "\(formatDate(order.scheduledDate)) · \(formatTime(range.start)) – \(formatTime(range.end))"
        }
        return formatDateTime(order.scheduledDate)
    }

    static func timeStatus(
        for order: WorkOrder,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WorkOrderTimeStatus? {
        WorkOrderTimeStatusPolicy.timeStatus(for: order, now: now, calendar: calendar)
    }

    static func formatDate(_ date: Date) -> String {
        WorkOrderDateFormatting.date.string(from: date)
    }

    static func formatTime(_ date: Date) -> String {
        WorkOrderDateFormatting.time.string(from: date)
    }

    static func formatTimeRange(_ range: ScheduledTimeRange?, fallback: Date) -> String? {
        if let range {
            let start = WorkOrderDateFormatting.time.string(from: range.start)
            let end = WorkOrderDateFormatting.time.string(from: range.end)
            return "\(start) – \(end)"
        }
        return WorkOrderDateFormatting.time.string(from: fallback)
    }

    static func formatDateTime(_ date: Date) -> String {
        "\(formatDate(date)) · \(formatTime(date))"
    }

    static func isActiveStatus(_ status: WorkOrderStatus) -> Bool {
        switch status {
        case .accepted, .enRoute, .arrived, .inProgress:
            return true
        case .assigned, .rejected, .paused, .completed:
            return false
        }
    }

    /// Inclusive calendar-day check on `WorkOrder.scheduledDate`.
    static func isScheduled(onDayOf reference: Date, date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, inSameDayAs: reference)
    }

    static func scheduledDayBounds(
        for reference: Date = Date(),
        calendar: Calendar = .current
    ) -> (from: Date, to: Date) {
        let start = calendar.startOfDay(for: reference)
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? start
        return (start, end)
    }
}

private enum WorkOrderDateFormatting {
    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let greetingDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMMM yyyy, EEEE"
        return formatter
    }()
}

extension WorkOrderPresentationMapping {
    static func greetingDate(_ date: Date = Date()) -> String {
        WorkOrderDateFormatting.greetingDate.string(from: date)
    }
}
