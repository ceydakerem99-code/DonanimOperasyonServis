import XCTest
@testable import DonanimOperasyonServis

final class FirebaseCustomerRepositoryTests: XCTestCase {

    private func makeCustomer(
        id: CustomerID = CustomerID("cust-1"),
        name: String = "Migros Bahçelievler"
    ) -> Customer {
        Customer(
            id: id,
            name: name,
            contactPersonName: "Ayşe",
            phoneNumber: PhoneNumber("+90 555 111 22 33"),
            email: "ayse@example.com",
            address: "Cadde 1",
            city: "İstanbul",
            notes: nil,
            createdByUserId: UserID("user-operator-1"),
            createdAt: DomainFixtures.referenceDate,
            updatedAt: DomainFixtures.referenceDate
        )
    }

    func testSaveFetchListDelete() async throws {
        let harness = FirebaseTestHarness()
        let a = makeCustomer(id: CustomerID("a"), name: "Migros Bahçelievler")
        let b = makeCustomer(id: CustomerID("b"), name: "A101 Kadıköy")
        try await harness.customers.save(a)
        try await harness.customers.save(b)

        let fetched = try await harness.customers.fetch(id: a.id)
        XCTAssertEqual(fetched, a)

        let all = try await harness.customers.list(searchText: nil)
        XCTAssertEqual(Set(all.map(\.id)), Set([a.id, b.id]))

        let filtered = try await harness.customers.list(searchText: "migros")
        XCTAssertEqual(filtered.map(\.id), [a.id])

        try await harness.customers.delete(id: a.id)
        await XCTAssertThrowsErrorAsync(try await harness.customers.fetch(id: a.id)) { _ in }
    }

    func testFetchUnknownThrowsNotFound() async throws {
        let harness = FirebaseTestHarness()
        await XCTAssertThrowsErrorAsync(
            try await harness.customers.fetch(id: CustomerID("missing"))
        ) { error in
            XCTAssertEqual(error as? DomainError, .notFound(entity: "Customer", id: "missing"))
        }
    }
}
