import XCTest
@testable import DonanimOperasyonServis

final class WorkOrderStateMachineTests: XCTestCase {

    // MARK: - Allowed transitions

    func testAllValidTransitionsSucceed() throws {
        let validPairs: [(WorkOrderStatus, WorkOrderStatus)] = [
            (.assigned,   .accepted),
            (.accepted,   .enRoute),
            (.enRoute,    .arrived),
            (.arrived,    .inProgress),
            (.inProgress, .paused),
            (.paused,     .inProgress),
            (.inProgress, .completed)
        ]
        for (from, to) in validPairs {
            XCTAssertTrue(
                WorkOrderStateMachine.canTransition(from: from, to: to),
                "Expected \(from) -> \(to) to be allowed"
            )
            let result = try WorkOrderStateMachine.transition(from: from, to: to)
            XCTAssertEqual(result, to)
        }
    }

    func testAllowedTransitionsTableMatchesExpectation() {
        XCTAssertEqual(WorkOrderStateMachine.allowedTransitions(from: .assigned),   [.accepted])
        XCTAssertEqual(WorkOrderStateMachine.allowedTransitions(from: .accepted),   [.enRoute])
        XCTAssertEqual(WorkOrderStateMachine.allowedTransitions(from: .enRoute),    [.arrived])
        XCTAssertEqual(WorkOrderStateMachine.allowedTransitions(from: .arrived),    [.inProgress])
        XCTAssertEqual(WorkOrderStateMachine.allowedTransitions(from: .inProgress), [.paused, .completed])
        XCTAssertEqual(WorkOrderStateMachine.allowedTransitions(from: .paused),     [.inProgress])
        XCTAssertEqual(WorkOrderStateMachine.allowedTransitions(from: .completed),  [])
    }

    // MARK: - Invalid transitions

    func testInvalidTransitionsAreRejected() {
        let invalidPairs: [(WorkOrderStatus, WorkOrderStatus)] = [
            (.assigned,   .enRoute),
            (.assigned,   .completed),
            (.accepted,   .arrived),
            (.enRoute,    .inProgress),
            (.arrived,    .completed),
            (.paused,     .completed),
            (.accepted,   .assigned),
            (.inProgress, .arrived)
        ]
        for (from, to) in invalidPairs {
            XCTAssertFalse(
                WorkOrderStateMachine.canTransition(from: from, to: to),
                "Expected \(from) -> \(to) to be rejected"
            )
            XCTAssertThrowsError(try WorkOrderStateMachine.transition(from: from, to: to)) { error in
                XCTAssertEqual(
                    error as? DomainError,
                    .invalidStateTransition(from: from, to: to)
                )
            }
        }
    }

    // MARK: - Completed lock

    func testAllTransitionsFromCompletedAreRejected() {
        for target in WorkOrderStatus.allCases where target != .completed {
            XCTAssertFalse(
                WorkOrderStateMachine.canTransition(from: .completed, to: target),
                "Completed must not transition to \(target)"
            )
            XCTAssertThrowsError(try WorkOrderStateMachine.transition(from: .completed, to: target)) { error in
                XCTAssertEqual(
                    error as? DomainError,
                    .invalidStateTransition(from: .completed, to: target)
                )
            }
        }
    }

    // MARK: - Paused resume path

    func testPausedResumesToInProgress() throws {
        let result = try WorkOrderStateMachine.transition(from: .paused, to: .inProgress)
        XCTAssertEqual(result, .inProgress)
    }

    func testSelfTransitionsAreRejected() {
        for status in WorkOrderStatus.allCases {
            XCTAssertFalse(WorkOrderStateMachine.canTransition(from: status, to: status))
        }
    }
}
