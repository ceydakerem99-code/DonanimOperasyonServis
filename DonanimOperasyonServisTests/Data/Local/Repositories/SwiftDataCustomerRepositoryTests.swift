import XCTest
@testable import DonanimOperasyonServis

final class SwiftDataCustomerRepositoryTests: XCTestCase {

    private func makeCustomer(
        id: CustomerID = CustomerID("cust-1"),
        name: String = "Migros Bahçelievler",
        city: String? = "İstanbul"
    ) -> Customer {
        Customer(
            id: id,
            name: name,
            contactPersonName: "Ayşe Yıldız",
            phoneNumber: PhoneNumber("+90 555 111 22 33"),
            email: "ayse@example.com",
            address: "Bahçelievler Cd. No: 12",
            city: city,
            notes: "Zil çalışmıyor",
            createdByUserId: UserID("user-operator-1"),
            createdAt: DomainFixtures.referenceDate,
            updatedAt: DomainFixtures.referenceDate
        )
    }

    func testSaveThenFetch() async throws {
        let harness = try SwiftDataTestHarness()
        let customer = makeCustomer()
        try await harness.customers.save(customer)
        let fetched = try await harness.customers.fetch(id: customer.id)
        XCTAssertEqual(fetched, customer)
    }

    func testFetchUnknownIdThrowsNotFound() async throws {
        let harness = try SwiftDataTestHarness()
        await XCTAssertThrowsErrorAsync(
            try await harness.customers.fetch(id: CustomerID("missing"))
        ) { error in
            XCTAssertEqual(error as? DomainError, .notFound(entity: "Customer", id: "missing"))
        }
    }

    func testListReturnsAllAndSearchNarrowsByName() async throws {
        let harness = try SwiftDataTestHarness()
        let a = makeCustomer(id: CustomerID("a"), name: "Migros Bahçelievler")
        let b = makeCustomer(id: CustomerID("b"), name: "A101 Kadıköy")
        let c = makeCustomer(id: CustomerID("c"), name: "BIM Beşiktaş")
        for customer in [a, b, c] { try await harness.customers.save(customer) }

        let all = try await harness.customers.list(searchText: nil)
        XCTAssertEqual(all.count, 3)

        let filtered = try await harness.customers.list(searchText: "migros")
        XCTAssertEqual(filtered.map(\.id), [a.id])
    }

    func testDeleteRemovesCustomer() async throws {
        let harness = try SwiftDataTestHarness()
        let customer = makeCustomer()
        try await harness.customers.save(customer)
        try await harness.customers.delete(id: customer.id)

        await XCTAssertThrowsErrorAsync(
            try await harness.customers.fetch(id: customer.id)
        ) { _ in }
    }
}
