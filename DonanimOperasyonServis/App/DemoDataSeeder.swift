#if DEBUG
import Foundation

/// DEBUG-only demo seed for SwiftData — local repositories only.
///
/// Local writes always go through the container's SwiftData repositories
/// (`userRepository`, `customerRepository`, `workOrderRepository`, …) —
/// never the `remote*` Firebase repositories and never SyncQueue enqueue.
///
/// `FakeAuthRepository.seed` is mock-only for DEBUG sign-in credentials.
enum DemoDataSeeder {

    struct DemoSeedOutcome: Equatable, Sendable {
        let isSuccess: Bool
        let message: String
    }

    /// Backward-compatible alias used by existing call sites / tests.
    typealias DemoAccount = DemoAccountRecord

    struct DemoAccountRecord: Sendable {
        let email: String
        let password: String
        let user: User
    }

    static let accounts: [DemoAccountRecord] = [
        DemoAccountRecord(
            email: "admin@dops.test",
            password: "DopsTest123!",
            user: User(
                id: UserID("demo-admin"),
                email: "admin@dops.test",
                fullName: "Admin Demo",
                role: .admin,
                phoneNumber: PhoneNumber("+905551110001"),
                isActive: true,
                createdAt: referenceDate,
                updatedAt: referenceDate
            )
        ),
        DemoAccountRecord(
            email: "operator@dops.test",
            password: "DopsTest123!",
            user: User(
                id: UserID("demo-operator"),
                email: "operator@dops.test",
                fullName: "Mehmet Kaya",
                role: .operator,
                phoneNumber: PhoneNumber("+905551110002"),
                isActive: true,
                createdAt: referenceDate,
                updatedAt: referenceDate
            )
        ),
        DemoAccountRecord(
            email: "technician@dops.test",
            password: "DopsTest123!",
            user: User(
                id: UserID("demo-technician"),
                email: "technician@dops.test",
                fullName: "Ahmet Yılmaz",
                role: .technician,
                phoneNumber: PhoneNumber("+905551110003"),
                isActive: true,
                createdAt: referenceDate,
                updatedAt: referenceDate
            )
        )
    ]

    private static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
    private static let seedMarkerCustomerId = CustomerID("demo-cust-abc")

    private static let demoActiveTechnicianIds = [
        "demo-technician", "demo-technician-2", "demo-technician-3",
        "demo-technician-4", "demo-technician-5"
    ]

    private static let demoUserIds = [
        "demo-admin", "demo-operator",
        "demo-technician", "demo-technician-2", "demo-technician-3",
        "demo-technician-4", "demo-technician-5",
        "demo-technician-inactive", "demo-operator-2"
    ]

    private static let demoCustomerIds = [
        "demo-cust-abc", "demo-cust-xyz", "demo-cust-def",
        "demo-cust-ghi", "demo-cust-jkl"
    ]

    private static let demoWorkOrderIds = [
        "demo-wo-assigned", "demo-wo-progress", "demo-wo-done"
    ]

    /// Previous seed IDs — removed from active seed but still cleared on upgrade.
    private static let legacyDemoWorkOrderIds = [
        "demo-wo-accepted", "demo-wo-enroute", "demo-wo-arrived", "demo-wo-paused",
        "demo-wo-other-tech", "demo-wo-rich", "demo-wo-edit-ready",
        "demo-wo-urgent-2", "demo-wo-high-new", "demo-wo-printer-fix",
        "demo-wo-scanner-setup", "demo-wo-tablet-delivery",
        "demo-wo-completed-2", "demo-wo-completed-3", "demo-wo-paused-2"
    ]

    private static var allDemoWorkOrderIdsForCleanup: [String] {
        Array(Set(demoWorkOrderIds + legacyDemoWorkOrderIds))
    }

    private static let legacyDemoNotificationIds = [
        "demo-notif-op-1", "demo-notif-op-2", "demo-notif-admin-1",
        "demo-notif-tech-1", "demo-notif-tech-2", "demo-notif-tech-3",
        "demo-notif-tech-4", "demo-notif-tech-5", "demo-notif-op-3"
    ]

    // MARK: - Public API

    static func seedIfNeeded(container: DIContainer) async {
        let report = SeedReport()
        await seedAccounts(container: container, report: report)
        await seedOperationalDataIfNeeded(container: container, report: report)
        if report.requiredFailures.isEmpty {
            AppLogger.app.info("DEBUG demo data ready.")
        } else {
            AppLogger.app.error(
                "DEBUG demo seed incomplete: \(report.requiredFailures.joined(separator: "; "))"
            )
        }
    }

    /// Idempotent force load — clears known demo IDs then reseeds.
    @discardableResult
    static func loadDemoData(container: DIContainer) async -> DemoSeedOutcome {
        _ = await clearDemoData(container: container)
        let report = SeedReport()
        await seedAccounts(container: container, report: report)
        await seedOperationalData(container: container, force: true, report: report)
        await verifyRequiredEntities(container: container, report: report)
        return outcome(from: report)
    }

    /// Persists demo users through `userRepository`. FakeAuth credential
    /// seeding is optional so live Firebase DEBUG sessions still get
    /// local SwiftData users.
    @discardableResult
    static func persistDemoUsers(
        to userRepository: any UserRepository,
        fakeAuth: FakeAuthRepository?
    ) async -> [String] {
        var errors: [String] = []
        for record in allDemoUserRecords() {
            do {
                try await userRepository.save(record.user)
            } catch {
                errors.append("User \(record.user.id.rawValue): \(error)")
                AppLogger.app.error(
                    "Demo account save failed for \(record.user.email): \(error)"
                )
            }
            fakeAuth?.seed(user: record.user, password: record.password)
        }
        return errors
    }

    @discardableResult
    static func clearDemoData(container: DIContainer) async -> String {

        for id in allDemoWorkOrderIdsForCleanup {
            let woId = WorkOrderID(id)
            if let notes = try? await container.workOrderNoteRepository.list(for: woId) {
                for note in notes {
                    await deleteIgnoringNotFound {
                        try await container.workOrderNoteRepository.delete(id: note.id, for: woId)
                    }
                }
            }
            if let photos = try? await container.workOrderPhotoRepository.list(for: woId) {
                for photo in photos {
                    await deleteIgnoringNotFound {
                        try await container.workOrderPhotoRepository.delete(id: photo.id, for: woId)
                    }
                }
            }
            if let signatures = try? await container.signatureRepository.list(for: woId) {
                for signature in signatures {
                    await deleteIgnoringNotFound {
                        try await container.signatureRepository.delete(id: signature.id, for: woId)
                    }
                }
            }
            // Locations / status history: delete via WO cascade if available;
            // otherwise leave orphan rows keyed by demo WO id — clearing WO is enough for lists.
            await deleteIgnoringNotFound {
                try await container.workOrderRepository.delete(id: woId)
            }
        }

        for id in demoCustomerIds {
            await deleteIgnoringNotFound {
                try await container.customerRepository.delete(id: CustomerID(id))
            }
        }

        for id in legacyDemoNotificationIds {
            await deleteIgnoringNotFound {
                try await container.notificationRepository.delete(id: NotificationID(id))
            }
        }

        let conflictOpId = SyncOperationID("demo-sync-op-conflict")
        if let conflictOp = try? await container.syncOperationRepository.fetch(id: conflictOpId),
           conflictOp.status == .succeeded {
            await deleteIgnoringNotFound {
                try await container.syncOperationRepository.delete(id: conflictOpId)
            }
        }
        if let conflict = try? await container.syncConflictRepository.fetch(id: SyncConflictID("demo-conflict-1")),
           !conflict.isResolved {
            await deleteIgnoringNotFound {
                try await container.syncConflictRepository.save(
                    conflict.markingResolved(
                        choice: .useLocal,
                        at: Date(),
                        by: UserID("demo-admin")
                    )
                )
            }
        }

        for id in demoUserIds where id != "demo-admin" && id != "demo-operator" && id != "demo-technician" {
            await deleteIgnoringNotFound {
                try await container.userRepository.delete(id: UserID(id))
            }
        }

        AppLogger.app.info("DEBUG demo data cleared.")
        return "Demo veriler temizlendi."
    }

    // MARK: - Accounts

    private static func seedAccounts(container: DIContainer, report: SeedReport) async {
        let fakeAuth = container.authRepository as? FakeAuthRepository
        let errors = await persistDemoUsers(
            to: container.userRepository,
            fakeAuth: fakeAuth
        )
        report.requiredFailures.append(contentsOf: errors)
    }

    // MARK: - Operational data

    private static func seedOperationalDataIfNeeded(container: DIContainer, report: SeedReport) async {
        if (try? await container.customerRepository.fetch(id: seedMarkerCustomerId)) != nil {
            await trimLegacyDemoWorkOrdersIfNeeded(container: container, report: report)
            await trimLegacyDemoNotificationsIfNeeded(container: container, report: report)
            await trimLegacyDemoConflictIfNeeded(container: container, report: report)
            await backfillMissingDemoStatusHistories(container: container, report: report)
            return
        }
        await seedOperationalData(container: container, force: true, report: report)
    }

    private static func seedOperationalData(
        container: DIContainer,
        force: Bool,
        report: SeedReport
    ) async {
        if !force,
           (try? await container.customerRepository.fetch(id: seedMarkerCustomerId)) != nil {
            return
        }

        let operatorId = UserID("demo-operator")
        let techId = UserID("demo-technician")
        let techBId = UserID("demo-technician-2")
        let now = Date()

        let customers = makeCustomers(operatorId: operatorId)
        for customer in customers {
            await report.require("Customer \(customer.id.rawValue)") {
                try await container.customerRepository.save(customer)
            }
        }

        let workOrders = makeWorkOrders(techId: techId, techBId: techBId, now: now)
        for order in workOrders {
            await report.require("WorkOrder \(order.id.rawValue)") {
                try await container.workOrderRepository.save(order)
            }
        }

        await ensureDemoStatusHistories(
            container: container,
            orders: workOrders,
            operatorId: operatorId,
            techId: techId,
            now: now,
            report: report
        )
    }

    private static func makeCustomers(operatorId: UserID) -> [Customer] {
        [
            Customer(
                id: seedMarkerCustomerId,
                name: "ABC Market",
                contactPersonName: "Ali Veli",
                phoneNumber: PhoneNumber("+905301112233"),
                email: "abc@example.com",
                address: "Bahçelievler Mah. Gazi Cad. No:12",
                city: "Çorum",
                notes: "Demo müşteri",
                createdByUserId: operatorId,
                createdAt: referenceDate,
                updatedAt: referenceDate
            ),
            Customer(
                id: CustomerID("demo-cust-xyz"),
                name: "XYZ Mağaza",
                contactPersonName: "Ayşe Yılmaz",
                phoneNumber: PhoneNumber("+905302223344"),
                email: "xyz@example.com",
                address: "Merkez Mah. Atatürk Bulvarı No:45",
                city: "Ankara",
                createdByUserId: operatorId,
                createdAt: referenceDate,
                updatedAt: referenceDate
            ),
            Customer(
                id: CustomerID("demo-cust-def"),
                name: "DEF Restoran",
                contactPersonName: "Can Öztürk",
                phoneNumber: PhoneNumber("+905303334455"),
                address: "Kızılay Cad. No:8",
                city: "Ankara",
                createdByUserId: operatorId,
                createdAt: referenceDate,
                updatedAt: referenceDate
            ),
            Customer(
                id: CustomerID("demo-cust-ghi"),
                name: "GHI Oteli",
                contactPersonName: "Deniz Kara",
                phoneNumber: PhoneNumber("+905304445566"),
                email: "ghi@example.com",
                address: "Sahil Cad. No:3",
                city: "Antalya",
                createdByUserId: operatorId,
                createdAt: referenceDate,
                updatedAt: referenceDate
            ),
            Customer(
                id: CustomerID("demo-cust-jkl"),
                name: "JKL Eczane",
                contactPersonName: "Ece Nur",
                phoneNumber: PhoneNumber("+905305556677"),
                address: "Sağlık Sok. No:17",
                city: "İzmir",
                createdByUserId: operatorId,
                createdAt: referenceDate,
                updatedAt: referenceDate
            )
        ]
    }

    private static func makeWorkOrders(
        techId: UserID,
        techBId: UserID,
        now: Date
    ) -> [WorkOrder] {
        [
            makeWO(
                id: "demo-wo-assigned", number: "WO-2001",
                customer: seedMarkerCustomerId, tech: techId,
                status: .assigned, priority: .urgent, now: now,
                brand: "Ingenico", model: "iCT250", category: .pos, workType: .repair
            ),
            makeWO(
                id: "demo-wo-progress", number: "WO-2005",
                customer: CustomerID("demo-cust-xyz"), tech: techBId,
                status: .inProgress, priority: .high, now: now,
                brand: "Honeywell", model: "Voyager", category: .barcodeScanner, workType: .installation
            ),
            makeWO(
                id: "demo-wo-done", number: "WO-2007",
                customer: CustomerID("demo-cust-def"), tech: techId,
                status: .completed, priority: .normal, now: now, completed: true,
                brand: "Ingenico", model: "Move/5000", category: .pos, workType: .repair
            )
        ]
    }

    // MARK: - Legacy trim (upgrade path)

    private static func trimLegacyDemoWorkOrdersIfNeeded(
        container: DIContainer,
        report: SeedReport
    ) async {
        for id in legacyDemoWorkOrderIds {
            await deleteDemoWorkOrderIfPresent(container: container, id: id, report: report)
        }
    }

    private static func trimLegacyDemoNotificationsIfNeeded(
        container: DIContainer,
        report: SeedReport
    ) async {
        for id in legacyDemoNotificationIds {
            await report.warn("Legacy notification trim \(id)") {
                try await container.notificationRepository.delete(id: NotificationID(id))
            }
        }
    }

    private static func trimLegacyDemoConflictIfNeeded(
        container: DIContainer,
        report: SeedReport
    ) async {
        let conflictOpId = SyncOperationID("demo-sync-op-conflict")
        if let conflictOp = try? await container.syncOperationRepository.fetch(id: conflictOpId),
           conflictOp.status == .succeeded {
            await report.warn("Legacy sync op trim demo-sync-op-conflict") {
                try await container.syncOperationRepository.delete(id: conflictOpId)
            }
        }
        if let conflict = try? await container.syncConflictRepository.fetch(id: SyncConflictID("demo-conflict-1")),
           !conflict.isResolved {
            await report.warn("Legacy conflict trim demo-conflict-1") {
                try await container.syncConflictRepository.save(
                    conflict.markingResolved(
                        choice: .useLocal,
                        at: Date(),
                        by: UserID("demo-admin")
                    )
                )
            }
        }
    }

    private static func deleteDemoWorkOrderIfPresent(
        container: DIContainer,
        id: String,
        report: SeedReport
    ) async {
        let woId = WorkOrderID(id)
        guard (try? await container.workOrderRepository.fetch(id: woId)) != nil else { return }
        if let notes = try? await container.workOrderNoteRepository.list(for: woId) {
            for note in notes {
                await report.warn("Legacy note trim \(note.id)") {
                    try await container.workOrderNoteRepository.delete(id: note.id, for: woId)
                }
            }
        }
        if let photos = try? await container.workOrderPhotoRepository.list(for: woId) {
            for photo in photos {
                await report.warn("Legacy photo trim \(photo.id)") {
                    try await container.workOrderPhotoRepository.delete(id: photo.id, for: woId)
                }
            }
        }
        if let signatures = try? await container.signatureRepository.list(for: woId) {
            for signature in signatures {
                await report.warn("Legacy signature trim \(signature.id)") {
                    try await container.signatureRepository.delete(id: signature.id, for: woId)
                }
            }
        }
        await report.warn("Legacy work order trim \(id)") {
            try await container.workOrderRepository.delete(id: woId)
        }
    }

    // MARK: - Histories

    private static func backfillMissingDemoStatusHistories(
        container: DIContainer,
        report: SeedReport
    ) async {
        var orders: [WorkOrder] = []
        for id in demoWorkOrderIds {
            if let order = try? await container.workOrderRepository.fetch(id: WorkOrderID(id)) {
                orders.append(order)
            }
        }
        guard !orders.isEmpty else { return }
        await ensureDemoStatusHistories(
            container: container,
            orders: orders,
            operatorId: UserID("demo-operator"),
            techId: UserID("demo-technician"),
            now: Date(),
            report: report
        )
    }

    private static func ensureDemoStatusHistories(
        container: DIContainer,
        orders: [WorkOrder],
        operatorId: UserID,
        techId: UserID,
        now: Date,
        report: SeedReport
    ) async {
        for order in orders {
            let existing = (try? await container.workOrderStatusHistoryRepository.list(for: order.id)) ?? []
            guard existing.isEmpty else { continue }
            let path = statusPath(to: order.status)
            var previous: WorkOrderStatus?
            for (index, status) in path.enumerated() {
                let actorId = index == 0 ? operatorId : techId
                let entry = WorkOrderStatusHistory(
                    id: "demo-hist-\(order.id.rawValue)-\(status.rawValue)",
                    workOrderId: order.id,
                    fromStatus: previous,
                    toStatus: status,
                    pauseReason: status == .paused ? order.currentPauseReason : nil,
                    actorUserId: actorId,
                    occurredAt: now.addingTimeInterval(TimeInterval(index * 60))
                )
                await report.warn("StatusHistory \(entry.id)") {
                    try await container.workOrderStatusHistoryRepository.append(entry)
                }
                previous = status
            }
        }
    }

    private static func statusPath(to status: WorkOrderStatus) -> [WorkOrderStatus] {
        switch status {
        case .assigned: return [.assigned]
        case .accepted: return [.assigned, .accepted]
        case .rejected: return [.assigned, .rejected]
        case .enRoute: return [.assigned, .accepted, .enRoute]
        case .arrived: return [.assigned, .accepted, .enRoute, .arrived]
        case .inProgress: return [.assigned, .accepted, .enRoute, .arrived, .inProgress]
        case .paused: return [.assigned, .accepted, .enRoute, .arrived, .inProgress, .paused]
        case .completed: return [.assigned, .accepted, .enRoute, .arrived, .inProgress, .completed]
        }
    }

    private static func makeWO(
        id: String,
        number: String,
        customer: CustomerID,
        tech: UserID,
        status: WorkOrderStatus,
        priority: WorkOrderPriority,
        pause: PauseReason? = nil,
        now: Date,
        completed: Bool = false,
        brand: String = "Ingenico",
        model: String = "iCT250",
        category: DeviceCategory = .pos,
        workType: WorkType = .repair
    ) -> WorkOrder {
        WorkOrder(
            id: WorkOrderID(id),
            workOrderNumber: number,
            createdByUserId: UserID("demo-operator"),
            assignedTechnicianId: tech,
            customerId: customer,
            workType: workType,
            deviceCategory: category,
            deviceBrand: brand,
            deviceModel: model,
            serialNumber: "SN-\(number.suffix(4))",
            issueDescription: "Demo iş emri — \(number)",
            priority: priority,
            scheduledDate: now,
            scheduledTimeRange: ScheduledTimeRange(
                uncheckedStart: now,
                end: now.addingTimeInterval(3600)
            ),
            status: status,
            currentPauseReason: pause,
            createdAt: referenceDate,
            updatedAt: now,
            completedAt: completed ? now : nil
        )
    }

    // MARK: - Verification / live enqueue / reporting

    private static func allDemoUserRecords() -> [DemoAccountRecord] {
        accounts + [
            DemoAccountRecord(
                email: "technician2@dops.test",
                password: "DopsTest123!",
                user: User(
                    id: UserID("demo-technician-2"),
                    email: "technician2@dops.test",
                    fullName: "Ayşe Demir",
                    role: .technician,
                    phoneNumber: PhoneNumber("+905551110004"),
                    isActive: true,
                    createdAt: referenceDate,
                    updatedAt: referenceDate
                )
            ),
            DemoAccountRecord(
                email: "technician3@dops.test",
                password: "DopsTest123!",
                user: User(
                    id: UserID("demo-technician-3"),
                    email: "technician3@dops.test",
                    fullName: "Burak Şahin",
                    role: .technician,
                    phoneNumber: PhoneNumber("+905551110007"),
                    isActive: true,
                    createdAt: referenceDate,
                    updatedAt: referenceDate
                )
            ),
            DemoAccountRecord(
                email: "technician4@dops.test",
                password: "DopsTest123!",
                user: User(
                    id: UserID("demo-technician-4"),
                    email: "technician4@dops.test",
                    fullName: "Cem Akın",
                    role: .technician,
                    phoneNumber: PhoneNumber("+905551110008"),
                    isActive: true,
                    createdAt: referenceDate,
                    updatedAt: referenceDate
                )
            ),
            DemoAccountRecord(
                email: "technician5@dops.test",
                password: "DopsTest123!",
                user: User(
                    id: UserID("demo-technician-5"),
                    email: "technician5@dops.test",
                    fullName: "Deniz Koç",
                    role: .technician,
                    phoneNumber: PhoneNumber("+905551110009"),
                    isActive: true,
                    createdAt: referenceDate,
                    updatedAt: referenceDate
                )
            ),
            DemoAccountRecord(
                email: "inactive.tech@dops.test",
                password: "DopsTest123!",
                user: User(
                    id: UserID("demo-technician-inactive"),
                    email: "inactive.tech@dops.test",
                    fullName: "Pasif Teknisyen",
                    role: .technician,
                    phoneNumber: PhoneNumber("+905551110005"),
                    isActive: false,
                    createdAt: referenceDate,
                    updatedAt: referenceDate
                )
            ),
            DemoAccountRecord(
                email: "operator2@dops.test",
                password: "DopsTest123!",
                user: User(
                    id: UserID("demo-operator-2"),
                    email: "operator2@dops.test",
                    fullName: "Zeynep Aksoy",
                    role: .operator,
                    phoneNumber: PhoneNumber("+905551110006"),
                    isActive: true,
                    createdAt: referenceDate,
                    updatedAt: referenceDate
                )
            )
        ]
    }

    private static func verifyRequiredEntities(
        container: DIContainer,
        report: SeedReport
    ) async {
        for id in demoUserIds {
            do {
                _ = try await container.userRepository.fetch(id: UserID(id))
            } catch {
                report.requiredFailures.append("User \(id) seed sonrası bulunamadı: \(error)")
            }
        }
        for id in demoActiveTechnicianIds {
            do {
                let user = try await container.userRepository.fetch(id: UserID(id))
                guard user.role == .technician, user.isActive else {
                    report.requiredFailures.append("Technician \(id) aktif teknisyen değil")
                    continue
                }
            } catch {
                report.requiredFailures.append("Technician \(id) seed sonrası bulunamadı: \(error)")
            }
        }
        for id in demoCustomerIds {
            do {
                _ = try await container.customerRepository.fetch(id: CustomerID(id))
            } catch {
                report.requiredFailures.append("Customer \(id) seed sonrası bulunamadı: \(error)")
            }
        }
        let customerIdSet = Set(demoCustomerIds)
        for id in demoWorkOrderIds {
            do {
                let order = try await container.workOrderRepository.fetch(id: WorkOrderID(id))
                if !customerIdSet.contains(order.customerId.rawValue) {
                    report.requiredFailures.append(
                        "WorkOrder \(id) customerId \(order.customerId.rawValue) demo müşterilerle uyuşmuyor"
                    )
                }
            } catch {
                report.requiredFailures.append("WorkOrder \(id) seed sonrası bulunamadı: \(error)")
            }
        }
    }

    private static func outcome(from report: SeedReport) -> DemoSeedOutcome {
        if !report.requiredFailures.isEmpty {
            var message = "Demo seed başarısız:\n" + report.requiredFailures.joined(separator: "\n")
            if !report.warnings.isEmpty {
                message += "\nUyarılar:\n" + report.warnings.joined(separator: "\n")
            }
            return DemoSeedOutcome(isSuccess: false, message: message)
        }
        var message =
            "Demo veriler yüklendi. Kullanıcı \(demoUserIds.count), müşteri \(demoCustomerIds.count), iş emri \(demoWorkOrderIds.count)."
        if !report.warnings.isEmpty {
            message += " Uyarılar: " + report.warnings.joined(separator: "; ")
        }
        return DemoSeedOutcome(isSuccess: true, message: message)
    }

    private static func deleteIgnoringNotFound(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch let error as DomainError {
            if case .notFound = error { return }
            AppLogger.app.error("Demo clear failed: \(error)")
        } catch {
            AppLogger.app.error("Demo clear failed: \(error)")
        }
    }

    private final class SeedReport: @unchecked Sendable {
        var requiredFailures: [String] = []
        var warnings: [String] = []

        func require(_ label: String, _ work: () async throws -> Void) async {
            do {
                try await work()
            } catch {
                requiredFailures.append("\(label): \(error)")
                AppLogger.app.error("Demo seed required failure \(label): \(error)")
            }
        }

        func warn(_ label: String, _ work: () async throws -> Void) async {
            do {
                try await work()
            } catch {
                warnings.append("\(label): \(error)")
                AppLogger.app.warning("Demo seed warning \(label): \(error)")
            }
        }
    }
}

/// Legacy name — keep call sites compiling.
typealias DemoAccountSeeder = DemoDataSeeder
#endif
