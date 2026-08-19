import Foundation

/// Rejects a pending `EditRequest`. Mirrors
/// `ApproveEditRequestUseCase` on the authorization side but does
/// not mutate the underlying work order.
struct RejectEditRequestUseCase: Sendable {
    let editRequestRepository: EditRequestRepository

    init(editRequestRepository: EditRequestRepository) {
        self.editRequestRepository = editRequestRepository
    }

    @discardableResult
    func execute(
        actor: User,
        requestId: EditRequestID,
        decisionNote: String? = nil,
        at now: Date = Date()
    ) async throws -> EditRequest {
        guard RoleAccessPolicy.can(.rejectEditRequest, as: actor.role) else {
            throw DomainError.unauthorized(action: .rejectEditRequest)
        }

        var request = try await editRequestRepository.fetch(id: requestId)

        guard RoleAccessPolicy.canReviewEditRequest(request, as: actor) else {
            if request.requestedByUserId == actor.id {
                throw DomainError.invalidEditRequest(reason: .selfReview)
            }
            throw DomainError.unauthorized(action: .rejectEditRequest)
        }

        _ = try EditRequestStateMachine.transition(from: request.status, to: .rejected)

        request.status = .rejected
        request.reviewedByUserId = actor.id
        request.reviewedAt = now
        request.decisionNote = decisionNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await editRequestRepository.save(request)

        return request
    }
}
