import XCTest
@testable import DonanimOperasyonServis

final class FirebaseStoragePathTests: XCTestCase {

    func testPhotoPathLayout() {
        let path = FirebaseStoragePath.photo(
            workOrderId: WorkOrderID("wo-42"),
            photoId: "photo-9"
        )
        XCTAssertEqual(path.rawValue, "workOrders/wo-42/photos/photo-9")
    }

    func testSignaturePathLayout() {
        let path = FirebaseStoragePath.signature(
            workOrderId: WorkOrderID("wo-42"),
            signatureId: "sig-1"
        )
        XCTAssertEqual(path.rawValue, "workOrders/wo-42/signatures/sig-1")
    }

    func testFakeStorageUploadDownloadDelete() async throws {
        let storage = FakeFirebaseStorageDataSource()
        let path = FirebaseStoragePath.photo(workOrderId: WorkOrderID("wo"), photoId: "p1")
        let payload = Data("jpeg-bytes".utf8)

        let returned = try await storage.upload(data: payload, to: path)
        XCTAssertEqual(returned, path.rawValue)

        let downloaded = try await storage.download(from: path)
        XCTAssertEqual(downloaded, payload)

        try await storage.delete(path)
        do {
            _ = try await storage.download(from: path)
            XCTFail("expected notFound after delete")
        } catch {
            XCTAssertEqual(error as? FirebaseError, .notFound)
        }
    }

    func testFakeStorageDeleteIsIdempotent() async throws {
        let storage = FakeFirebaseStorageDataSource()
        let path = FirebaseStoragePath.signature(workOrderId: WorkOrderID("wo"), signatureId: "s")
        try await storage.delete(path)
    }
}
