import XCTest
@testable import DonanimOperasyonServis

final class CreateUserUseCaseTests: XCTestCase {

    func testAdminCreatesUserLocallyViaAuthProvisioner() async throws {
        let users = InMemoryUserRepository()
        let auth = FakeAuthAccountCreator()
        auth.setNextUID("new-op-uid")
        let useCase = CreateUserUseCase(userRepository: users, authAccounts: auth)
        let admin = DomainFixtures.adminUser()

        let created = try await useCase.execute(
            actor: admin,
            email: "op@dops.com",
            password: "secret1",
            fullName: "Operasyon",
            role: .operator
        )

        XCTAssertEqual(created.id.rawValue, "new-op-uid")
        XCTAssertEqual(created.email, "op@dops.com")
        XCTAssertEqual(created.role, .operator)
        let stored = try await users.fetch(id: created.id)
        XCTAssertEqual(stored.fullName, "Operasyon")
    }

    func testOperatorCannotCreateUser() async {
        let useCase = CreateUserUseCase(
            userRepository: InMemoryUserRepository(),
            authAccounts: FakeAuthAccountCreator()
        )
        await XCTAssertThrowsErrorAsync(
            try await useCase.execute(
                actor: DomainFixtures.operatorUser(),
                email: "x@dops.com",
                password: "secret1",
                fullName: "X",
                role: .technician
            )
        ) { error in
            XCTAssertEqual(error as? DomainError, .unauthorized(action: .manageUsers))
        }
    }

    func testRejectsWeakPassword() async {
        let useCase = CreateUserUseCase(
            userRepository: InMemoryUserRepository(),
            authAccounts: FakeAuthAccountCreator()
        )
        await XCTAssertThrowsErrorAsync(
            try await useCase.execute(
                actor: DomainFixtures.adminUser(),
                email: "x@dops.com",
                password: "123",
                fullName: "X",
                role: .technician
            )
        ) { error in
            guard case .invalidData(let reason) = error as? DomainError else {
                return XCTFail("expected invalidData")
            }
            XCTAssertEqual(reason, "user.weakPassword")
        }
    }
}

@MainActor
final class AdminCreateUserViewModelTests: XCTestCase {

    func testCreateUserSuccess() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        try await deps.userRepository.save(admin)

        let vm = AdminCreateUserViewModel(actor: admin, dependencies: deps)
        vm.fullName = "Teknisyen Ali"
        vm.email = "tech@dops.com"
        vm.password = "secret12"
        vm.role = .technician

        await vm.create()

        guard case .created(let id) = vm.phase else {
            return XCTFail("expected created, got \(vm.phase)")
        }
        let stored = try await deps.userRepository.fetch(id: id)
        XCTAssertEqual(stored.role, .technician)
        XCTAssertEqual(stored.email, "tech@dops.com")

        let pending = try await deps.syncOperationRepository.list(
            entityType: .user,
            entityId: id.rawValue
        )
        XCTAssertTrue(pending.contains { $0.operationType == .create })
    }

    func testCreateUserUnauthorized() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let operatorUser = DomainFixtures.operatorUser()

        let vm = AdminCreateUserViewModel(actor: operatorUser, dependencies: deps)
        vm.fullName = "X"
        vm.email = "x@dops.com"
        vm.password = "secret12"

        await vm.create()

        guard case .error(let message) = vm.phase else {
            return XCTFail("expected error")
        }
        XCTAssertTrue(message.contains("yetkiniz"))
    }
}
