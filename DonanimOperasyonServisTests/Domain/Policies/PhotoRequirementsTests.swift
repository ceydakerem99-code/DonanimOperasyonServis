import XCTest
@testable import DonanimOperasyonServis

final class PhotoRequirementsTests: XCTestCase {

    func testInstallationRequiresBeforeAndAfter() {
        XCTAssertEqual(
            PhotoRequirements.requiredCategories(for: .installation),
            [.before, .after]
        )
    }

    func testMaintenanceRequiresBeforeAndAfter() {
        XCTAssertEqual(
            PhotoRequirements.requiredCategories(for: .maintenance),
            [.before, .after]
        )
    }

    func testRepairRequiresBeforeAfterAndEvidence() {
        XCTAssertEqual(
            PhotoRequirements.requiredCategories(for: .repair),
            [.before, .after, .evidenceSerialNumber]
        )
    }

    func testDeliveryRequiresOnlyEvidenceSerialNumber() {
        XCTAssertEqual(
            PhotoRequirements.requiredCategories(for: .delivery),
            [.evidenceSerialNumber]
        )
    }

    func testMissingCategoriesReflectsMissingItems() {
        let photos = [
            DomainFixtures.photo(id: "p1", category: .before)
        ]
        let missing = PhotoRequirements.missingCategories(for: .repair, given: photos)
        XCTAssertEqual(missing, [.after, .evidenceSerialNumber])
    }

    func testMissingCategoriesEmptyWhenAllProvided() {
        let photos = PhotoRequirements
            .requiredCategories(for: .installation)
            .enumerated()
            .map { DomainFixtures.photo(id: "p\($0.offset)", category: $0.element) }
        XCTAssertTrue(
            PhotoRequirements.missingCategories(for: .installation, given: photos).isEmpty
        )
    }
}
