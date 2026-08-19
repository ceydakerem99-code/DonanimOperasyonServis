import Foundation

/// Mutation kind carried by a `SyncOperation`. Hard vs soft delete
/// is not modelled; `delete` means "remove this entity from remote".
enum SyncOperationType: String, CaseIterable, Hashable, Sendable, Codable {
    case create
    case update
    case delete
}
