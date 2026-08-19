import XCTest
@testable import DonanimOperasyonServis

/// Verifies that every Domain entity survives a full
/// `Domain → SwiftData → Domain` round-trip without losing data —
/// enum values, typed IDs, optional fields, `ScheduledTimeRange`,
/// and `LocationCoordinate` all round-trip identity-preserving.
final class DomainRoundTripTests: XCTestCase {

    func testUserRoundTrip() {
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
        let model = UserModel(domain: user)
        XCTAssertEqual(model.toDomain(), user)
    }

    func testUserWithNilPhoneRoundTrip() {
        let user = User(
            id: UserID("u-2"),
            email: "x@y.com",
            fullName: "Adsız",
            role: .admin,
            phoneNumber: nil,
            isActive: false,
            createdAt: DomainFixtures.referenceDate,
            updatedAt: DomainFixtures.referenceDate
        )
        XCTAssertEqual(UserModel(domain: user).toDomain(), user)
    }

    func testCustomerRoundTripWithAllOptionalFieldsSet() {
        let customer = Customer(
            id: CustomerID("c-1"),
            name: "Örnek Müşteri",
            contactPersonName: "Ali Kaya",
            phoneNumber: PhoneNumber("+90 555 999 88 77"),
            email: "info@ornek.com",
            address: "Adres 1",
            city: "Ankara",
            notes: "Not",
            createdByUserId: UserID("op-1"),
            createdAt: DomainFixtures.referenceDate,
            updatedAt: DomainFixtures.referenceDate
        )
        XCTAssertEqual(CustomerModel(domain: customer).toDomain(), customer)
    }

    func testCustomerRoundTripWithAllOptionalFieldsNil() {
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
        XCTAssertEqual(CustomerModel(domain: customer).toDomain(), customer)
    }

    func testWorkOrderRoundTripCoversEveryEnumAndScheduledTimeRange() {
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
        let model = WorkOrderModel(domain: order)
        XCTAssertEqual(model.toDomain(), order)
    }

    func testWorkOrderRoundTripWithoutOptionalRangeAndPauseReason() {
        let order = DomainFixtures.workOrder(
            scheduledTimeRange: nil,
            status: .completed,
            currentPauseReason: nil,
            completedAt: DomainFixtures.referenceDate.addingTimeInterval(3_600)
        )
        XCTAssertEqual(WorkOrderModel(domain: order).toDomain(), order)
    }

    func testNoteRoundTrip() {
        let note = DomainFixtures.note(text: "  Türkçe not: şçğüö  ")
        XCTAssertEqual(WorkOrderNoteModel(domain: note).toDomain(), note)
    }

    func testStatusHistoryRoundTripPreservesPauseReason() {
        let entry = WorkOrderStatusHistory(
            id: "h1",
            workOrderId: WorkOrderID("wo-1"),
            fromStatus: .inProgress,
            toStatus: .paused,
            pauseReason: .approvalWaiting,
            actorUserId: UserID("t"),
            occurredAt: DomainFixtures.referenceDate
        )
        XCTAssertEqual(WorkOrderStatusHistoryModel(domain: entry).toDomain(), entry)
    }

    func testStatusHistoryRoundTripWithNilFromStatus() {
        let entry = WorkOrderStatusHistory(
            id: "h1",
            workOrderId: WorkOrderID("wo-1"),
            fromStatus: nil,
            toStatus: .assigned,
            pauseReason: nil,
            actorUserId: UserID("op"),
            occurredAt: DomainFixtures.referenceDate
        )
        XCTAssertEqual(WorkOrderStatusHistoryModel(domain: entry).toDomain(), entry)
    }

    func testPhotoRoundTrip() {
        let photo = DomainFixtures.photo(id: "p", category: .evidenceSerialNumber)
        XCTAssertEqual(WorkOrderPhotoModel(domain: photo).toDomain(), photo)
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
        XCTAssertEqual(WorkOrderLocationModel(domain: location).toDomain(), location)
    }

    func testLocationRoundTripWithNilAccuracy() {
        let location = WorkOrderLocation(
            id: "l",
            workOrderId: WorkOrderID("wo"),
            event: .enRoute,
            coordinate: LocationCoordinate(latitude: 0, longitude: 0, accuracy: nil),
            capturedByUserId: UserID("t"),
            capturedAt: DomainFixtures.referenceDate
        )
        XCTAssertEqual(WorkOrderLocationModel(domain: location).toDomain(), location)
    }

    func testSignatureRoundTripBothKinds() {
        for kind in SignatureKind.allCases {
            let signature = DomainFixtures.signature(id: "sig-\(kind.rawValue)", kind: kind, signerName: kind == .customer ? "Müşteri" : nil)
            XCTAssertEqual(SignatureModel(domain: signature).toDomain(), signature)
        }
    }

    func testEditRequestRoundTripPendingAndDecided() {
        let pending = DomainFixtures.editRequest(status: .pending)
        XCTAssertEqual(EditRequestModel(domain: pending).toDomain(), pending)

        let approved = DomainFixtures.editRequest(
            status: .approved,
            reviewedByUserId: DomainFixtures.operatorUser().id,
            reviewedAt: DomainFixtures.referenceDate.addingTimeInterval(60)
        )
        XCTAssertEqual(EditRequestModel(domain: approved).toDomain(), approved)
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
        XCTAssertEqual(NotificationModel(domain: notification).toDomain(), notification)
    }
}
