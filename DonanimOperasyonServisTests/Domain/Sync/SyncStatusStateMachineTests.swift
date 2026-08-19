import XCTest
@testable import DonanimOperasyonServis

final class SyncStatusStateMachineTests: XCTestCase {

    func testAllowedTransitionsSucceed() throws {
        XCTAssertEqual(try SyncStatusStateMachine.transition(from: .pending, to: .inProgress), .inProgress)
        XCTAssertEqual(try SyncStatusStateMachine.transition(from: .inProgress, to: .succeeded), .succeeded)
        XCTAssertEqual(try SyncStatusStateMachine.transition(from: .inProgress, to: .failed), .failed)
        XCTAssertEqual(try SyncStatusStateMachine.transition(from: .inProgress, to: .conflict), .conflict)
    }

    func testTransitionTable() {
        XCTAssertEqual(SyncStatusStateMachine.allowedTransitions(from: .pending), [.inProgress])
        XCTAssertEqual(
            SyncStatusStateMachine.allowedTransitions(from: .inProgress),
            [.succeeded, .failed, .conflict]
        )
        XCTAssertEqual(SyncStatusStateMachine.allowedTransitions(from: .succeeded), [])
        XCTAssertEqual(SyncStatusStateMachine.allowedTransitions(from: .failed), [])
        XCTAssertEqual(SyncStatusStateMachine.allowedTransitions(from: .conflict), [])
    }

    func testInvalidTransitionsAreRejected() {
        let invalid: [(SyncStatus, SyncStatus)] = [
            (.pending, .succeeded),
            (.pending, .failed),
            (.pending, .conflict),
            (.inProgress, .pending),
            (.succeeded, .pending),
            (.failed, .pending),
            (.failed, .inProgress),
            (.conflict, .inProgress),
            (.conflict, .succeeded)
        ]
        for (from, to) in invalid {
            XCTAssertFalse(SyncStatusStateMachine.canTransition(from: from, to: to))
            XCTAssertThrowsError(try SyncStatusStateMachine.transition(from: from, to: to)) { error in
                XCTAssertEqual(
                    error as? DomainError,
                    .invalidSyncStatusTransition(from: from, to: to)
                )
            }
        }
    }
}
