import XCTest
@testable import DonanimOperasyonServis

final class CompletionRequirementsBeforeCompleteActionTests: XCTestCase {

    func testMissingCompletedGPSIsExcludedFromBeforeCompleteAction() {
        var full = DomainFixtures.fullCompletionContext(for: .installation)
        full = CompletionContext(
            workType: full.workType,
            notes: full.notes,
            photos: full.photos,
            locations: full.locations.filter { $0.event != .completed },
            signatures: full.signatures
        )

        XCTAssertEqual(CompletionRequirements.missingBeforeCompleteAction(full), [])
        guard case .failure(let missing) = CompletionRequirements.check(full) else {
            return XCTFail("full check should still require completed GPS")
        }
        XCTAssertTrue(missing.items.contains(.missingLocation(.completed)))
    }

    func testMissingNoteStillBlocksBeforeCompleteAction() {
        var full = DomainFixtures.fullCompletionContext(for: .installation)
        full = CompletionContext(
            workType: full.workType,
            notes: [],
            photos: full.photos,
            locations: full.locations,
            signatures: full.signatures
        )
        XCTAssertEqual(
            CompletionRequirements.missingBeforeCompleteAction(full),
            [.missingNote]
        )
    }

    func testMissingPhotoStillBlocksBeforeCompleteAction() {
        var full = DomainFixtures.fullCompletionContext(for: .installation)
        full = CompletionContext(
            workType: full.workType,
            notes: full.notes,
            photos: full.photos.filter { $0.category != .after },
            locations: full.locations,
            signatures: full.signatures
        )
        XCTAssertEqual(
            CompletionRequirements.missingBeforeCompleteAction(full),
            [.missingPhoto(.after)]
        )
    }

    func testMissingSignatureStillBlocksBeforeCompleteAction() {
        var full = DomainFixtures.fullCompletionContext(for: .installation)
        full = CompletionContext(
            workType: full.workType,
            notes: full.notes,
            photos: full.photos,
            locations: full.locations,
            signatures: full.signatures.filter { $0.kind != .customer }
        )
        XCTAssertEqual(
            CompletionRequirements.missingBeforeCompleteAction(full),
            [.missingCustomerSignature]
        )
    }

    func testMissingEnRouteGPSStillBlocksBeforeCompleteAction() {
        var full = DomainFixtures.fullCompletionContext(for: .installation)
        full = CompletionContext(
            workType: full.workType,
            notes: full.notes,
            photos: full.photos,
            locations: full.locations.filter { $0.event != .enRoute },
            signatures: full.signatures
        )
        XCTAssertTrue(
            CompletionRequirements.missingBeforeCompleteAction(full)
                .contains(.missingLocation(.enRoute))
        )
    }
}
