import Foundation

enum ReportDatasetBuilder {
    private static let childFetchConcurrency = 5

    struct Repositories: Sendable {
        let customerRepository: CustomerRepository
        let userRepository: UserRepository
        let signatureRepository: SignatureRepository
        let workOrderPhotoRepository: WorkOrderPhotoRepository
        let statusHistoryRepository: WorkOrderStatusHistoryRepository
    }

    static func build(
        kind: AdminReportKind,
        orders: [WorkOrder],
        repositories: Repositories
    ) async -> ReportDetailPayload {
        let customers = await loadCustomers(for: orders, repository: repositories.customerRepository)
        let technicians = await loadTechnicians(for: orders, repository: repositories.userRepository)

        switch kind {
        case .workOrders:
            return await buildWorkOrdersReport(orders: orders, customers: customers, technicians: technicians, repositories: repositories)
        case .technicianPerformance:
            return buildTechnicianPerformanceReport(orders: orders, technicians: technicians)
        case .pauseReasons:
            return await buildPauseReport(orders: orders, customers: customers, technicians: technicians, repositories: repositories)
        case .signatures:
            return await buildSignatureReport(orders: orders, customers: customers, technicians: technicians, repositories: repositories)
        case .photos:
            return await buildPhotoReport(orders: orders, customers: customers, technicians: technicians, repositories: repositories)
        case .customerAnalytics:
            return ReportDetailPayload()
        case .customerSatisfaction:
            return ReportDetailPayload()
        case .faultRecurrence:
            return ReportDetailPayload()
        case .dailyOperations:
            return ReportDetailPayload()
        }
    }

    private static func buildWorkOrdersReport(
        orders: [WorkOrder],
        customers: [CustomerID: Customer],
        technicians: [UserID: User],
        repositories: Repositories
    ) async -> ReportDetailPayload {
        let signatures = await loadSignatures(for: orders.map(\.id), repository: repositories.signatureRepository)
        let photos = await loadPhotos(for: orders.map(\.id), repository: repositories.workOrderPhotoRepository)

        let total = orders.count
        let completed = orders.filter { $0.status == .completed }.count
        let completionRate = total > 0 ? Double(completed) / Double(total) * 100 : 0

        var payload = ReportDetailPayload(
            metrics: [
                AdminReportMetric(id: "total", title: "Toplam İş Emri", value: "\(total)"),
                AdminReportMetric(id: "completed", title: "Tamamlanan", value: "\(completed)"),
                AdminReportMetric(id: "rate", title: "Tamamlanma Oranı", value: String(format: "%.0f%%", completionRate))
            ],
            statusBreakdown: statusBreakdown(from: orders)
        )

        payload.workOrderEntries = orders
            .sorted { $0.scheduledDate > $1.scheduledDate }
            .map { order in
                let customer = customers[order.customerId]
                let sigCount = signatures[order.id]?.count ?? 0
                return WorkOrderReportEntry(
                    id: order.id,
                    workOrderNumber: order.workOrderNumber,
                    customerName: customer?.name ?? "Bilinmeyen müşteri",
                    workplace: workplaceLabel(for: customer),
                    technicianName: technicians[order.assignedTechnicianId]?.fullName ?? "Bilinmeyen",
                    priority: order.priority,
                    status: order.status,
                    scheduledDate: order.scheduledDate,
                    deviceLabel: deviceLabel(for: order),
                    workType: order.workType,
                    signatureStatusLabel: sigCount > 0 ? "İmzalı" : "İmzasız",
                    photoCount: photos[order.id]?.count ?? 0
                )
            }
        return payload
    }

    private static func buildTechnicianPerformanceReport(
        orders: [WorkOrder],
        technicians: [UserID: User]
    ) -> ReportDetailPayload {
        var grouped: [UserID: [WorkOrder]] = [:]
        for order in orders {
            grouped[order.assignedTechnicianId, default: []].append(order)
        }

        let entries = grouped.map { techId, items -> TechnicianPerformanceEntry in
            let completed = items.filter { $0.status == .completed }
            let completionDays = completed.compactMap { order -> Double? in
                guard let completedAt = order.completedAt else { return nil }
                return completedAt.timeIntervalSince(order.createdAt) / 86_400
            }
            let avgDays = completionDays.isEmpty ? nil : completionDays.reduce(0, +) / Double(completionDays.count)
            return TechnicianPerformanceEntry(
                id: techId,
                name: technicians[techId]?.fullName ?? techId.rawValue,
                totalAssigned: items.count,
                completed: completed.count,
                inProgress: items.filter { $0.status == .inProgress || $0.status.isActivelyInField }.count,
                paused: items.filter { $0.status == .paused }.count,
                rejected: items.filter { $0.status == .rejected }.count,
                urgent: items.filter { $0.priority == .urgent }.count,
                high: items.filter { $0.priority == .high }.count,
                normal: items.filter { $0.priority == .normal }.count,
                completionRate: items.isEmpty ? 0 : Double(completed.count) / Double(items.count) * 100,
                averageCompletionDays: avgDays
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return ReportDetailPayload(
            metrics: entries.map {
                AdminReportMetric(
                    id: $0.id.rawValue,
                    title: $0.name,
                    value: String(format: "%.0f%% tamamlanma · %@", $0.completionRate, $0.statusSummary)
                )
            },
            technicianEntries: entries
        )
    }

    private static func buildPauseReport(
        orders: [WorkOrder],
        customers: [CustomerID: Customer],
        technicians: [UserID: User],
        repositories: Repositories
    ) async -> ReportDetailPayload {
        let pausedOrders = orders.filter { $0.status == .paused || $0.currentPauseReason != nil }
        let historyTargets = Set(pausedOrders.map(\.id))
        let histories = await loadStatusHistories(for: Array(historyTargets), repository: repositories.statusHistoryRepository)

        var entries: [PauseReportEntry] = []
        for order in pausedOrders {
            let customer = customers[order.customerId]
            let history = histories[order.id] ?? []
            let pauseEvents = history.filter { $0.toStatus == .paused }
            if pauseEvents.isEmpty, order.status == .paused {
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

        let grouped = Dictionary(grouping: entries, by: \.pauseReason)
        let metrics = PauseReason.allCases.map { reason in
            AdminReportMetric(
                id: reason.rawValue,
                title: reason.displayName,
                value: "\(grouped[reason]?.count ?? 0)"
            )
        }

        return ReportDetailPayload(
            metrics: metrics,
            pauseEntries: entries.sorted { $0.startedAt > $1.startedAt }
        )
    }

    private static func buildSignatureReport(
        orders: [WorkOrder],
        customers: [CustomerID: Customer],
        technicians: [UserID: User],
        repositories: Repositories
    ) async -> ReportDetailPayload {
        let completed = orders.filter { $0.status == .completed }
        let signatures = await loadSignatures(for: completed.map(\.id), repository: repositories.signatureRepository)

        var entries: [SignatureReportEntry] = []
        var totalSignatures = 0
        for order in completed {
            let sigs = signatures[order.id] ?? []
            totalSignatures += sigs.count
            let customer = customers[order.customerId]
            for signature in sigs {
                entries.append(
                    SignatureReportEntry(
                        id: signature.id,
                        signature: signature,
                        workOrderId: order.id,
                        workOrderNumber: order.workOrderNumber,
                        customerName: customer?.name ?? "Bilinmeyen müşteri",
                        workplace: workplaceLabel(for: customer),
                        technicianName: technicians[order.assignedTechnicianId]?.fullName ?? "Bilinmeyen",
                        signerName: signature.signerName,
                        capturedAt: signature.capturedAt,
                        statusLabel: "İmzalı"
                    )
                )
            }
        }

        return ReportDetailPayload(
            metrics: [
                AdminReportMetric(id: "completed", title: "Tamamlanan İş Emri", value: "\(completed.count)"),
                AdminReportMetric(id: "signatures", title: "Toplam İmza", value: "\(totalSignatures)")
            ],
            signatureEntries: entries.sorted { $0.capturedAt > $1.capturedAt }
        )
    }

    private static func buildPhotoReport(
        orders: [WorkOrder],
        customers: [CustomerID: Customer],
        technicians: [UserID: User],
        repositories: Repositories
    ) async -> ReportDetailPayload {
        let photos = await loadPhotos(for: orders.map(\.id), repository: repositories.workOrderPhotoRepository)

        var entries: [PhotoReportEntry] = []
        var totalPhotos = 0
        for order in orders {
            let orderPhotos = photos[order.id] ?? []
            totalPhotos += orderPhotos.count
            let customer = customers[order.customerId]
            for photo in orderPhotos {
                entries.append(
                    PhotoReportEntry(
                        id: photo.id,
                        photo: photo,
                        workOrderId: order.id,
                        workOrderNumber: order.workOrderNumber,
                        customerName: customer?.name ?? "Bilinmeyen müşteri",
                        workplace: workplaceLabel(for: customer),
                        technicianName: technicians[order.assignedTechnicianId]?.fullName ?? "Bilinmeyen",
                        capturedAt: photo.capturedAt,
                        categoryLabel: photo.category.displayName
                    )
                )
            }
        }

        return ReportDetailPayload(
            metrics: [
                AdminReportMetric(id: "orders", title: "İş Emri", value: "\(orders.count)"),
                AdminReportMetric(id: "photos", title: "Toplam Fotoğraf", value: "\(totalPhotos)")
            ],
            photoEntries: entries.sorted { $0.capturedAt > $1.capturedAt }
        )
    }

    private static func statusBreakdown(from orders: [WorkOrder]) -> [AdminStatusBreakdown] {
        let total = orders.count
        return WorkOrderStatus.allCases.compactMap { status in
            let count = orders.filter { $0.status == status }.count
            guard count > 0 else { return nil }
            let pct = total > 0 ? Double(count) / Double(total) * 100 : 0
            return AdminStatusBreakdown(
                id: status.rawValue,
                status: status,
                count: count,
                percentage: pct
            )
        }
    }

    private static func workplaceLabel(for customer: Customer?) -> String {
        guard let customer else { return "—" }
        if let city = customer.city, !city.isEmpty {
            return "\(customer.name) · \(city)"
        }
        return customer.address.isEmpty ? customer.name : customer.address
    }

    private static func deviceLabel(for order: WorkOrder) -> String {
        "\(order.deviceCategory.displayName) · \(order.deviceBrand) \(order.deviceModel)"
    }

    private static func loadCustomers(
        for orders: [WorkOrder],
        repository: CustomerRepository
    ) async -> [CustomerID: Customer] {
        var result: [CustomerID: Customer] = [:]
        for customerId in Set(orders.map(\.customerId)) {
            if let customer = try? await repository.fetch(id: customerId) {
                result[customerId] = customer
            }
        }
        return result
    }

    private static func loadTechnicians(
        for orders: [WorkOrder],
        repository: UserRepository
    ) async -> [UserID: User] {
        var result: [UserID: User] = [:]
        if let technicians = try? await repository.list(role: .technician, isActive: nil) {
            for tech in technicians {
                result[tech.id] = tech
            }
        }
        for techId in Set(orders.map(\.assignedTechnicianId)) where result[techId] == nil {
            if let tech = try? await repository.fetch(id: techId) {
                result[techId] = tech
            }
        }
        return result
    }

    private static func loadSignatures(
        for workOrderIds: [WorkOrderID],
        repository: SignatureRepository
    ) async -> [WorkOrderID: [Signature]] {
        await loadChildData(for: workOrderIds) { id in
            (try? await repository.list(for: id)) ?? []
        }
    }

    private static func loadPhotos(
        for workOrderIds: [WorkOrderID],
        repository: WorkOrderPhotoRepository
    ) async -> [WorkOrderID: [WorkOrderPhoto]] {
        await loadChildData(for: workOrderIds) { id in
            (try? await repository.list(for: id)) ?? []
        }
    }

    private static func loadStatusHistories(
        for workOrderIds: [WorkOrderID],
        repository: WorkOrderStatusHistoryRepository
    ) async -> [WorkOrderID: [WorkOrderStatusHistory]] {
        await loadChildData(for: workOrderIds) { id in
            (try? await repository.list(for: id)) ?? []
        }
    }

    private static func loadChildData<T: Sendable>(
        for workOrderIds: [WorkOrderID],
        fetch: @escaping @Sendable (WorkOrderID) async -> [T]
    ) async -> [WorkOrderID: [T]] {
        guard !workOrderIds.isEmpty else { return [:] }
        var result: [WorkOrderID: [T]] = [:]
        let chunks = stride(from: 0, to: workOrderIds.count, by: childFetchConcurrency).map {
            Array(workOrderIds[$0..<min($0 + childFetchConcurrency, workOrderIds.count)])
        }
        for chunk in chunks {
            await withTaskGroup(of: (WorkOrderID, [T]).self) { group in
                for id in chunk {
                    group.addTask { (id, await fetch(id)) }
                }
                for await pair in group {
                    result[pair.0] = pair.1
                }
            }
        }
        return result
    }
}
