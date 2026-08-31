import Foundation

/// Session-scoped eligibility for draining persisted queue rows.
///
/// The SwiftData queue is device-global; only rows owned by the
/// active Firebase Auth UID may be sent remotely during a drain.
enum SyncOperationUserScope {

    /// Rows with no resolvable actor (legacy customer creates) remain
    /// eligible for any authenticated session.
    static func isEligible(
        _ operation: SyncOperation,
        authUID: String?,
        local: SyncEntityRepositories
    ) async throws -> Bool {
        let sessionUID = authUID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !sessionUID.isEmpty else { return false }

        guard let actorUID = try await SyncOperationActorResolver.resolve(
            operation: operation,
            local: local
        ) else {
            return operation.entityType == .customer
        }
        return actorUID == sessionUID
    }

    static func filter(
        _ operations: [SyncOperation],
        authUID: String?,
        local: SyncEntityRepositories
    ) async throws -> [SyncOperation] {
        var eligible: [SyncOperation] = []
        for operation in operations {
            if try await isEligible(operation, authUID: authUID, local: local) {
                eligible.append(operation)
            }
        }
        return eligible
    }

    static func foreignOperationCount(
        in operations: [SyncOperation],
        authUID: String?,
        local: SyncEntityRepositories
    ) async throws -> Int {
        operations.count - (try await filter(operations, authUID: authUID, local: local)).count
    }
}
