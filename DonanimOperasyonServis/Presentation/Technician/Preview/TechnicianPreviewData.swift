#if DEBUG
import Foundation

enum TechnicianPreviewData {
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    static let technician = User(
        id: UserID("tech-preview"),
        email: "ahmet@example.com",
        fullName: "Ahmet Yılmaz",
        role: .technician,
        phoneNumber: PhoneNumber("+905551112233"),
        isActive: true,
        createdAt: referenceDate,
        updatedAt: referenceDate
    )

    static let customer = Customer(
        id: CustomerID("cust-preview"),
        name: "ABC Market",
        contactPersonName: "Ali Veli",
        phoneNumber: PhoneNumber("+905301112233"),
        address: "Bahçelievler Mah. Gazi Cad. No:12",
        city: "Çorum",
        createdByUserId: UserID("operator-1"),
        createdAt: referenceDate,
        updatedAt: referenceDate
    )

    static func workOrder(status: WorkOrderStatus, priority: WorkOrderPriority = .urgent) -> WorkOrder {
        WorkOrder(
            id: WorkOrderID("wo-tech-1"),
            workOrderNumber: "WO-1024",
            createdByUserId: UserID("operator-1"),
            assignedTechnicianId: technician.id,
            customerId: customer.id,
            workType: .repair,
            deviceCategory: .pos,
            deviceBrand: "Ingenico",
            deviceModel: "DX8000",
            serialNumber: "98765432310",
            issueDescription: "POS cihazı açılmıyor",
            priority: priority,
            scheduledDate: referenceDate,
            scheduledTimeRange: ScheduledTimeRange(
                uncheckedStart: referenceDate,
                end: referenceDate.addingTimeInterval(3600)
            ),
            status: status,
            createdAt: referenceDate,
            updatedAt: referenceDate,
            completedAt: status == .completed ? referenceDate : nil
        )
    }

    static var sampleOrders: [WorkOrder] {
        [
            workOrder(status: .inProgress),
            workOrder(status: .assigned, priority: .normal),
            workOrder(status: .paused, priority: .high)
        ]
    }

    static var sampleNotifications: [AppNotification] {
        [
            AppNotification(
                id: NotificationID("n1"),
                recipientUserId: technician.id,
                type: .workOrderAssigned,
                title: "Yeni iş atandı",
                body: "WO-1024 size atandı.",
                relatedWorkOrderId: WorkOrderID("wo-tech-1"),
                createdAt: referenceDate
            )
        ]
    }
}
#endif
