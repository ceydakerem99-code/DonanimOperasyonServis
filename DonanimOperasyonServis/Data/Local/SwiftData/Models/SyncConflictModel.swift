import Foundation
import SwiftData

/// SwiftData persistence model for a detected `SyncConflict`.
///
/// Kept as its own table so conflict payloads are not stuffed into
/// `SyncOperationModel` as a JSON blob. `syncOperationId` is a
/// string foreign key (same convention as other Domain typed IDs).
///
/// Resolution metadata (`resolutionRaw`, `resolvedAt`,
/// `resolvedByUserId`) is optional so existing unresolved rows
/// lightweight-migrate without a status-enum expansion.
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
    var resolutionRaw: String?
    var resolvedAt: Date?
    var resolvedByUserId: String?

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
        statusRaw: String,
        resolutionRaw: String? = nil,
        resolvedAt: Date? = nil,
        resolvedByUserId: String? = nil
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
        self.resolutionRaw = resolutionRaw
        self.resolvedAt = resolvedAt
        self.resolvedByUserId = resolvedByUserId
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
            statusRaw: domain.status.rawValue,
            resolutionRaw: domain.resolution?.rawValue,
            resolvedAt: domain.resolvedAt,
            resolvedByUserId: domain.resolvedByUserId?.rawValue
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
        self.resolutionRaw = domain.resolution?.rawValue
        self.resolvedAt = domain.resolvedAt
        self.resolvedByUserId = domain.resolvedByUserId?.rawValue
    }

    func toDomain() -> SyncConflict? {
        guard
            let entityType = SyncEntityType(rawValue: entityTypeRaw),
            let status = SyncConflictStatus(rawValue: statusRaw)
        else { return nil }

        let resolution: SyncConflictResolutionChoice?
        if let resolutionRaw {
            guard let parsed = SyncConflictResolutionChoice(rawValue: resolutionRaw) else {
                return nil
            }
            resolution = parsed
        } else {
            resolution = nil
        }

        let actor: UserID?
        if let resolvedByUserId, !resolvedByUserId.isEmpty {
            actor = UserID(resolvedByUserId)
        } else {
            actor = nil
        }

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
            status: status,
            resolution: resolution,
            resolvedAt: resolvedAt,
            resolvedByUserId: actor
        )
    }
}
