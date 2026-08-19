import XCTest
@testable import DonanimOperasyonServis

final class EditRequestStateMachineTests: XCTestCase {

    func testPendingCanBeApproved() throws {
        XCTAssertTrue(EditRequestStateMachine.canTransition(from: .pending, to: .approved))
        let result = try EditRequestStateMachine.transition(from: .pending, to: .approved)
        XCTAssertEqual(result, .approved)
    }

    func testPendingCanBeRejected() throws {
        XCTAssertTrue(EditRequestStateMachine.canTransition(from: .pending, to: .rejected))
        let result = try EditRequestStateMachine.transition(from: .pending, to: .rejected)
        XCTAssertEqual(result, .rejected)
    }

    func testApprovedIsTerminal() {
        for target in EditRequestStatus.allCases {
            XCTAssertFalse(
                EditRequestStateMachine.canTransition(from: .approved, to: target),
                "Approved must not transition to \(target)"
            )
            XCTAssertThrowsError(try EditRequestStateMachine.transition(from: .approved, to: target)) { error in
                XCTAssertEqual(
                    error as? DomainError,
                    .invalidEditRequestTransition(from: .approved, to: target)
                )
            }
        }
    }

    func testRejectedIsTerminal() {
        for target in EditRequestStatus.allCases {
            XCTAssertFalse(
                EditRequestStateMachine.canTransition(from: .rejected, to: target),
                "Rejected must not transition to \(target)"
            )
            XCTAssertThrowsError(try EditRequestStateMachine.transition(from: .rejected, to: target)) { error in
                XCTAssertEqual(
                    error as? DomainError,
                    .invalidEditRequestTransition(from: .rejected, to: target)
                )
            }
        }
    }

    func testPendingCannotSelfTransition() {
        XCTAssertFalse(EditRequestStateMachine.canTransition(from: .pending, to: .pending))
    }

    func testIsTerminalFlagOnStatus() {
        XCTAssertFalse(EditRequestStatus.pending.isTerminal)
        XCTAssertTrue(EditRequestStatus.approved.isTerminal)
        XCTAssertTrue(EditRequestStatus.rejected.isTerminal)
    }
}
