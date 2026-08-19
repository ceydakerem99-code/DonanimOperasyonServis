import Foundation

/// Captures signature metadata for a work order assigned to the acting
/// technician.
struct CaptureSignatureUseCase: Sendable {
    let workOrderRepository: WorkOrderRepository
    let signatureRepository: SignatureRepository

    init(
        workOrderRepository: WorkOrderRepository,
        signatureRepository: SignatureRepository
    ) {
        self.workOrderRepository = workOrderRepository
        self.signatureRepository = signatureRepository
    }

    @discardableResult
    func execute(
        actor: User,
        orderId: WorkOrderID,
        kind: SignatureKind,
        storagePath: String?,
        signerName: String? = nil,
        signatureId: String = UUID().uuidString,
        at now: Date = Date()
    ) async throws -> Signature {
        guard RoleAccessPolicy.can(.captureSignature, as: actor.role) else {
            throw DomainError.unauthorized(action: .captureSignature)
        }

        let order = try await workOrderRepository.fetch(id: orderId)
        guard RoleAccessPolicy.canAct(on: order, as: actor) else {
            throw order.isLocked
                ? DomainError.workOrderLocked(order.id)
                : DomainError.unauthorized(action: .captureSignature)
        }

        let signature = Signature(
            id: signatureId,
            workOrderId: order.id,
            kind: kind,
            storagePath: storagePath,
            signerName: signerName?.trimmingCharacters(in: .whitespacesAndNewlines),
            capturedByUserId: actor.id,
            capturedAt: now
        )
        try await signatureRepository.save(signature)
        return signature
    }
}
