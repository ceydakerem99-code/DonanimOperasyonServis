import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class SignatureReportSearchTests: XCTestCase {

    private func sampleEntry(
        customer: String,
        technician: String,
        workOrderNumber: String,
        status: String
    ) -> SignatureReportEntry {
        let orderId = WorkOrderID("wo-\(workOrderNumber)")
        return SignatureReportEntry(
            id: "sig-\(workOrderNumber)",
            signature: DomainFixtures.signature(
                workOrderId: orderId,
                kind: .customer,
                signerName: customer
            ),
            workOrderId: orderId,
            workOrderNumber: workOrderNumber,
            customerName: customer,
            workplace: "\(customer) · İstanbul",
            technicianName: technician,
            signerName: customer,
            capturedAt: DomainFixtures.referenceDate,
            statusLabel: status
        )
    }

    func testNameWorkplaceWorkOrderTechnicianAndStatusSearch() {
        let rows = [
            sampleEntry(customer: "ABC Market", technician: "Mehmet Kerem", workOrderNumber: "WO-123", status: "İmzalı"),
            sampleEntry(customer: "XYZ Ltd", technician: "Ayşe Demir", workOrderNumber: "WO-456", status: "İmzasız")
        ]

        XCTAssertEqual(SignatureReportSearch.filter(rows, query: "Mehmet").map(\.workOrderId), [WorkOrderID("wo-WO-123")])
        XCTAssertEqual(SignatureReportSearch.filter(rows, query: "ABC").map(\.workOrderId), [WorkOrderID("wo-WO-123")])
        XCTAssertEqual(SignatureReportSearch.filter(rows, query: "WO-123").map(\.workOrderId), [WorkOrderID("wo-WO-123")])
        XCTAssertEqual(SignatureReportSearch.filter(rows, query: "Ayse").map(\.workOrderId), [WorkOrderID("wo-WO-456")])
        XCTAssertEqual(SignatureReportSearch.filter(rows, query: "İmzalı").map(\.workOrderId), [WorkOrderID("wo-WO-123")])
        XCTAssertEqual(SignatureReportSearch.filter(rows, query: "").count, 2)
    }

    func testSignatureSearchIsLocalFilterOnly() {
        let rows = [sampleEntry(customer: "ABC", technician: "Mehmet Kerem", workOrderNumber: "WO-123", status: "İmzalı")]
        let filtered = SignatureReportSearch.filter(rows, query: "mehmet")
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.technicianName, "Mehmet Kerem")
    }
}
