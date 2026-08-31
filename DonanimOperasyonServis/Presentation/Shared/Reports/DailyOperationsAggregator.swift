import Foundation

enum DailyOperationsAggregator {
    static func buildReport(
        selectedDay: Date,
        orders: [WorkOrder],
        customers: [CustomerID: Customer],
        technicians: [UserID: User],
        activeTechnicians: [User],
        statusHistories: [WorkOrderID: [WorkOrderStatusHistory]],
        calendar: Calendar = .current
    ) -> DailyOperationsReport {
        let day = calendar.startOfDay(for: selectedDay)
        let reference = referenceMoment(for: day, calendar: calendar)
        let planned = plannedForDay(orders, day: day, calendar: calendar)

        return DailyOperationsReport(
            selectedDay: day,
            kpis: kpis(
                orders: orders,
                planned: planned,
                day: day,
                reference: reference,
                activeTechnicians: activeTechnicians,
                calendar: calendar
            ),
            technicianSummaries: technicianSummaries(
                planned: planned,
                day: day,
                technicians: technicians,
                calendar: calendar
            ),
            customerSummary: customerSummary(
                orders: orders,
                day: day,
                calendar: calendar
            ),
            workflowEntries: workflowEntries(
                planned: planned,
                customers: customers,
                technicians: technicians
            ),
            delayedEntries: delayedEntries(
                planned: planned,
                reference: reference,
                customers: customers,
                technicians: technicians,
                calendar: calendar
            ),
            pauseSummary: pauseSummary(
                planned: planned,
                day: day,
                customers: customers,
                technicians: technicians,
                statusHistories: statusHistories,
                calendar: calendar
            )
        )
    }

    static func referenceMoment(for day: Date, calendar: Calendar = .current) -> Date {
        let todayStart = calendar.startOfDay(for: Date())
        let selectedStart = calendar.startOfDay(for: day)
        if selectedStart >= todayStart {
            return Date()
        }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: selectedStart) ?? selectedStart
        return nextDay.addingTimeInterval(-1)
    }

    static func isOnDay(_ date: Date, day: Date, calendar: Calendar) -> Bool {
        calendar.isDate(date, inSameDayAs: day)
    }

    static func plannedForDay(_ orders: [WorkOrder], day: Date, calendar: Calendar) -> [WorkOrder] {
        orders.filter { isOnDay($0.scheduledDate, day: day, calendar: calendar) }
    }

    private static func kpis(
        orders: [WorkOrder],
        planned: [WorkOrder],
        day: Date,
        reference: Date,
        activeTechnicians: [User],
        calendar: Calendar
    ) -> DailyOperationsKPIs {
        let opened = orders.filter { isOnDay($0.createdAt, day: day, calendar: calendar) }
        let completed = orders.filter {
            $0.status == .completed
                && ($0.completedAt.map { isOnDay($0, day: day, calendar: calendar) } ?? false)
        }
        let inProgress = planned.filter { $0.status.isActivelyInField }
        let paused = planned.filter { $0.status == .paused }
        let urgent = planned.filter { $0.priority == .urgent && !$0.status.isTerminal }
        let delayed = WorkOrderTimeStatusPolicy.filterDashboardOverdue(
            planned,
            now: reference,
            calendar: calendar
        )
        let rejected = orders.filter {
            $0.status == .rejected
                && (isOnDay($0.createdAt, day: day, calendar: calendar)
                    || isOnDay($0.updatedAt, day: day, calendar: calendar))
        }

        let plannedNonRejected = planned.filter { $0.status != .rejected }
        let completedPlanned = planned.filter {
            $0.status == .completed
                && ($0.completedAt.map { isOnDay($0, day: day, calendar: calendar) } ?? false)
        }
        let completionRate = plannedNonRejected.isEmpty
            ? 0
            : Double(completedPlanned.count) / Double(plannedNonRejected.count) * 100

        let assignedTechnicianCount = Set(planned.map(\.assignedTechnicianId)).count

        return DailyOperationsKPIs(
            openedCount: opened.count,
            completedCount: completed.count,
            inProgressCount: inProgress.count,
            pausedCount: paused.count,
            urgentCount: urgent.count,
            delayedCount: delayed.count,
            rejectedCount: rejected.count,
            completionRate: completionRate,
            activeTechnicianCount: activeTechnicians.filter(\.isActive).count,
            assignedTechnicianCount: assignedTechnicianCount
        )
    }

    private static func technicianSummaries(
        planned: [WorkOrder],
        day: Date,
        technicians: [UserID: User],
        calendar: Calendar
    ) -> [DailyTechnicianSummary] {
        let grouped = Dictionary(grouping: planned, by: \.assignedTechnicianId)
        return grouped.map { techId, items in
            let completed = items.filter {
                $0.status == .completed
                    && ($0.completedAt.map { isOnDay($0, day: day, calendar: calendar) } ?? false)
            }
            let completionHours = completed.compactMap { order -> Double? in
                guard let completedAt = order.completedAt else { return nil }
                return max(0, completedAt.timeIntervalSince(order.createdAt) / 3600)
            }
            let averageHours = completionHours.isEmpty
                ? nil
                : completionHours.reduce(0, +) / Double(completionHours.count)

            return DailyTechnicianSummary(
                id: techId,
                name: technicians[techId]?.fullName ?? techId.rawValue,
                assignedCount: items.count,
                completedCount: completed.count,
                inProgressCount: items.filter { $0.status.isActivelyInField }.count,
                pausedCount: items.filter { $0.status == .paused }.count,
                urgentCount: items.filter { $0.priority == .urgent }.count,
                highCount: items.filter { $0.priority == .high }.count,
                normalCount: items.filter { $0.priority == .normal }.count,
                completionRate: items.isEmpty ? 0 : Double(completed.count) / Double(items.count) * 100,
                averageCompletionHours: averageHours
            )
        }
        .sorted {
            if $0.completedCount != $1.completedCount { return $0.completedCount > $1.completedCount }
            if $0.assignedCount != $1.assignedCount { return $0.assignedCount > $1.assignedCount }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func customerSummary(
        orders: [WorkOrder],
        day: Date,
        calendar: Calendar
    ) -> DailyCustomerOperationSummary {
        let relevant = orders.filter { order in
            isOnDay(order.scheduledDate, day: day, calendar: calendar)
                || isOnDay(order.createdAt, day: day, calendar: calendar)
                || (order.completedAt.map { isOnDay($0, day: day, calendar: calendar) } ?? false)
        }
        let nonRejected = relevant.filter { $0.status != .rejected }

        return DailyCustomerOperationSummary(
            uniqueCustomerCount: Set(nonRejected.map(\.customerId)).count,
            workTypeCounts: Dictionary(grouping: nonRejected, by: \.workType).mapValues(\.count),
            deviceCategoryCounts: Dictionary(grouping: nonRejected, by: \.deviceCategory).mapValues(\.count)
        )
    }

    private static func workflowEntries(
        planned: [WorkOrder],
        customers: [CustomerID: Customer],
        technicians: [UserID: User]
    ) -> [DailyWorkflowEntry] {
        planned
            .sorted { plannedStart(for: $0) < plannedStart(for: $1) }
            .map { order in
                DailyWorkflowEntry(
                    id: order.id,
                    plannedTime: plannedStart(for: order),
                    workOrderNumber: order.workOrderNumber,
                    customerName: customers[order.customerId]?.name ?? "Bilinmeyen müşteri",
                    technicianName: technicians[order.assignedTechnicianId]?.fullName ?? "Bilinmeyen",
                    workType: order.workType,
                    priority: order.priority,
                    status: order.status
                )
            }
    }

    private static func delayedEntries(
        planned: [WorkOrder],
        reference: Date,
        customers: [CustomerID: Customer],
        technicians: [UserID: User],
        calendar: Calendar
    ) -> [DailyDelayedEntry] {
        WorkOrderTimeStatusPolicy.filterDashboardOverdue(planned, now: reference, calendar: calendar)
            .sorted { plannedStart(for: $0) < plannedStart(for: $1) }
            .map { order in
                DailyDelayedEntry(
                    id: order.id,
                    workOrderNumber: order.workOrderNumber,
                    customerName: customers[order.customerId]?.name ?? "Bilinmeyen müşteri",
                    technicianName: technicians[order.assignedTechnicianId]?.fullName ?? "Bilinmeyen"
                )
            }
    }

    private static func pauseSummary(
        planned: [WorkOrder],
        day: Date,
        customers: [CustomerID: Customer],
        technicians: [UserID: User],
        statusHistories: [WorkOrderID: [WorkOrderStatusHistory]],
        calendar: Calendar
    ) -> DailyPauseSummary {
        var entries: [PauseReportEntry] = []

        for order in planned {
            let customer = customers[order.customerId]
            let history = statusHistories[order.id] ?? []
            let pauseEvents = history.filter {
                $0.toStatus == .paused && isOnDay($0.occurredAt, day: day, calendar: calendar)
            }

            if pauseEvents.isEmpty, order.status == .paused, isOnDay(order.updatedAt, day: day, calendar: calendar) {
                entries.append(
                    PauseReportEntry(
                        id: "\(order.id.rawValue)-active",
                        workOrderId: order.id,
                        workOrderNumber: order.workOrderNumber,
                        customerName: customer?.name ?? "Bilinmeyen müşteri",
                        workplace: workplaceLabel(for: customer),
                        technicianName: technicians[order.assignedTechnicianId]?.fullName ?? "Bilinmeyen",
                        pauseReason: order.currentPauseReason ?? .other,
                        startedAt: order.updatedAt,
                        endedAt: nil,
                        isActive: true
                    )
                )
                continue
            }

            for event in pauseEvents {
                let resume = history.first {
                    $0.fromStatus == .paused && $0.occurredAt > event.occurredAt
                }
                entries.append(
                    PauseReportEntry(
                        id: event.id,
                        workOrderId: order.id,
                        workOrderNumber: order.workOrderNumber,
                        customerName: customer?.name ?? "Bilinmeyen müşteri",
                        workplace: workplaceLabel(for: customer),
                        technicianName: technicians[order.assignedTechnicianId]?.fullName ?? "Bilinmeyen",
                        pauseReason: event.pauseReason ?? order.currentPauseReason ?? .other,
                        startedAt: event.occurredAt,
                        endedAt: resume?.occurredAt,
                        isActive: order.status == .paused && resume == nil
                    )
                )
            }
        }

        let reasonCounts = Dictionary(grouping: entries, by: \.pauseReason).mapValues(\.count)
        let durations = entries.map { entry -> TimeInterval in
            let end = entry.endedAt ?? referenceMoment(for: day, calendar: calendar)
            return max(0, end.timeIntervalSince(entry.startedAt))
        }
        let averagePause = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)

        return DailyPauseSummary(
            pausedCount: entries.count,
            reasonCounts: reasonCounts,
            averagePauseDurationSeconds: averagePause,
            entries: entries.sorted { $0.startedAt < $1.startedAt }
        )
    }

    private static func plannedStart(for order: WorkOrder) -> Date {
        order.scheduledTimeRange?.start ?? order.scheduledDate
    }

    private static func workplaceLabel(for customer: Customer?) -> String {
        guard let customer else { return "—" }
        if let city = customer.city, !city.isEmpty {
            return "\(customer.name) · \(city)"
        }
        return customer.address.isEmpty ? customer.name : customer.address
    }
}
