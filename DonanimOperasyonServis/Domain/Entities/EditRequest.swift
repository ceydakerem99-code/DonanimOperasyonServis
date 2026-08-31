import Foundation

/// A technician's request to change a single field on a completed
/// work order. Because completed work orders are locked from normal
/// state-machine mutations, an approved edit request is the only
/// path by which their fields can be modified.
///
/// Only users with role `.operator` may transition an edit request
/// to `.approved` or `.rejected` — the admin does not sit in the
/// operational review loop. See `RoleAccessPolicy`.
///
/// An edit request identifies:
/// - which field is being changed (`field`)
/// - the value the field held at request creation time
///   (`currentValue`), captured for audit
/// - the value the requester wants the field to hold
///   (`requestedValue`)
/// - who made the request (`requestedByUserId`) and who decided it
///   (`reviewedByUserId`)
struct EditRequest: Hashable, Sendable, Identifiable, Codable {
    let id: EditRequestID
    let workOrderId: WorkOrderID
    let requestedByUserId: UserID
    let createdAt: Date

    var reason: String
    /// The dotted name of the field being changed. See
    /// `EditableWorkOrderField` for the allowed set.
    var field: String
    var currentValue: String
    var requestedValue: String

    var status: EditRequestStatus
    var reviewedByUserId: UserID?
    var reviewedAt: Date?
    var decisionNote: String?

    init(
        id: EditRequestID,
        workOrderId: WorkOrderID,
        requestedByUserId: UserID,
        createdAt: Date,
        reason: String,
        field: String,
        currentValue: String,
        requestedValue: String,
        status: EditRequestStatus = .pending,
        reviewedByUserId: UserID? = nil,
        reviewedAt: Date? = nil,
        decisionNote: String? = nil
    ) {
        self.id = id
        self.workOrderId = workOrderId
        self.requestedByUserId = requestedByUserId
        self.createdAt = createdAt
        self.reason = reason
        self.field = field
        self.currentValue = currentValue
        self.requestedValue = requestedValue
        self.status = status
        self.reviewedByUserId = reviewedByUserId
        self.reviewedAt = reviewedAt
        self.decisionNote = decisionNote
    }
}

/// The whitelist of `WorkOrder` fields that may be targeted by an
/// `EditRequest`. Everything else (`id`, `status`, `createdAt`,
/// timestamps, participant IDs, …) is off-limits: those are either
/// immutable, controlled by the state machine, or would require a
/// separate authorization model.
enum EditableWorkOrderField: String, CaseIterable, Hashable, Sendable {
    case issueDescription
    case deviceBrand
    case deviceModel
    case serialNumber
    case scheduledDate
    case priority

    /// Canonical string snapshot stored on `EditRequest.currentValue` /
    /// `requestedValue` (and parsed by `ApproveEditRequestUseCase`).
    func value(on workOrder: WorkOrder) -> String {
        switch self {
        case .issueDescription:
            return workOrder.issueDescription ?? ""
        case .deviceBrand:
            return workOrder.deviceBrand
        case .deviceModel:
            return workOrder.deviceModel
        case .serialNumber:
            return workOrder.serialNumber
        case .scheduledDate:
            return String(workOrder.scheduledDate.timeIntervalSince1970)
        case .priority:
            return workOrder.priority.rawValue
        }
    }

    var displayName: String {
        switch self {
        case .issueDescription: return "Sorun Açıklaması"
        case .deviceBrand: return "Cihaz Markası"
        case .deviceModel: return "Cihaz Modeli"
        case .serialNumber: return "Seri Numarası"
        case .scheduledDate: return "Planlanan Tarih"
        case .priority: return "Öncelik"
        }
    }
}
