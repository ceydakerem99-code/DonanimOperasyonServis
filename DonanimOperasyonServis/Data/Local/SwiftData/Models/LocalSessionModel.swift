import Foundation
import SwiftData

/// Single-row persistence entry that records which user is currently
/// signed in on this device. Backs `SwiftDataAuthRepository`.
///
/// The store is expected to contain at most one `LocalSessionModel`
/// instance. `currentUserId` is `nil` when no user is signed in.
@Model
final class LocalSessionModel {
    /// A stable, well-known primary key so the repository can look
    /// up "the" session row without scanning.
    @Attribute(.unique) var id: String

    var currentUserId: String?
    var updatedAt: Date

    init(id: String = LocalSessionModel.singletonId,
         currentUserId: String?,
         updatedAt: Date) {
        self.id = id
        self.currentUserId = currentUserId
        self.updatedAt = updatedAt
    }

    static let singletonId = "local-session"
}
