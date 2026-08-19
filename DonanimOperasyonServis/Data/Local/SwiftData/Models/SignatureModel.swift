import Foundation
import SwiftData

/// SwiftData persistence model for `Signature`. As with photos, the
/// signature image bytes live in a separate storage subsystem —
/// this row only carries metadata plus a locator.
@Model
final class SignatureModel {

    @Attribute(.unique) var id: String

    var workOrder: WorkOrderModel?
    var workOrderId: String

    var kindRaw: String
    var storagePath: String?
    var signerName: String?
    var capturedByUserId: String
    var capturedAt: Date

    init(
        id: String,
        workOrderId: String,
        kindRaw: String,
        storagePath: String?,
        signerName: String?,
        capturedByUserId: String,
        capturedAt: Date
    ) {
        self.id = id
        self.workOrderId = workOrderId
        self.kindRaw = kindRaw
        self.storagePath = storagePath
        self.signerName = signerName
        self.capturedByUserId = capturedByUserId
        self.capturedAt = capturedAt
    }
}

extension SignatureModel {

    convenience init(domain: Signature) {
        self.init(
            id: domain.id,
            workOrderId: domain.workOrderId.rawValue,
            kindRaw: domain.kind.rawValue,
            storagePath: domain.storagePath,
            signerName: domain.signerName,
            capturedByUserId: domain.capturedByUserId.rawValue,
            capturedAt: domain.capturedAt
        )
    }

    func apply(domain: Signature) {
        self.workOrderId = domain.workOrderId.rawValue
        self.kindRaw = domain.kind.rawValue
        self.storagePath = domain.storagePath
        self.signerName = domain.signerName
        self.capturedByUserId = domain.capturedByUserId.rawValue
        self.capturedAt = domain.capturedAt
    }

    func toDomain() -> Signature? {
        guard let kind = SignatureKind(rawValue: kindRaw) else { return nil }
        return Signature(
            id: id,
            workOrderId: WorkOrderID(workOrderId),
            kind: kind,
            storagePath: storagePath,
            signerName: signerName,
            capturedByUserId: UserID(capturedByUserId),
            capturedAt: capturedAt
        )
    }
}
