#if DEBUG
import Foundation

/// Seeds deterministic mock credentials and sample operational data
/// when the app runs on `FakeAuthRepository` (no Firebase config).
///
/// Passwords live in memory only — never persisted to SwiftData.
/// Business seed data is created only when missing (no overwrite).
enum DemoAccountSeeder {

    struct DemoAccount: Sendable {
        let email: String
        let password: String
        let user: User
    }

    static let accounts: [DemoAccount] = [
        DemoAccount(
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
        DemoAccount(
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
        DemoAccount(
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

    static func seedIfNeeded(container: DIContainer) async {
        guard let auth = container.authRepository as? FakeAuthRepository else { return }

        for account in accounts {
            do {
                try await container.userRepository.save(account.user)
            } catch {
                AppLogger.app.warning("Demo account save failed for \(account.email): \(error)")
            }
            auth.seed(user: account.user, password: account.password)
        }

        // Extra technician so wizard assignment has a second option.
        let techB = User(
            id: UserID("demo-technician-2"),
            email: "technician2@dops.test",
            fullName: "Ayşe Demir",
            role: .technician,
            phoneNumber: PhoneNumber("+905551110004"),
            isActive: true,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
        try? await container.userRepository.save(techB)
        auth.seed(user: techB, password: "DopsTest123!")

        await seedOperationalDataIfNeeded(container: container)
        AppLogger.app.info("DEBUG demo accounts ready (FakeAuthRepository).")
    }

    private static func seedOperationalDataIfNeeded(container: DIContainer) async {
        if (try? await container.customerRepository.fetch(id: seedMarkerCustomerId)) != nil {
            return
        }

        let operatorId = UserID("demo-operator")
        let techId = UserID("demo-technician")
        let techBId = UserID("demo-technician-2")
        let now = Date()

        let customers = [
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
            )
        ]

        for customer in customers {
            try? await container.customerRepository.save(customer)
        }

        let workOrders: [WorkOrder] = [
            makeWO(id: "demo-wo-assigned", number: "WO-2001", customer: seedMarkerCustomerId, tech: techId, status: .assigned, priority: .urgent, now: now),
            makeWO(id: "demo-wo-accepted", number: "WO-2002", customer: CustomerID("demo-cust-xyz"), tech: techId, status: .accepted, priority: .high, now: now),
            makeWO(id: "demo-wo-enroute", number: "WO-2003", customer: seedMarkerCustomerId, tech: techId, status: .enRoute, priority: .normal, now: now),
            makeWO(id: "demo-wo-arrived", number: "WO-2004", customer: CustomerID("demo-cust-def"), tech: techId, status: .arrived, priority: .normal, now: now),
            makeWO(id: "demo-wo-progress", number: "WO-2005", customer: seedMarkerCustomerId, tech: techId, status: .inProgress, priority: .high, now: now),
            makeWO(id: "demo-wo-paused", number: "WO-2006", customer: CustomerID("demo-cust-xyz"), tech: techId, status: .paused, priority: .normal, pause: .partWaiting, now: now),
            makeWO(id: "demo-wo-done", number: "WO-2007", customer: CustomerID("demo-cust-def"), tech: techId, status: .completed, priority: .normal, now: now, completed: true),
            makeWO(id: "demo-wo-other-tech", number: "WO-2008", customer: seedMarkerCustomerId, tech: techBId, status: .assigned, priority: .normal, now: now)
        ]

        for order in workOrders {
            try? await container.workOrderRepository.save(order)
        }

        let notifications: [AppNotification] = [
            AppNotification(
                id: NotificationID("demo-notif-op-1"),
                recipientUserId: operatorId,
                type: .workOrderAssigned,
                title: "Yeni iş emri atandı",
                body: "WO-2001 Ahmet Yılmaz'a atandı.",
                relatedWorkOrderId: WorkOrderID("demo-wo-assigned"),
                createdAt: now
            ),
            AppNotification(
                id: NotificationID("demo-notif-tech-1"),
                recipientUserId: techId,
                type: .workOrderAssigned,
                title: "Size yeni iş emri atandı",
                body: "WO-2001 — ABC Market",
                relatedWorkOrderId: WorkOrderID("demo-wo-assigned"),
                createdAt: now
            ),
            AppNotification(
                id: NotificationID("demo-notif-tech-2"),
                recipientUserId: techId,
                type: .workOrderStatusChanged,
                title: "İş emri güncellendi",
                body: "WO-2005 işlemde.",
                relatedWorkOrderId: WorkOrderID("demo-wo-progress"),
                isRead: true,
                createdAt: now.addingTimeInterval(-3600)
            )
        ]
        for notification in notifications {
            try? await container.notificationRepository.save(notification)
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
        completed: Bool = false
    ) -> WorkOrder {
        WorkOrder(
            id: WorkOrderID(id),
            workOrderNumber: number,
            createdByUserId: UserID("demo-operator"),
            assignedTechnicianId: tech,
            customerId: customer,
            workType: .repair,
            deviceCategory: .pos,
            deviceBrand: "Ingenico",
            deviceModel: "iCT250",
            serialNumber: "SN-\(number.suffix(4))",
            issueDescription: "Demo iş emri",
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
}
#endif
