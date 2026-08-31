import Foundation

/// Pure, static role-based access control matrix.
///
/// This is the single source of truth for who can do what in v1.
/// It is code-first and read-only: there is no admin UI for editing
/// role permissions at runtime. Changing permissions requires a
/// code change, a new build, and (for the server side) a matching
/// change to Firestore Security Rules in a later phase.
///
/// The policy is intentionally split into two surfaces:
///
/// 1. `can(_:as:)` — a role-only check. Answers "does this role
///    ever have permission to perform this action?"
/// 2. Contextual helpers (`canAct(on:as:)`,
///    `canRequestEdit(on:as:)`, `canReviewEditRequest(_:as:)`) —
///    answer role + resource-scoped questions such as "may this
///    specific technician act on this specific work order?"
enum RoleAccessPolicy {

    // MARK: - Role-only matrix

    /// The exhaustive permission table. Each key is a role; each
    /// value is the set of actions that role may perform under
    /// *some* context. Fine-grained resource checks (assigned
    /// technician, ownership, etc.) live in the contextual helpers
    /// below.
    static let permissions: [UserRole: Set<DomainAction>] = [

        .admin: [
            .manageUsers,
            .viewRolesMatrix,
            .manageSystemConfiguration,
            .viewSystemReports,
            .viewServiceReport,
            .deleteWorkOrder
            // NOTE: admin intentionally CANNOT approve or reject
            // edit requests, and CANNOT execute field work.
        ],

        .operator: [
            .createWorkOrder,
            .createCustomer,
            .updateCustomer,
            .assignWorkOrder,
            .viewAllWorkOrders,
            .viewServiceReport,
            .viewSystemReports,
            .approveEditRequest,
            .rejectEditRequest,
            .resolveSyncConflict,
            .createCustomerSatisfaction
        ],

        .technician: [
            .viewOwnAssignedWorkOrders,
            .viewServiceReport,
            .acceptWorkOrder,
            .startTravelToCustomer,
            .markArrivedAtCustomer,
            .startServiceWork,
            .pauseServiceWork,
            .resumeServiceWork,
            .addWorkOrderNote,
            .addWorkOrderPhoto,
            .captureLocationSample,
            .captureSignature,
            .completeWorkOrder,
            .createEditRequest
        ]
    ]

    /// Role-only permission check. Prefer the contextual helpers
    /// below when a resource is in scope.
    static func can(_ action: DomainAction, as role: UserRole) -> Bool {
        permissions[role]?.contains(action) ?? false
    }

    // MARK: - Contextual checks

    /// Whether `user` may perform an operational status transition
    /// or evidence-capture action against `workOrder`.
    ///
    /// Rules:
    /// - Technicians may act only on work orders assigned to them,
    ///   and never on a `.completed` (locked) work order.
    /// - Operators and admins do not execute field work through
    ///   this surface; their permissions live in `can(_:as:)`.
    static func canAct(on workOrder: WorkOrder, as user: User) -> Bool {
        guard user.role == .technician else { return false }
        guard workOrder.assignedTechnicianId == user.id else { return false }
        guard !workOrder.isLocked else { return false }
        return true
    }

    /// Whether `user` may open an `EditRequest` against
    /// `workOrder`. Only the assigned technician of a
    /// **completed** work order may file one.
    static func canRequestEdit(on workOrder: WorkOrder, as user: User) -> Bool {
        guard user.role == .technician else { return false }
        guard workOrder.assignedTechnicianId == user.id else { return false }
        guard workOrder.isLocked else { return false }
        return true
    }

    /// Whether `user` may approve or reject a specific
    /// `EditRequest`.
    ///
    /// Rules:
    /// - Only operators can review edit requests. Admin cannot.
    /// - The reviewer must not be the requester (`selfReview`
    ///   is blocked here as well as by `DomainError.invalidEditRequest`).
    static func canReviewEditRequest(_ request: EditRequest, as user: User) -> Bool {
        guard user.role == .operator else { return false }
        guard request.requestedByUserId != user.id else { return false }
        return true
    }

    /// Whether `user` may open a pending `CustomerSatisfaction`
    /// survey for `workOrder`. Only operators may create surveys for
    /// **completed** work orders.
    static func canCreateCustomerSatisfaction(on workOrder: WorkOrder, as user: User) -> Bool {
        guard user.role == .operator else { return false }
        guard workOrder.isLocked else { return false }
        return true
    }
}
