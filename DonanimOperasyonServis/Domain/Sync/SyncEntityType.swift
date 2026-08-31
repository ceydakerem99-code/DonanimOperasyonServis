import Foundation

/// Domain types that may be enqueued for remote synchronization.
///
/// `SyncOperation` itself is **not** a member of this set — the
/// queue is local metadata and must never be synced recursively.
enum SyncEntityType: String, CaseIterable, Hashable, Sendable, Codable {
    case user
    case customer
    case workOrder
    case workOrderNote
    case workOrderStatusHistory
    case workOrderPhoto
    case workOrderLocation
    case signature
    case editRequest
    case notification
    case customerSatisfaction
}
