import XCTest
@testable import DonanimOperasyonServis

final class AddWorkOrderPhotoUseCaseTests: XCTestCase {

    func makeUseCase() -> (
        AddWorkOrderPhotoUseCase,
        InMemoryWorkOrderRepository,
        InMemoryPhotoRepository
    ) {
        let orders = InMemoryWorkOrderRepository()
        let photos = InMemoryPhotoRepository()
        let useCase = AddWorkOrderPhotoUseCase(
            workOrderRepository: orders,
            photoRepository: photos
        )
        return (useCase, orders, photos)
    }

    func testAssignedTechnicianCanAddPhoto() async throws {
        let (useCase, orders, photos) = makeUseCase()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(assignedTechnicianId: tech.id, status: .inProgress)
        try await orders.save(order)

        let photo = try await useCase.execute(
            actor: tech,
            orderId: order.id,
            category: .before,
            storagePath: "pending://photos/test.jpg",
            photoId: "photo-1",
            at: DomainFixtures.referenceDate
        )

        XCTAssertEqual(photo.workOrderId, order.id)
        XCTAssertEqual(photo.category, .before)
        XCTAssertEqual(photo.capturedByUserId, tech.id)
        let stored = try await photos.list(for: order.id)
        XCTAssertEqual(stored.count, 1)
    }

    func testOtherTechnicianUnauthorized() async {
        let (useCase, orders, _) = makeUseCase()
        let assigned = DomainFixtures.technicianUser(id: UserID("tech-a"))
        let other = DomainFixtures.technicianUser(id: UserID("tech-b"), email: "b@example.com")
        let order = DomainFixtures.workOrder(assignedTechnicianId: assigned.id, status: .inProgress)
        try? await orders.save(order)

        do {
            _ = try await useCase.execute(
                actor: other,
                orderId: order.id,
                category: .after,
                storagePath: nil
            )
            XCTFail("expected unauthorized")
        } catch let error as DomainError {
            guard case .unauthorized = error else {
                return XCTFail("unexpected \(error)")
            }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testCompletedWorkOrderLocked() async {
        let (useCase, orders, _) = makeUseCase()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(assignedTechnicianId: tech.id, status: .completed)
        try? await orders.save(order)

        do {
            _ = try await useCase.execute(
                actor: tech,
                orderId: order.id,
                category: .before,
                storagePath: nil
            )
            XCTFail("expected locked")
        } catch let error as DomainError {
            guard case .workOrderLocked = error else {
                return XCTFail("unexpected \(error)")
            }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
