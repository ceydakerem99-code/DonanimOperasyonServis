import Foundation

/// Maps a thrown `DomainError` (or `SyncConflictDetected`) onto
/// `SyncError`. `FirebaseError` is not part of this surface —
/// remote repositories already translate it.
enum SyncErrorMapping {

    static func from(_ error: Error) -> SyncError {
        if let sync = error as? SyncError { return sync }
        if error is SyncConflictDetected { return .conflict }

        guard let domain = error as? DomainError else {
            return .unknown(reason: String(describing: error))
        }

        switch domain {
        case .unauthorized:
            return .unauthorized
        case .authenticationFailed:
            return .unauthorized
        case .notFound:
            return .notFound
        case .invalidData,
             .invalidStateTransition,
             .invalidEditRequestTransition,
             .invalidCustomerSatisfactionTransition,
             .invalidEditRequest,
             .invalidCustomerSatisfaction,
             .incompleteWorkOrder,
             .workOrderLocked,
             .invalidSyncStatusTransition:
            return .invalidPayload
        case .infrastructure(let underlying):
            return mapInfrastructure(underlying)
        }
    }

    private static func mapInfrastructure(_ underlying: String) -> SyncError {
        if underlying.contains("networkUnavailable") { return .networkUnavailable }
        if underlying.contains("permissionDenied") { return .unauthorized }
        if underlying.contains("localMediaMissing") { return .invalidPayload }
        if underlying.contains("serverError") { return .serverError }
        if underlying.contains("notConfigured") { return .serverError }
        if underlying.contains("storageError") { return .serverError }
        if underlying.contains("encodingFailed") || underlying.contains("decodingFailed") {
            return .invalidPayload
        }
        if underlying.contains("unknown") {
            return .unknown(reason: underlying)
        }
        return .unknown(reason: underlying)
    }
}
