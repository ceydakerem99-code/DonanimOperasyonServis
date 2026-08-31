import Foundation

/// The single error type produced by the Domain layer. Any Data or
/// Infrastructure error is expected to be mapped into a
/// `DomainError` (or a `.infrastructure` case) before it crosses
/// back into the Domain / Presentation boundary.
///
/// Error cases are deliberately code-first (no user-facing strings)
/// so that the Presentation layer owns Turkish localization and
/// the Domain layer stays framework-agnostic.
enum DomainError: Error, Hashable, Sendable {
    /// A `WorkOrder` state machine transition from `from` to `to`
    /// is not allowed. Also thrown when trying to leave `.completed`.
    case invalidStateTransition(from: WorkOrderStatus, to: WorkOrderStatus)

    /// An `EditRequest` state machine transition from `from` to `to`
    /// is not allowed (typically because the request has already been
    /// decided).
    case invalidEditRequestTransition(from: EditRequestStatus, to: EditRequestStatus)

    /// A `CustomerSatisfaction` state machine transition from `from`
    /// to `to` is not allowed (typically because the survey has
    /// already been submitted or expired).
    case invalidCustomerSatisfactionTransition(
        from: CustomerSatisfactionStatus,
        to: CustomerSatisfactionStatus
    )

    /// The acting user does not have the role, or does not own the
    /// resource, required for this action. Carries the offending
    /// action for logging / analytics.
    case unauthorized(action: DomainAction)

    /// A caller attempted to mutate a completed work order via a
    /// normal write path. Only approved edit requests may modify
    /// specific fields of a completed order.
    case workOrderLocked(WorkOrderID)

    /// The completion checklist has one or more gaps. The associated
    /// value lists each gap so the UI can present them individually.
    case incompleteWorkOrder([MissingRequirement])

    /// The edit request payload is malformed (e.g. `currentValue`
    /// equals `requestedValue`, or the field is not editable).
    case invalidEditRequest(reason: InvalidEditRequestReason)

    /// The customer satisfaction payload or lifecycle precondition
    /// is invalid (e.g. work order not completed, survey not pending).
    case invalidCustomerSatisfaction(reason: InvalidCustomerSatisfactionReason)

    /// A referenced entity could not be found.
    case notFound(entity: String, id: String)

    /// Firebase Authentication or session bootstrap failed before an
    /// application session could be established. Distinct from
    /// `.unauthorized(action:)` which covers RBAC after login.
    case authenticationFailed(AuthenticationFailureReason)

    /// A generic domain validation error (empty required field,
    /// pause without a reason, etc.).
    case invalidData(reason: String)

    /// Escape hatch for lower-layer (Data / Infrastructure) errors
    /// that reach the Domain surface unchanged. Use sparingly.
    case infrastructure(underlying: String)

    /// A `SyncOperation` status transition from `from` to `to` is
    /// not allowed by `SyncStatusStateMachine`.
    case invalidSyncStatusTransition(from: SyncStatus, to: SyncStatus)
}

extension DomainError {
    /// Subcases explaining why sign-in or session restore failed.
    enum AuthenticationFailureReason: String, Hashable, Sendable {
        case invalidCredentials
        case userNotFound
        case networkUnavailable
        case tooManyRequests
        case unauthorized
        case userDocumentMissing
        /// Firebase Auth could not read/write the Keychain (often
        /// unsigned simulator builds / missing code signing).
        case keychainUnavailable
        case weakPassword
        case passwordsDoNotMatch
        case sameAsCurrentPassword
        case sessionInvalid
        case requiresRecentLogin
        case unknown
    }

    /// Subcases explaining why an `EditRequest` payload was rejected.
    enum InvalidEditRequestReason: String, Hashable, Sendable {
        /// `currentValue` matches `requestedValue`.
        case noChange
        /// The named field is not permitted to be edited via
        /// `EditRequest` (e.g. `id`, `status`).
        case fieldNotEditable
        /// The reviewer is trying to decide their own request.
        case selfReview
        /// The target work order is not in `.completed` state.
        case workOrderNotCompleted
    }

    /// Subcases explaining why a `CustomerSatisfaction` mutation was
    /// rejected.
    enum InvalidCustomerSatisfactionReason: String, Hashable, Sendable {
        /// The target work order is not in `.completed` state.
        case workOrderNotCompleted
        /// A `.pending` survey already exists for this work order.
        case pendingAlreadyExists
        /// The survey is not in `.pending` state.
        case notPending
    }
}
