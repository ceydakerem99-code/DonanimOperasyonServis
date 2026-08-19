import Foundation

/// Approves a pending `EditRequest` and applies its change to the
/// target work order.
///
/// Authorization:
/// - Only operators may approve edit requests (admin cannot).
/// - The reviewer must not be the requester.
///
/// Effects:
/// - The edit request transitions to `.approved`, stamping
///   `reviewedByUserId`, `reviewedAt`, and optionally
///   `decisionNote`.
/// - The single targeted `EditableWorkOrderField` on the work order
///   is mutated to `requestedValue`. **No other fields are
///   changed**, and the work order's `.completed` status is
///   preserved — approving an edit request never re-opens the work
///   order.
///
/// Any parse failure while applying the value surfaces as
/// `DomainError.invalidEditRequest(reason: .fieldNotEditable)` or
/// `.invalidData` so the operator can decide whether to reject and
/// ask for a corrected request.
struct ApproveEditRequestUseCase: Sendable {
    let editRequestRepository: EditRequestRepository
    let workOrderRepository: WorkOrderRepository

    init(
        editRequestRepository: EditRequestRepository,
        workOrderRepository: WorkOrderRepository
    ) {
        self.editRequestRepository = editRequestRepository
        self.workOrderRepository = workOrderRepository
    }

    @discardableResult
    func execute(
        actor: User,
        requestId: EditRequestID,
        decisionNote: String? = nil,
        at now: Date = Date()
    ) async throws -> EditRequest {
        guard RoleAccessPolicy.can(.approveEditRequest, as: actor.role) else {
            throw DomainError.unauthorized(action: .approveEditRequest)
        }

        var request = try await editRequestRepository.fetch(id: requestId)

        guard RoleAccessPolicy.canReviewEditRequest(request, as: actor) else {
            if request.requestedByUserId == actor.id {
                throw DomainError.invalidEditRequest(reason: .selfReview)
            }
            throw DomainError.unauthorized(action: .approveEditRequest)
        }

        // State-machine transition (throws if not currently pending).
        _ = try EditRequestStateMachine.transition(from: request.status, to: .approved)

        // Apply the change to the target work order. Only whitelisted
        // fields are editable via this path.
        guard let field = EditableWorkOrderField(rawValue: request.field) else {
            throw DomainError.invalidEditRequest(reason: .fieldNotEditable)
        }

        var workOrder = try await workOrderRepository.fetch(id: request.workOrderId)
        try Self.apply(
            value: request.requestedValue,
            to: field,
            on: &workOrder
        )
        workOrder.updatedAt = now
        try await workOrderRepository.save(workOrder)

        request.status = .approved
        request.reviewedByUserId = actor.id
        request.reviewedAt = now
        request.decisionNote = decisionNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await editRequestRepository.save(request)

        return request
    }

    /// Applies `value` to `field` on `workOrder`. Kept static so
    /// tests can exercise the parser directly without spinning up a
    /// full use-case invocation.
    static func apply(
        value: String,
        to field: EditableWorkOrderField,
        on workOrder: inout WorkOrder
    ) throws {
        switch field {
        case .issueDescription:
            workOrder.issueDescription = value
        case .deviceBrand:
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                throw DomainError.invalidData(reason: "workOrder.deviceBrandEmpty")
            }
            workOrder.deviceBrand = trimmed
        case .deviceModel:
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                throw DomainError.invalidData(reason: "workOrder.deviceModelEmpty")
            }
            workOrder.deviceModel = trimmed
        case .serialNumber:
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                throw DomainError.invalidData(reason: "workOrder.serialNumberEmpty")
            }
            workOrder.serialNumber = trimmed
        case .scheduledDate:
            guard let interval = TimeInterval(value) else {
                throw DomainError.invalidData(reason: "workOrder.scheduledDateInvalid")
            }
            workOrder.scheduledDate = Date(timeIntervalSince1970: interval)
        case .priority:
            guard let parsed = WorkOrderPriority(rawValue: value) else {
                throw DomainError.invalidData(reason: "workOrder.priorityInvalid")
            }
            workOrder.priority = parsed
        }
    }
}
