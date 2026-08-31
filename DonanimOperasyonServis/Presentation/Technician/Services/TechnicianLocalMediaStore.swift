import Foundation

/// Local on-disk cache for technician-captured photo / signature bytes.
/// Domain metadata still goes through existing repositories; this store
/// only keeps binaries so offline captures survive until sync uploads them.
enum TechnicianLocalMediaStore {
    private static let photosFolder = "TechnicianPhotos"
    private static let signaturesFolder = "TechnicianSignatures"

    static func photoFileURL(workOrderId: WorkOrderID, photoId: String) throws -> URL {
        let dir = try mediaDirectory(photosFolder)
            .appendingPathComponent(workOrderId.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(photoId).jpg", isDirectory: false)
    }

    @discardableResult
    static func savePhoto(
        data: Data,
        workOrderId: WorkOrderID,
        photoId: String
    ) throws -> URL {
        let url = try photoFileURL(workOrderId: workOrderId, photoId: photoId)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func loadPhoto(workOrderId: WorkOrderID, photoId: String) -> Data? {
        guard let url = try? photoFileURL(workOrderId: workOrderId, photoId: photoId),
              FileManager.default.fileExists(atPath: url.path)
        else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    static func signatureFileURL(workOrderId: WorkOrderID, signatureId: String) throws -> URL {
        let dir = try mediaDirectory(signaturesFolder)
            .appendingPathComponent(workOrderId.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(signatureId).png", isDirectory: false)
    }

    @discardableResult
    static func saveSignature(
        data: Data,
        workOrderId: WorkOrderID,
        signatureId: String
    ) throws -> URL {
        let url = try signatureFileURL(workOrderId: workOrderId, signatureId: signatureId)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func loadSignature(workOrderId: WorkOrderID, signatureId: String) -> Data? {
        guard let url = try? signatureFileURL(workOrderId: workOrderId, signatureId: signatureId),
              FileManager.default.fileExists(atPath: url.path)
        else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private static func mediaDirectory(_ folderName: String) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
