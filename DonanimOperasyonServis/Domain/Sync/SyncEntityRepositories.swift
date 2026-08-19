import Foundation

/// The ten syncable entity repositories, bundled so `SyncManager`
/// can be constructed without a 20-parameter initializer. Local and
/// remote sides use the same Domain protocols; the local side is
/// SwiftData, the remote side is Firebase.
struct SyncEntityRepositories: Sendable {
    var users: any UserRepository
    var customers: any CustomerRepository
    var workOrders: any WorkOrderRepository
    var notes: any WorkOrderNoteRepository
    var photos: any WorkOrderPhotoRepository
    var locations: any WorkOrderLocationRepository
    var statusHistory: any WorkOrderStatusHistoryRepository
    var signatures: any SignatureRepository
    var editRequests: any EditRequestRepository
    var notifications: any NotificationRepository
}
