import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class AsyncLoadSessionTests: XCTestCase {

    override func tearDown() {
        AsyncLoadSession.indicatorDelay = .milliseconds(400)
        super.tearDown()
    }

    func testFastLoadDoesNotShowSpinnerBeforeDelay() async {
        AsyncLoadSession.indicatorDelay = .milliseconds(500)
        let session = AsyncLoadSession()
        let context = session.start(hadCachedContent: false)
        XCTAssertFalse(session.showsLoadingIndicator)

        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(session.showsLoadingIndicator)

        session.finish(generation: context.generation)
        XCTAssertFalse(session.showsLoadingIndicator)
    }

    func testSlowLoadShowsSpinnerAfterDelay() async {
        AsyncLoadSession.indicatorDelay = .milliseconds(100)
        let session = AsyncLoadSession()
        _ = session.start(hadCachedContent: false)

        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(session.showsLoadingIndicator)
    }

    func testCachedContentNeverShowsBlockingSpinner() async {
        AsyncLoadSession.indicatorDelay = .milliseconds(50)
        let session = AsyncLoadSession()
        _ = session.start(hadCachedContent: true)

        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(session.showsLoadingIndicator)
    }

    func testCancellationSettlesLoadingState() async {
        let session = AsyncLoadSession()
        let context = session.start(hadCachedContent: false)

        let settled = session.settleCancelledLoad(
            context: context,
            phase: "loading",
            loadingPhase: "loading",
            loadedPhase: "loaded",
            emptyPhase: "empty"
        )
        XCTAssertEqual(settled, "empty")
        XCTAssertFalse(session.showsLoadingIndicator)
    }

    func testCancellationWithCacheReturnsLoaded() async {
        let session = AsyncLoadSession()
        let context = session.start(hadCachedContent: true)

        let settled = session.settleCancelledLoad(
            context: context,
            phase: "loading",
            loadingPhase: "loading",
            loadedPhase: "loaded",
            emptyPhase: "empty"
        )
        XCTAssertEqual(settled, "loaded")
    }

    func testSupersededGenerationDoesNotSettleStaleLoad() async {
        let session = AsyncLoadSession()
        let first = session.start(hadCachedContent: false)
        _ = session.start(hadCachedContent: false)

        let settled = session.settleCancelledLoad(
            context: first,
            phase: "loading",
            loadingPhase: "loading",
            loadedPhase: "loaded",
            emptyPhase: "empty"
        )
        XCTAssertNil(settled)
    }

    func testFinishClearsDelayedIndicator() async {
        AsyncLoadSession.indicatorDelay = .milliseconds(200)
        let session = AsyncLoadSession()
        let context = session.start(hadCachedContent: false)

        try? await Task.sleep(for: .milliseconds(250)
        )
        XCTAssertTrue(session.showsLoadingIndicator)

        session.finish(generation: context.generation)
        XCTAssertFalse(session.showsLoadingIndicator)
    }
}

@MainActor
final class AsyncLoadContainerLogicTests: XCTestCase {

    func testNotificationListCancellationLeavesLoadingSettled() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(operatorUser)

        let vm = OperatorNotificationListViewModel(actor: operatorUser, dependencies: deps)
        let task = Task { await vm.load() }
        task.cancel()
        await task.value

        XCTAssertNotEqual(vm.phase, .loading)
        XCTAssertFalse(vm.showsLoadingIndicator)
    }

    func testReportDetailCacheShowsContentWithoutBlockingSpinner() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(DomainFixtures.customer())
        try await container.workOrderRepository.save(DomainFixtures.workOrder(status: .completed))

        let vm = AdminReportDetailViewModel(kind: .workOrders, actor: admin, dependencies: deps)
        await vm.load()
        XCTAssertTrue(vm.hasCachedContent)

        AsyncLoadSession.indicatorDelay = .milliseconds(200)
        await vm.load()
        XCTAssertFalse(vm.showsLoadingIndicator)
        XCTAssertEqual(vm.phase, .loaded)
    }
}
