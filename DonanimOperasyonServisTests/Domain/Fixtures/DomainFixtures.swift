import Foundation
@testable import DonanimOperasyonServis

/// Deterministic factories for building Domain entities in tests.
/// Every timestamp and identifier is fixed unless the caller
/// overrides it, so assertions can compare against known values.
enum DomainFixtures {

    /// A reference point used by all default timestamps so tests are
    /// deterministic regardless of when they run.
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Users

    static func adminUser(
        id: UserID = UserID("user-admin-1"),
        email: String = "admin@example.com",
        fullName: String = "Admin User"
    ) -> User {
        User(
            id: id,
            email: email,
            fullName: fullName,
            role: .admin,
            phoneNumber: nil,
            isActive: true,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
    }

    static func operatorUser(
        id: UserID = UserID("user-operator-1"),
        email: String = "operator@example.com",
        fullName: String = "Operatör Kullanıcı"
    ) -> User {
        User(
            id: id,
            email: email,
            fullName: fullName,
            role: .operator,
            phoneNumber: nil,
            isActive: true,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
    }

    static func technicianUser(
        id: UserID = UserID("user-technician-1"),
        email: String = "tech@example.com",
        fullName: String = "Teknisyen Kullanıcı"
    ) -> User {
        User(
            id: id,
            email: email,
            fullName: fullName,
            role: .technician,
            phoneNumber: nil,
            isActive: true,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
    }

    // MARK: - WorkOrder

    static func workOrder(
        id: WorkOrderID = WorkOrderID("wo-1"),
        workOrderNumber: String = "WO-0001",
        createdByUserId: UserID = UserID("user-operator-1"),
        assignedTechnicianId: UserID = UserID("user-technician-1"),
        customerId: CustomerID = CustomerID("cust-1"),
        workType: WorkType = .installation,
        deviceCategory: DeviceCategory = .pos,
        deviceBrand: String = "Ingenico",
        deviceModel: String = "iCT250",
        serialNumber: String = "SN-001",
        issueDescription: String? = "Yeni kurulum",
        priority: WorkOrderPriority = .normal,
        scheduledDate: Date = referenceDate,
        scheduledTimeRange: ScheduledTimeRange? = ScheduledTimeRange(
            uncheckedStart: referenceDate,
            end: referenceDate.addingTimeInterval(3600)
        ),
        status: WorkOrderStatus = .assigned,
        currentPauseReason: PauseReason? = nil,
        createdAt: Date = referenceDate,
        updatedAt: Date = referenceDate,
        completedAt: Date? = nil
    ) -> WorkOrder {
        WorkOrder(
            id: id,
            workOrderNumber: workOrderNumber,
            createdByUserId: createdByUserId,
            assignedTechnicianId: assignedTechnicianId,
            customerId: customerId,
            workType: workType,
            deviceCategory: deviceCategory,
            deviceBrand: deviceBrand,
            deviceModel: deviceModel,
            serialNumber: serialNumber,
            issueDescription: issueDescription,
            priority: priority,
            scheduledDate: scheduledDate,
            scheduledTimeRange: scheduledTimeRange,
            status: status,
            currentPauseReason: currentPauseReason,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt
        )
    }

    static func newWorkOrderRequest(
        id: WorkOrderID = WorkOrderID("wo-new-1"),
        workOrderNumber: String = "WO-0002",
        assignedTechnicianId: UserID = UserID("user-technician-1"),
        customerId: CustomerID = CustomerID("cust-1"),
        workType: WorkType = .installation
    ) -> NewWorkOrderRequest {
        NewWorkOrderRequest(
            id: id,
            workOrderNumber: workOrderNumber,
            assignedTechnicianId: assignedTechnicianId,
            customerId: customerId,
            workType: workType,
            deviceCategory: .pos,
            deviceBrand: "Ingenico",
            deviceModel: "iCT250",
            serialNumber: "SN-100",
            issueDescription: "Yeni kurulum",
            priority: .normal,
            scheduledDate: referenceDate,
            scheduledTimeRange: nil
        )
    }

    // MARK: - Evidence

    static func note(
        id: String = "note-1",
        workOrderId: WorkOrderID = WorkOrderID("wo-1"),
        authorUserId: UserID = UserID("user-technician-1"),
        text: String = "Servis notu"
    ) -> WorkOrderNote {
        WorkOrderNote(
            id: id,
            workOrderId: workOrderId,
            authorUserId: authorUserId,
            text: text,
            createdAt: referenceDate
        )
    }

    static func photo(
        id: String = "photo-1",
        workOrderId: WorkOrderID = WorkOrderID("wo-1"),
        category: PhotoCategory,
        capturedByUserId: UserID = UserID("user-technician-1")
    ) -> WorkOrderPhoto {
        WorkOrderPhoto(
            id: id,
            workOrderId: workOrderId,
            category: category,
            storagePath: "photos/\(id).jpg",
            capturedByUserId: capturedByUserId,
            capturedAt: referenceDate
        )
    }

    static func location(
        id: String = "loc-1",
        workOrderId: WorkOrderID = WorkOrderID("wo-1"),
        event: LocationEvent,
        capturedByUserId: UserID = UserID("user-technician-1")
    ) -> WorkOrderLocation {
        WorkOrderLocation(
            id: id,
            workOrderId: workOrderId,
            event: event,
            coordinate: LocationCoordinate(latitude: 41.0082, longitude: 28.9784, accuracy: 5),
            capturedByUserId: capturedByUserId,
            capturedAt: referenceDate
        )
    }

    static func signature(
        id: String = "sig-1",
        workOrderId: WorkOrderID = WorkOrderID("wo-1"),
        kind: SignatureKind,
        signerName: String? = nil,
        capturedByUserId: UserID = UserID("user-technician-1")
    ) -> Signature {
        Signature(
            id: id,
            workOrderId: workOrderId,
            kind: kind,
            storagePath: "signatures/\(id).png",
            signerName: signerName,
            capturedByUserId: capturedByUserId,
            capturedAt: referenceDate
        )
    }

    /// A complete evidence bundle for a repair work order — used by
    /// the "happy path" completion test.
    static func fullCompletionContext(for workType: WorkType) -> CompletionContext {
        let requiredPhotos = PhotoRequirements
            .requiredCategories(for: workType)
            .enumerated()
            .map { index, category in
                photo(id: "photo-\(index)", category: category)
            }
        let locations = LocationEvent.allCases.enumerated().map { index, event in
            location(id: "loc-\(index)", event: event)
        }
        return CompletionContext(
            workType: workType,
            notes: [note()],
            photos: requiredPhotos,
            locations: locations,
            signatures: [
                signature(id: "sig-tech", kind: .technician),
                signature(id: "sig-cust", kind: .customer, signerName: "Müşteri")
            ]
        )
    }

    // MARK: - EditRequest

    static func editRequest(
        id: EditRequestID = EditRequestID("edit-1"),
        workOrderId: WorkOrderID = WorkOrderID("wo-1"),
        requestedByUserId: UserID = UserID("user-technician-1"),
        field: EditableWorkOrderField = .issueDescription,
        currentValue: String = "Eski açıklama",
        requestedValue: String = "Yeni açıklama",
        status: EditRequestStatus = .pending,
        reviewedByUserId: UserID? = nil,
        reviewedAt: Date? = nil
    ) -> EditRequest {
        EditRequest(
            id: id,
            workOrderId: workOrderId,
            requestedByUserId: requestedByUserId,
            createdAt: referenceDate,
            reason: "Test gerekçesi",
            field: field.rawValue,
            currentValue: currentValue,
            requestedValue: requestedValue,
            status: status,
            reviewedByUserId: reviewedByUserId,
            reviewedAt: reviewedAt,
            decisionNote: nil
        )
    }

    // MARK: - Customer / Notification / History

    static func customer(
        id: CustomerID = CustomerID("cust-1"),
        name: String = "Migros Bahçelievler",
        createdByUserId: UserID = UserID("user-operator-1")
    ) -> Customer {
        Customer(
            id: id,
            name: name,
            address: "Bağdat Cad. No:1",
            createdByUserId: createdByUserId,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
    }

    static func notification(
        id: NotificationID = NotificationID("notif-1"),
        recipientUserId: UserID = UserID("user-technician-1"),
        type: NotificationType = .workOrderAssigned
    ) -> AppNotification {
        AppNotification(
            id: id,
            recipientUserId: recipientUserId,
            type: type,
            title: "İş emri atandı",
            body: "Yeni bir iş emri atandı.",
            createdAt: referenceDate
        )
    }

    static func statusHistory(
        id: String = "hist-1",
        workOrderId: WorkOrderID = WorkOrderID("wo-1"),
        fromStatus: WorkOrderStatus? = nil,
        toStatus: WorkOrderStatus = .assigned,
        actorUserId: UserID = UserID("user-operator-1")
    ) -> WorkOrderStatusHistory {
        WorkOrderStatusHistory(
            id: id,
            workOrderId: workOrderId,
            fromStatus: fromStatus,
            toStatus: toStatus,
            actorUserId: actorUserId,
            occurredAt: referenceDate
        )
    }
}
