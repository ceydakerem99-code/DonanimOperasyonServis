import Foundation

/// The exhaustive enumeration of business actions that
/// `RoleAccessPolicy` authorizes. Every use case that performs a
/// privileged action first asks the policy `can(_:as:)` and throws
/// `DomainError.unauthorized(action:)` on refusal.
///
/// The enum is grouped by the role that owns the action in v1:
///
/// - `admin*` — organizational / configuration surface
/// - `operator*` — operational surface (create, assign, review)
/// - `technician*` — field-work surface (execute, evidence)
///
/// New actions should be added here first, then wired into the
/// permission table in `RoleAccessPolicy`.
enum DomainAction: Hashable, Sendable {
    // MARK: Admin
    case manageUsers
    case viewRolesMatrix
    case manageSystemConfiguration
    case viewSystemReports

    // MARK: Operator
    case createWorkOrder
    case createCustomer
    case assignWorkOrder
    case viewAllWorkOrders
    case viewServiceReport
    case approveEditRequest
    case rejectEditRequest
    case resolveSyncConflict

    // MARK: Technician
    case viewOwnAssignedWorkOrders
    case acceptWorkOrder
    case startTravelToCustomer
    case markArrivedAtCustomer
    case startServiceWork
    case pauseServiceWork
    case resumeServiceWork
    case addWorkOrderNote
    case addWorkOrderPhoto
    case captureLocationSample
    case captureSignature
    case completeWorkOrder
    case createEditRequest
}
