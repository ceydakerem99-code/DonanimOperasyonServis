import XCTest
@testable import DonanimOperasyonServis

final class FirestoreWriteEncodingTests: XCTestCase {

    func testLiveSetAndCommitEncodeDatesAsTheSameTimestamps() throws {
        let dto = FirestoreUserDTO(domain: DomainFixtures.operatorUser())
        let fromSet = try LiveFirestoreConfiguration.encode(dto)
        let fromCommit = try LiveFirestoreConfiguration.encode(FirestoreEncodableBox(dto))

        XCTAssertEqual(fromSet.keys, fromCommit.keys)
        XCTAssertTrue(LiveFirestoreConfiguration.isTimestamp(fromSet["createdAt"]))
        XCTAssertTrue(LiveFirestoreConfiguration.isTimestamp(fromSet["updatedAt"]))
        XCTAssertTrue(LiveFirestoreConfiguration.isTimestamp(fromCommit["createdAt"]))
        XCTAssertTrue(LiveFirestoreConfiguration.isTimestamp(fromCommit["updatedAt"]))

        // Same encoder, same DTO, same boxed encode(to:) forwarding.
        XCTAssertEqual(fromSet as NSDictionary, fromCommit as NSDictionary)
    }

    func testWorkOrderDatesAreTimestampsOnBothWritePaths() throws {
        let dto = FirestoreWorkOrderDTO(domain: DomainFixtures.workOrder())
        let fromSet = try LiveFirestoreConfiguration.encode(dto)
        let fromCommit = try LiveFirestoreConfiguration.encode(FirestoreEncodableBox(dto))

        for key in ["createdAt", "updatedAt", "scheduledDate", "scheduledStart", "scheduledEnd"] {
            XCTAssertTrue(LiveFirestoreConfiguration.isTimestamp(fromSet[key]), "set path \(key)")
            XCTAssertTrue(LiveFirestoreConfiguration.isTimestamp(fromCommit[key]), "commit path \(key)")
        }
        XCTAssertEqual(fromSet as NSDictionary, fromCommit as NSDictionary)
    }

    func testFakeSetCompletesBeforeSubsequentFetch() async throws {
        let fake = FakeFirestoreDataSource()
        let user = DomainFixtures.technicianUser()
        let dto = FirestoreUserDTO(domain: user)

        try await fake.set(dto, collection: .users, id: dto.id)
        let fetched = try await fake.fetch(FirestoreUserDTO.self, collection: .users, id: dto.id)
        XCTAssertEqual(fetched, dto)
    }

    func testFakeCommitUsesTheSameJSONEncoderAsSet() async throws {
        let viaSet = FakeFirestoreDataSource()
        let viaCommit = FakeFirestoreDataSource()
        let dto = FirestoreUserDTO(domain: DomainFixtures.operatorUser())

        try await viaSet.set(dto, collection: .users, id: dto.id)
        try await viaCommit.commit([
            FirestoreWrite.set(dto, collection: .users, id: dto.id)
        ])

        let fromSet = try await viaSet.fetch(FirestoreUserDTO.self, collection: .users, id: dto.id)
        let fromCommit = try await viaCommit.fetch(FirestoreUserDTO.self, collection: .users, id: dto.id)
        XCTAssertEqual(fromSet, fromCommit)
        XCTAssertEqual(fromSet, dto)
    }
}
