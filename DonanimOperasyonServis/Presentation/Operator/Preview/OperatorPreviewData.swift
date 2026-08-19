#if DEBUG
import Foundation

/// Preview / mock fixtures for Operator screens. Uses the same shapes
/// as production data but never touches Firebase.
enum OperatorPreviewData {

    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    static let operatorUser = User(
        id: UserID("user-operator-preview"),
        email: "mehmet@example.com",
        fullName: "Mehmet Kaya",
        role: .operator,
        phoneNumber: PhoneNumber("+905551234567"),
        isActive: true,
        createdAt: referenceDate,
        updatedAt: referenceDate
    )

    static let technicianAhmet = User(
        id: UserID("tech-ahmet"),
        email: "ahmet@example.com",
        fullName: "Ahmet Yılmaz",
        role: .technician,
        isActive: true,
        createdAt: referenceDate,
        updatedAt: referenceDate
    )

    static let technicianMehmet = User(
        id: UserID("tech-mehmet"),
        email: "mehmet.tech@example.com",
        fullName: "Mehmet Demir",
        role: .technician,
        isActive: true,
        createdAt: referenceDate,
        updatedAt: referenceDate
    )

    static let customerABC = Customer(
        id: CustomerID("cust-abc"),
        name: "ABC Market",
        contactPersonName: "Ali Veli",
        phoneNumber: PhoneNumber("+905301112233"),
        address: "Bahçelievler Mah. Gazi Cad. No:12 Çorum",
        city: "Çorum",
        createdByUserId: operatorUser.id,
        createdAt: referenceDate,
        updatedAt: referenceDate
    )

    static let customerXYZ = Customer(
        id: CustomerID("cust-xyz"),
        name: "XYZ Mağaza",
        contactPersonName: "Ayşe Yılmaz",
        phoneNumber: PhoneNumber("+905302223344"),
        address: "Merkez Mah. Atatürk Bulvarı No:45",
        city: "Ankara",
        createdByUserId: operatorUser.id,
        createdAt: referenceDate,
        updatedAt: referenceDate
    )

    static func workOrder(
        id: String,
        number: String,
        customerId: CustomerID,
        status: WorkOrderStatus,
        priority: WorkOrderPriority = .normal,
        workType: WorkType = .repair
    ) -> WorkOrder {
        WorkOrder(
            id: WorkOrderID(id),
            workOrderNumber: number,
            createdByUserId: operatorUser.id,
            assignedTechnicianId: technicianAhmet.id,
            customerId: customerId,
            workType: workType,
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

    static var sampleWorkOrders: [WorkOrder] {
        [
            workOrder(id: "wo-1024", number: "WO-1024", customerId: customerABC.id, status: .assigned, priority: .urgent),
            workOrder(id: "wo-1025", number: "WO-1025", customerId: customerXYZ.id, status: .inProgress, priority: .normal, workType: .installation),
            workOrder(id: "wo-1026", number: "WO-1026", customerId: customerABC.id, status: .completed, priority: .normal, workType: .delivery)
        ]
    }

    static var urgentCards: [WorkOrderCardData] {
        sampleWorkOrders
            .filter { $0.priority == .urgent }
            .map {
                WorkOrderPresentationMapping.cardData(
                    from: $0,
                    customerName: customerABC.name,
                    technicianName: technicianAhmet.fullName
                )
            }
    }

    static var sampleNotifications: [AppNotification] {
        [
            AppNotification(
                id: NotificationID("notif-1"),
                recipientUserId: operatorUser.id,
                type: .workOrderAssigned,
                title: "Yeni iş emri atandı",
                body: "WO-1024 numaralı acil iş emri oluşturuldu.",
                relatedWorkOrderId: WorkOrderID("wo-1024"),
                createdAt: referenceDate
            ),
            AppNotification(
                id: NotificationID("notif-2"),
                recipientUserId: operatorUser.id,
                type: .editRequestCreated,
                title: "Düzenleme talebi",
                body: "WO-1026 için yeni düzenleme talebi bekliyor.",
                relatedEditRequestId: EditRequestID("edit-1"),
                createdAt: referenceDate.addingTimeInterval(600)
            )
        ]
    }

    static var sampleEditRequest: EditRequest {
        EditRequest(
            id: EditRequestID("edit-1"),
            workOrderId: WorkOrderID("wo-1026"),
            requestedByUserId: technicianAhmet.id,
            createdAt: referenceDate,
            reason: "Seri numarası yanlış girilmiş",
            field: EditableWorkOrderField.serialNumber.rawValue,
            currentValue: "98765432310",
            requestedValue: "98765432311",
            status: .pending
        )
    }
}
#endif
