import Foundation

/// Calendar-relative scheduling indicator for non-terminal work orders.
/// Uses `scheduledDate`, optional `scheduledTimeRange`, and `WorkOrderStatus`.
enum WorkOrderTimeStatus: String, Equatable, Sendable, CaseIterable {
    case delayed
    case windowPassed
    case today
    case approaching
    case scheduled

    var displayName: String {
        switch self {
        case .delayed: return "Gecikiyor"
        case .windowPassed: return "Süresi Geçti"
        case .today: return "Bugün"
        case .approaching: return "Yaklaşıyor"
        case .scheduled: return "Planlandı"
        }
    }

    var detailMessage: String {
        switch self {
        case .delayed:
            return "Planlanan gün geçti; iş henüz tamamlanmadı."
        case .windowPassed:
            return "Planlanan zaman aralığı sona erdi."
        case .today:
            return "Bugün planlanan iş."
        case .approaching:
            return "Planlanan başlangıç yaklaşıyor."
        case .scheduled:
            return "İleri tarihte planlandı."
        }
    }

    /// Matches dashboard `Geciken` KPI semantics.
    var countsAsDashboardOverdue: Bool {
        self == .delayed || self == .windowPassed
    }
}

enum WorkOrderTimeStatusPolicy {
    /// Hours before planned start when a future job becomes `Yaklaşıyor`.
    static let defaultApproachingLeadHours = 48

    /// Overdue when the planned window has passed and the job is not terminal.
    /// Same-calendar-day jobs without an explicit end time are not overdue until the day ends.
    static func isOverdue(
        _ order: WorkOrder,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard !order.status.isTerminal else { return false }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfScheduledDay = calendar.startOfDay(for: order.scheduledDate)

        if let range = order.scheduledTimeRange {
            let endDay = calendar.startOfDay(for: range.end)
            if endDay < startOfScheduledDay {
                // Stale window left from an earlier plan — compare scheduled day only.
                return startOfScheduledDay < startOfToday
            }
            return now > range.end
        }

        return startOfScheduledDay < startOfToday
    }

    static func timeStatus(
        for order: WorkOrder,
        now: Date,
        calendar: Calendar = .current,
        approachingLeadHours: Int = defaultApproachingLeadHours
    ) -> WorkOrderTimeStatus? {
        guard !order.status.isTerminal else { return nil }

        if isOverdue(order, now: now, calendar: calendar) {
            if calendar.isDate(order.scheduledDate, inSameDayAs: now) {
                return .windowPassed
            }
            return .delayed
        }

        if calendar.isDate(order.scheduledDate, inSameDayAs: now) {
            return .today
        }

        if isApproaching(
            order: order,
            now: now,
            calendar: calendar,
            approachingLeadHours: approachingLeadHours
        ) {
            return .approaching
        }

        return .scheduled
    }

    static func filter(
        _ orders: [WorkOrder],
        matching timeStatus: WorkOrderTimeStatus,
        now: Date,
        calendar: Calendar = .current
    ) -> [WorkOrder] {
        orders.filter {
            self.timeStatus(for: $0, now: now, calendar: calendar) == timeStatus
        }
    }

    static func filterDashboardOverdue(
        _ orders: [WorkOrder],
        now: Date,
        calendar: Calendar = .current
    ) -> [WorkOrder] {
        orders.filter { isOverdue($0, now: now, calendar: calendar) }
    }

    private static func plannedStart(for order: WorkOrder) -> Date {
        order.scheduledTimeRange?.start ?? order.scheduledDate
    }

    private static func isApproaching(
        order: WorkOrder,
        now: Date,
        calendar: Calendar,
        approachingLeadHours: Int
    ) -> Bool {
        let start = plannedStart(for: order)
        guard start > now else { return false }

        if calendar.isDateInTomorrow(order.scheduledDate) {
            return true
        }

        let lead = TimeInterval(approachingLeadHours) * 3600
        return start.timeIntervalSince(now) <= lead
    }
}
