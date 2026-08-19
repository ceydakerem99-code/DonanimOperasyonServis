import XCTest
@testable import DonanimOperasyonServis

final class CompletionRequirementsTests: XCTestCase {

    // MARK: - Happy path

    func testFullyPopulatedContextForEveryWorkTypeSucceeds() {
        for workType in WorkType.allCases {
            let context = DomainFixtures.fullCompletionContext(for: workType)
            let result = CompletionRequirements.check(context)
            switch result {
            case .success:
                break
            case .failure(let missing):
                XCTFail("Expected success for \(workType) but got \(missing.items)")
            }
        }
    }

    // MARK: - Individual gaps

    func testMissingNoteIsReported() {
        var context = DomainFixtures.fullCompletionContext(for: .installation)
        context = CompletionContext(
            workType: context.workType,
            notes: [],
            photos: context.photos,
            locations: context.locations,
            signatures: context.signatures
        )
        assertMissing(.missingNote, in: context)
    }

    func testMissingPhotosAreReportedForEachCategory() {
        // Installation requires [.before, .after]. Provide only .before.
        let context = CompletionContext(
            workType: .installation,
            notes: [DomainFixtures.note()],
            photos: [DomainFixtures.photo(id: "p1", category: .before)],
            locations: LocationEvent.allCases.enumerated().map { i, e in
                DomainFixtures.location(id: "l\(i)", event: e)
            },
            signatures: [
                DomainFixtures.signature(id: "st", kind: .technician),
                DomainFixtures.signature(id: "sc", kind: .customer)
            ]
        )
        assertMissing(.missingPhoto(.after), in: context)
    }

    func testMissingLocationEventsAreReportedForEachEvent() {
        // Full context minus the .arrived location.
        var context = DomainFixtures.fullCompletionContext(for: .maintenance)
        let filteredLocations = context.locations.filter { $0.event != .arrived }
        context = CompletionContext(
            workType: context.workType,
            notes: context.notes,
            photos: context.photos,
            locations: filteredLocations,
            signatures: context.signatures
        )
        assertMissing(.missingLocation(.arrived), in: context)
    }

    func testMissingTechnicianSignatureIsReported() {
        var context = DomainFixtures.fullCompletionContext(for: .repair)
        context = CompletionContext(
            workType: context.workType,
            notes: context.notes,
            photos: context.photos,
            locations: context.locations,
            signatures: context.signatures.filter { $0.kind != .technician }
        )
        assertMissing(.missingTechnicianSignature, in: context)
    }

    func testMissingCustomerSignatureIsReported() {
        var context = DomainFixtures.fullCompletionContext(for: .repair)
        context = CompletionContext(
            workType: context.workType,
            notes: context.notes,
            photos: context.photos,
            locations: context.locations,
            signatures: context.signatures.filter { $0.kind != .customer }
        )
        assertMissing(.missingCustomerSignature, in: context)
    }

    // MARK: - Aggregation

    func testAllGapsAreReportedTogetherForEmptyContext() {
        let context = CompletionContext(workType: .repair)
        let result = CompletionRequirements.check(context)
        switch result {
        case .success:
            XCTFail("Expected failure for empty context")
        case .failure(let missing):
            let items = Set(missing.items)
            XCTAssertTrue(items.contains(.missingNote))
            XCTAssertTrue(items.contains(.missingPhoto(.before)))
            XCTAssertTrue(items.contains(.missingPhoto(.after)))
            XCTAssertTrue(items.contains(.missingPhoto(.evidenceSerialNumber)))
            XCTAssertTrue(items.contains(.missingLocation(.enRoute)))
            XCTAssertTrue(items.contains(.missingLocation(.arrived)))
            XCTAssertTrue(items.contains(.missingLocation(.completed)))
            XCTAssertTrue(items.contains(.missingTechnicianSignature))
            XCTAssertTrue(items.contains(.missingCustomerSignature))
        }
    }

    // MARK: - Helpers

    private func assertMissing(
        _ requirement: MissingRequirement,
        in context: CompletionContext,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = CompletionRequirements.check(context)
        switch result {
        case .success:
            XCTFail("Expected \(requirement) to be reported as missing", file: file, line: line)
        case .failure(let missing):
            XCTAssertTrue(
                missing.items.contains(requirement),
                "Expected missing items to contain \(requirement), got \(missing.items)",
                file: file,
                line: line
            )
        }
    }
}
