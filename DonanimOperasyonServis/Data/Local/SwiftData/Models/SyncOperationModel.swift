import Foundation
import SwiftData

/// SwiftData persistence model for the local sync queue.
///
/// Separate from the Domain `SyncOperation` value — Domain stays
/// free of `@Model`. Typed IDs and enums are stored as raw strings
/// / ints; `toDomain()` refuses unknown raw values rather than
/// substituting a default.
@Model
final class SyncOperationModel {

    @Attribute(.unique) var id: String
    @Attribute(.unique) var idempotencyKey: String

    var entityTypeRaw: String
    var entityId: String
    var operationTypeRaw: String
    var payloadReference: String?

    var createdAt: Date
    var updatedAt: Date

    var retryCount: Int
    var lastAttemptAt: Date?
    var nextRetryAt: Date?

    var statusRaw: String
    var errorMessage: String?

    var localVersion: Int
    var remoteVersion: Int

    init(
        id: String,
        entityTypeRaw: String,
        entityId: String,
        operationTypeRaw: String,
        payloadReference: String?,
        createdAt: Date,
        updatedAt: Date,
        retryCount: Int,
        lastAttemptAt: Date?,
        nextRetryAt: Date?,
        statusRaw: String,
        errorMessage: String?,
        localVersion: Int,
        remoteVersion: Int,
        idempotencyKey: String
    ) {
        self.id = id
        self.entityTypeRaw = entityTypeRaw
        self.entityId = entityId
        self.operationTypeRaw = operationTypeRaw
        self.payloadReference = payloadReference
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.retryCount = retryCount
        self.lastAttemptAt = lastAttemptAt
        self.nextRetryAt = nextRetryAt
        self.statusRaw = statusRaw
        self.errorMessage = errorMessage
        self.localVersion = localVersion
        self.remoteVersion = remoteVersion
        self.idempotencyKey = idempotencyKey
    }
}

// MARK: - Domain ↔ Model mapping

extension SyncOperationModel {

    convenience init(domain: SyncOperation) {
        self.init(
            id: domain.id.rawValue,
            entityTypeRaw: domain.entityType.rawValue,
            entityId: domain.entityId,
            operationTypeRaw: domain.operationType.rawValue,
            payloadReference: domain.payloadReference,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt,
            retryCount: domain.retryCount,
            lastAttemptAt: domain.lastAttemptAt,
            nextRetryAt: domain.nextRetryAt,
            statusRaw: domain.status.rawValue,
            errorMessage: domain.errorMessage,
            localVersion: domain.localVersion,
            remoteVersion: domain.remoteVersion,
            idempotencyKey: domain.idempotencyKey.rawValue
        )
    }

    func apply(domain: SyncOperation) {
        self.entityTypeRaw = domain.entityType.rawValue
        self.entityId = domain.entityId
        self.operationTypeRaw = domain.operationType.rawValue
        self.payloadReference = domain.payloadReference
        self.createdAt = domain.createdAt
        self.updatedAt = domain.updatedAt
        self.retryCount = domain.retryCount
        self.lastAttemptAt = domain.lastAttemptAt
        self.nextRetryAt = domain.nextRetryAt
        self.statusRaw = domain.status.rawValue
        self.errorMessage = domain.errorMessage
        self.localVersion = domain.localVersion
        self.remoteVersion = domain.remoteVersion
        self.idempotencyKey = domain.idempotencyKey.rawValue
    }

    /// Reconstructs the Domain value. Returns `nil` when any persisted
    /// enum raw value is unknown — callers must surface
    /// `DomainError.invalidData` rather than picking a default.
    func toDomain() -> SyncOperation? {
        guard
            let entityType = SyncEntityType(rawValue: entityTypeRaw),
            let operationType = SyncOperationType(rawValue: operationTypeRaw),
            let status = SyncStatus(rawValue: statusRaw)
        else { return nil }

        return SyncOperation(
            id: SyncOperationID(id),
            entityType: entityType,
            entityId: entityId,
            operationType: operationType,
            payloadReference: payloadReference,
            createdAt: createdAt,
            updatedAt: updatedAt,
            retryCount: retryCount,
            lastAttemptAt: lastAttemptAt,
            nextRetryAt: nextRetryAt,
            status: status,
            errorMessage: errorMessage,
            localVersion: localVersion,
            remoteVersion: remoteVersion,
            idempotencyKey: SyncIdempotencyKey(idempotencyKey)
        )
    }
}
