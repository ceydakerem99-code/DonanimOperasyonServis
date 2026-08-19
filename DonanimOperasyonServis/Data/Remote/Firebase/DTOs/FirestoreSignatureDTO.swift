import Foundation

/// Firestore DTO for the `signatures` collection.
///
/// Only signature metadata is here; the drawn image bytes live in
/// Firebase Storage under
/// `workOrders/{workOrderId}/signatures/{signatureId}`.
struct FirestoreSignatureDTO: Codable, Hashable, Sendable {
    let id: String
    let workOrderId: String
    let kind: String
    let storagePath: String?
    let signerName: String?
    let capturedByUserId: String
    let capturedAt: Date
}

extension FirestoreSignatureDTO {

    init(domain: Signature) {
        self.id = domain.id
        self.workOrderId = domain.workOrderId.rawValue
        self.kind = domain.kind.rawValue
        self.storagePath = domain.storagePath
        self.signerName = domain.signerName
        self.capturedByUserId = domain.capturedByUserId.rawValue
        self.capturedAt = domain.capturedAt
    }

    func toDomain() -> Signature? {
        guard let resolvedKind = SignatureKind(rawValue: kind) else { return nil }
        return Signature(
            id: id,
            workOrderId: WorkOrderID(workOrderId),
            kind: resolvedKind,
            storagePath: storagePath,
            signerName: signerName,
            capturedByUserId: UserID(capturedByUserId),
            capturedAt: capturedAt
        )
    }
}
