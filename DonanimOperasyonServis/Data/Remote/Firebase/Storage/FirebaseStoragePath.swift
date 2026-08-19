import Foundation

/// Canonical Firebase Storage object paths used by the app.
///
/// Photo and signature bytes live in Storage; Firestore documents
/// only carry a `storagePath` string that matches one of these
/// cases. The layout is:
///
/// ```
/// workOrders/{workOrderId}/photos/{photoId}
/// workOrders/{workOrderId}/signatures/{signatureId}
/// ```
///
/// Repositories and UI must not invent their own path strings —
/// every Storage object is addressed through this enum so the
/// `storage.rules` file (and the future upload workflow) have a
/// single source of truth.
enum FirebaseStoragePath: Hashable, Sendable {
    case workOrderPhoto(workOrderId: String, photoId: String)
    case workOrderSignature(workOrderId: String, signatureId: String)

    /// The path as stored in Firebase Storage (no leading slash).
    var rawValue: String {
        switch self {
        case .workOrderPhoto(let workOrderId, let photoId):
            return "workOrders/\(workOrderId)/photos/\(photoId)"
        case .workOrderSignature(let workOrderId, let signatureId):
            return "workOrders/\(workOrderId)/signatures/\(signatureId)"
        }
    }

    static func photo(workOrderId: WorkOrderID, photoId: String) -> Self {
        .workOrderPhoto(workOrderId: workOrderId.rawValue, photoId: photoId)
    }

    static func signature(workOrderId: WorkOrderID, signatureId: String) -> Self {
        .workOrderSignature(workOrderId: workOrderId.rawValue, signatureId: signatureId)
    }
}
