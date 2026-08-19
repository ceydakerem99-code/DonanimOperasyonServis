import Foundation

/// A captured signature (technician or customer) for a work order.
/// As with `WorkOrderPhoto`, the binary/image content lives in
/// storage — this entity holds only the metadata plus a locator.
struct Signature: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let workOrderId: WorkOrderID
    let kind: SignatureKind
    /// Storage locator; may be `nil` while a locally-captured
    /// signature image is queued for upload.
    var storagePath: String?
    /// Optional printed name of the signer (typically only used for
    /// customer signatures).
    var signerName: String?
    let capturedByUserId: UserID
    let capturedAt: Date

    init(
        id: String,
        workOrderId: WorkOrderID,
        kind: SignatureKind,
        storagePath: String? = nil,
        signerName: String? = nil,
        capturedByUserId: UserID,
        capturedAt: Date
    ) {
        self.id = id
        self.workOrderId = workOrderId
        self.kind = kind
        self.storagePath = storagePath
        self.signerName = signerName
        self.capturedByUserId = capturedByUserId
        self.capturedAt = capturedAt
    }
}
