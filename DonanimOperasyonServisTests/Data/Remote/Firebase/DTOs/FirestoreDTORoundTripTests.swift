import XCTest
@testable import DonanimOperasyonServis

/// Domain → DTO → Domain identity for every Firestore DTO. Covers
/// enums, typed IDs, optionals, `ScheduledTimeRange`,
/// `LocationCoordinate`, `PhoneNumber`, and Date round-trip through
/// the millisecond encoder used by the fake (Timestamp-equivalent).
final class FirestoreDTORoundTripTests: XCTestCase {

    func testUserRoundTripWithPhone() {
        let user = User(
            id: UserID("u-1"),
            email: "a@b.com",
            fullName: "Ada Lovelace",
            role: .technician,
            phoneNumber: PhoneNumber("+90 555 000 11 22"),
            isActive: true,
            createdAt: DomainFixtures.referenceDate,
            updatedAt: DomainFixtures.referenceDate.addingTimeInterval(60)
        )
        XCTAssertEqual(FirestoreUserDTO(domain: user).toDomain(), user)
    }

    func testUserRoundTripNilPhoneInactiveAdmin() {
        let user = DomainFixtures.adminUser()
        XCTAssertEqual(FirestoreUserDTO(domain: user).toDomain(), user)
    }

    func testCustomerRoundTripAllOptionalsSet() {
        let customer = Customer(
            id: CustomerID("c-1"),
            name: "Örnek",
            contactPersonName: "Ali",
            phoneNumber: PhoneNumber("+90 555 111 22 33"),
            email: "info@ornek.com",
            address: "Adres",
            city: "Ankara",
            notes: "Not",
            createdByUserId: UserID("op-1"),
            createdAt: DomainFixtures.referenceDate,
            updatedAt: DomainFixtures.referenceDate
        )
        XCTAssertEqual(FirestoreCustomerDTO(domain: customer).toDomain(), customer)
    }

    func testCustomerRoundTripAllOptionalsNil() {
        let customer = Customer(
            id: CustomerID("c-2"),
            name: "Minimal",
            contactPersonName: nil,
            phoneNumber: nil,
            email: nil,
            address: "Adres",
            city: nil,
            notes: nil,
            createdByUserId: UserID("op-1"),
            createdAt: DomainFixtures.referenceDate,
            updatedAt: DomainFixtures.referenceDate
        )
        XCTAssertEqual(FirestoreCustomerDTO(domain: customer).toDomain(), customer)
    }

    func testWorkOrderRoundTripEveryEnumAndScheduledRange() {
        let range = ScheduledTimeRange(
            uncheckedStart: DomainFixtures.referenceDate,
            end: DomainFixtures.referenceDate.addingTimeInterval(7_200)
        )
        let order = DomainFixtures.workOrder(
            workType: .repair,
            deviceCategory: .cashRegister,
            priority: .urgent,
            scheduledTimeRange: range,
            status: .paused,
            currentPauseReason: .partWaiting,
            completedAt: nil
        )
        XCTAssertEqual(FirestoreWorkOrderDTO(domain: order).toDomain(), order)
    }

    func testWorkOrderRoundTripWithoutOptionalRangeAndPauseReason() {
        let order = DomainFixtures.workOrder(
            scheduledTimeRange: nil,
            status: .completed,
            currentPauseReason: nil,
            completedAt: DomainFixtures.referenceDate.addingTimeInterval(3_600)
        )
        XCTAssertEqual(FirestoreWorkOrderDTO(domain: order).toDomain(), order)
    }

    func testNoteRoundTrip() {
        let note = DomainFixtures.note(text: "Türkçe not: şçğüö")
        XCTAssertEqual(FirestoreWorkOrderNoteDTO(domain: note).toDomain(), note)
    }

    func testStatusHistoryRoundTripPreservesPauseReasonAndNilFromStatus() {
        let withPause = WorkOrderStatusHistory(
            id: "h1",
            workOrderId: WorkOrderID("wo-1"),
            fromStatus: .inProgress,
            toStatus: .paused,
            pauseReason: .approvalWaiting,
            actorUserId: UserID("t"),
            occurredAt: DomainFixtures.referenceDate
        )
        XCTAssertEqual(FirestoreWorkOrderStatusHistoryDTO(domain: withPause).toDomain(), withPause)

        let creation = WorkOrderStatusHistory(
            id: "h0",
            workOrderId: WorkOrderID("wo-1"),
            fromStatus: nil,
            toStatus: .assigned,
            pauseReason: nil,
            actorUserId: UserID("op"),
            occurredAt: DomainFixtures.referenceDate
        )
        XCTAssertEqual(FirestoreWorkOrderStatusHistoryDTO(domain: creation).toDomain(), creation)
    }

    func testPhotoRoundTrip() {
        let photo = DomainFixtures.photo(id: "p", category: .evidenceSerialNumber)
        XCTAssertEqual(FirestoreWorkOrderPhotoDTO(domain: photo).toDomain(), photo)
    }

    func testLocationRoundTripPreservesCoordinateAccuracy() {
        let location = WorkOrderLocation(
            id: "l",
            workOrderId: WorkOrderID("wo"),
            event: .completed,
            coordinate: LocationCoordinate(latitude: 39.9208, longitude: 32.8541, accuracy: 3.75),
            capturedByUserId: UserID("t"),
            capturedAt: DomainFixtures.referenceDate
        )
        XCTAssertEqual(FirestoreWorkOrderLocationDTO(domain: location).toDomain(), location)
    }

    func testLocationRoundTripNilAccuracy() {
        let location = WorkOrderLocation(
            id: "l",
            workOrderId: WorkOrderID("wo"),
            event: .enRoute,
            coordinate: LocationCoordinate(latitude: 0, longitude: 0, accuracy: nil),
            capturedByUserId: UserID("t"),
            capturedAt: DomainFixtures.referenceDate
        )
        XCTAssertEqual(FirestoreWorkOrderLocationDTO(domain: location).toDomain(), location)
    }

    func testSignatureRoundTripBothKinds() {
        for kind in SignatureKind.allCases {
            let signature = DomainFixtures.signature(
                id: "sig-\(kind.rawValue)",
                kind: kind,
                signerName: kind == .customer ? "Müşteri" : nil
            )
            XCTAssertEqual(FirestoreSignatureDTO(domain: signature).toDomain(), signature)
        }
    }

    func testEditRequestRoundTripPendingAndDecided() {
        let pending = DomainFixtures.editRequest(status: .pending)
        XCTAssertEqual(FirestoreEditRequestDTO(domain: pending).toDomain(), pending)

        let approved = DomainFixtures.editRequest(
            status: .approved,
            reviewedByUserId: DomainFixtures.operatorUser().id,
            reviewedAt: DomainFixtures.referenceDate.addingTimeInterval(60)
        )
        XCTAssertEqual(FirestoreEditRequestDTO(domain: approved).toDomain(), approved)
    }

    func testNotificationRoundTripPreservesRelatedIDs() {
        let notification = AppNotification(
            id: NotificationID("n-1"),
            recipientUserId: UserID("u-1"),
            type: .editRequestApproved,
            title: "T",
            body: "B",
            relatedWorkOrderId: WorkOrderID("wo-42"),
            relatedEditRequestId: EditRequestID("er-9"),
            isRead: false,
            createdAt: DomainFixtures.referenceDate
        )
        XCTAssertEqual(FirestoreNotificationDTO(domain: notification).toDomain(), notification)
    }

    func testJSONMillisecondDateRoundTripPreservesTimestampFidelity() throws {
        let order = DomainFixtures.workOrder(completedAt: DomainFixtures.referenceDate)
        let dto = FirestoreWorkOrderDTO(domain: order)
        let data = try FirestoreJSON.encoder.encode(dto)
        let decoded = try FirestoreJSON.decoder.decode(FirestoreWorkOrderDTO.self, from: data)
        XCTAssertEqual(decoded.toDomain(), order)
        XCTAssertEqual(decoded.createdAt, order.createdAt)
        XCTAssertEqual(decoded.scheduledDate, order.scheduledDate)
    }

    func testUnknownEnumReturnsNilRatherThanCrashing() {
        let dto = FirestoreWorkOrderDTO(
            id: "wo",
            workOrderNumber: "WO",
            createdByUserId: "u",
            assignedTechnicianId: "t",
            customerId: "c",
            workType: "not-a-real-type",
            deviceCategory: "pos",
            deviceBrand: "x",
            deviceModel: "y",
            serialNumber: "z",
            issueDescription: nil,
            priority: "normal",
            scheduledDate: DomainFixtures.referenceDate,
            scheduledStart: nil,
            scheduledEnd: nil,
            status: "assigned",
            currentPauseReason: nil,
            createdAt: DomainFixtures.referenceDate,
            updatedAt: DomainFixtures.referenceDate,
            completedAt: nil
        )
        XCTAssertNil(dto.toDomain())
    }
}
