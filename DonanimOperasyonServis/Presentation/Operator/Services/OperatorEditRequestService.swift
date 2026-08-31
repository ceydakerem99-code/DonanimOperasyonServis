import Foundation

/// Operator edit-request review mutations with offline-first sync enqueue.
struct OperatorEditRequestService: Sendable {
    let approveEditRequest: ApproveEditRequestUseCase
    let rejectEditRequest: RejectEditRequestUseCase
    let syncOperationRepository: SyncOperationRepository

    @discardableResult
    func approveWithSync(
        actor: User,
        requestId: EditRequestID,
        decisionNote: String? = nil,
        at now: Date = Date()
    ) async throws -> EditRequest {
        let request = try await approveEditRequest.execute(
            actor: actor,
            requestId: requestId,
            decisionNote: decisionNote,
            at: now
        )
        try await AdminSyncEnqueue.enqueueUpdate(
            entityType: .editRequest,
            entityId: request.id.rawValue,
            queue: syncOperationRepository,
            now: now,
            actorUserId: actor.id.rawValue
        )
        return request
    }

    @discardableResult
    func rejectWithSync(
        actor: User,
        requestId: EditRequestID,
        decisionNote: String? = nil,
        at now: Date = Date()
    ) async throws -> EditRequest {
        let request = try await rejectEditRequest.execute(
            actor: actor,
            requestId: requestId,
            decisionNote: decisionNote,
            at: now
        )
        try await AdminSyncEnqueue.enqueueUpdate(
            entityType: .editRequest,
            entityId: request.id.rawValue,
            queue: syncOperationRepository,
            now: now,
            actorUserId: actor.id.rawValue
        )
        return request
    }
}
