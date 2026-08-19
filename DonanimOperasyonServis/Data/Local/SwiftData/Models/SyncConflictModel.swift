import Foundation
import SwiftData

/// SwiftData persistence model for a detected `SyncConflict`.
///
/// Kept as its own table so conflict payloads are not stuffed into
/// `SyncOperationModel` as a JSON blob. `syncOperationId` is a
/// string foreign key (same convention as other Domain typed IDs).
@Model
final class SyncConflictModel {

    @Attribute(.unique) var id: String
    @Attribute(.unique) var syncOperationId: String

    var entityTypeRaw: String
    var entityId: String
    var localVersion: Int
    var remoteVersion: Int
    var localReference: String?
    var remoteReference: String?
    var detectedAt: Date
    var statusRaw: String

    init(
        id: String,
        syncOperationId: String,
        entityTypeRaw: String,
        entityId: String,
        localVersion: Int,
        remoteVersion: Int,
        localReference: String?,
        remoteReference: String?,
        detectedAt: Date,
        statusRaw: String
    ) {
        self.id = id
        self.syncOperationId = syncOperationId
        self.entityTypeRaw = entityTypeRaw
        self.entityId = entityId
        self.localVersion = localVersion
        self.remoteVersion = remoteVersion
        self.localReference = localReference
        self.remoteReference = remoteReference
        self.detectedAt = detectedAt
        self.statusRaw = statusRaw
    }
}

// MARK: - Domain ↔ Model mapping

extension SyncConflictModel {

    convenience init(domain: SyncConflict) {
        self.init(
            id: domain.id.rawValue,
            syncOperationId: domain.syncOperationId.rawValue,
            entityTypeRaw: domain.entityType.rawValue,
            entityId: domain.entityId,
            localVersion: domain.localVersion,
            remoteVersion: domain.remoteVersion,
            localReference: domain.localReference,
            remoteReference: domain.remoteReference,
            detectedAt: domain.detectedAt,
            statusRaw: domain.status.rawValue
        )
    }

    func apply(domain: SyncConflict) {
        self.syncOperationId = domain.syncOperationId.rawValue
        self.entityTypeRaw = domain.entityType.rawValue
        self.entityId = domain.entityId
        self.localVersion = domain.localVersion
        self.remoteVersion = domain.remoteVersion
        self.localReference = domain.localReference
        self.remoteReference = domain.remoteReference
        self.detectedAt = domain.detectedAt
        self.statusRaw = domain.status.rawValue
    }

    func toDomain() -> SyncConflict? {
        guard
            let entityType = SyncEntityType(rawValue: entityTypeRaw),
            let status = SyncConflictStatus(rawValue: statusRaw)
        else { return nil }

        return SyncConflict(
            id: SyncConflictID(id),
            syncOperationId: SyncOperationID(syncOperationId),
            entityType: entityType,
            entityId: entityId,
            localVersion: localVersion,
            remoteVersion: remoteVersion,
            localReference: localReference,
            remoteReference: remoteReference,
            detectedAt: detectedAt,
            status: status
        )
    }
}
