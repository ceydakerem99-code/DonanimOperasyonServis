import Foundation

/// DEBUG / telemetry breakdown of the local sync queue.
enum SyncQueueDiagnostics {

    enum HoldReason: String, Sendable, Equatable {
        case actorMismatch
        case outstandingWorkOrderCreate
        case remoteParentMissing
        case remoteParentCompleted
        case technicianNotAssigned
        case dependencyBlocked
        case unresolvedConflict
        case unsatisfiedDependency
        case completionGPSWait
        case notApplicable
    }

    struct FailedBreakdown: Equatable, Sendable {
        var total: Int
        var unauthorized: Int
        var notFound: Int
        var dependencyBlocked: Int
        var networkOrRetryable: Int
        var other: Int
        var byEntityType: [SyncEntityType: Int]
    }

    struct QueueReport: Equatable, Sendable {
        let failedBreakdown: FailedBreakdown
        let holdReasonCounts: [HoldReason: Int]
        let pendingCount: Int
        let retryableFailedCount: Int
        let activeFailedCount: Int
    }

    /// Classifies a failed row from its stored `errorMessage` / retry metadata.
    static func failedCategory(of operation: SyncOperation) -> String {
        guard operation.status == .failed else { return "notFailed" }
        let message = operation.errorMessage ?? ""
        if message == SyncError.unauthorized.diagnosticMessage || message.hasPrefix("unauthorized") {
            return "unauthorized"
        }
        if message == SyncError.notFound.diagnosticMessage || message.hasPrefix("notFound") {
            return "notFound"
        }
        if message.hasPrefix("dependencyBlocked:") {
            return "dependencyBlocked"
        }
        if operation.nextRetryAt != nil
            || message == SyncError.networkUnavailable.diagnosticMessage
            || message.contains("networkUnavailable")
            || message == SyncError.serverError.diagnosticMessage
            || message.hasPrefix("serverError") {
            return "networkOrRetryable"
        }
        return "other"
    }

    static func failedBreakdown(_ operations: [SyncOperation]) -> FailedBreakdown {
        var unauthorized = 0
        var notFound = 0
        var dependencyBlocked = 0
        var networkOrRetryable = 0
        var other = 0
        var byEntity: [SyncEntityType: Int] = [:]

        for operation in operations where operation.status == .failed {
            byEntity[operation.entityType, default: 0] += 1
            switch failedCategory(of: operation) {
            case "unauthorized": unauthorized += 1
            case "notFound": notFound += 1
            case "dependencyBlocked": dependencyBlocked += 1
            case "networkOrRetryable": networkOrRetryable += 1
            default: other += 1
            }
        }

        return FailedBreakdown(
            total: operations.filter { $0.status == .failed }.count,
            unauthorized: unauthorized,
            notFound: notFound,
            dependencyBlocked: dependencyBlocked,
            networkOrRetryable: networkOrRetryable,
            other: other,
            byEntityType: byEntity
        )
    }

    static func makeReport(
        failed: [SyncOperation],
        pending: [SyncOperation],
        holdReasons: [SyncOperationID: HoldReason]
    ) -> QueueReport {
        let snapshot = SyncQueueIssueClassifier.snapshot(
            failed: failed,
            pending: pending,
            succeeded: [],
            conflicts: []
        )
        var holdCounts: [HoldReason: Int] = [:]
        for reason in holdReasons.values where reason != .notApplicable {
            holdCounts[reason, default: 0] += 1
        }
        return QueueReport(
            failedBreakdown: failedBreakdown(failed),
            holdReasonCounts: holdCounts,
            pendingCount: snapshot.pendingCount,
            retryableFailedCount: snapshot.retryableFailedCount,
            activeFailedCount: snapshot.activeFailedCount
        )
    }

    /// Single-line dump of queue fields needed for device diagnosis.
    static func operationDetailLine(_ operation: SyncOperation, holdReason: HoldReason? = nil) -> String {
        let parts: [String] = [
            "op=\(operation.id.rawValue)",
            "entityType=\(operation.entityType.rawValue)",
            "entityId=\(operation.entityId)",
            "operationType=\(operation.operationType.rawValue)",
            "status=\(operation.status.rawValue)",
            "errorMessage=\(operation.errorMessage ?? "-")",
            "retryCount=\(operation.retryCount)",
            "nextRetryAt=\(operation.nextRetryAt.map { "\($0.timeIntervalSince1970)" } ?? "nil")",
            "actorUserId=\(operation.actorUserId ?? "-")",
            "dependsOn=\(operation.dependsOnOperationId?.rawValue ?? "-")",
            "payloadReference=\(operation.payloadReference ?? "-")",
            "localVersion=\(operation.localVersion)",
            "category=\(operation.status == .failed ? failedCategory(of: operation) : "-")",
            "holdReason=\(holdReason?.rawValue ?? "-")"
        ]
        return parts.joined(separator: " ")
    }

    static func logSummary(_ report: QueueReport) {
        let failed = report.failedBreakdown
        AppLogger.sync.info(
            """
            SYNC QUEUE DIAG \
            failed=\(failed.total) \
            unauthorized=\(failed.unauthorized) \
            notFound=\(failed.notFound) \
            dependencyBlocked=\(failed.dependencyBlocked) \
            networkOrRetryable=\(failed.networkOrRetryable) \
            other=\(failed.other) \
            activeFailed=\(report.activeFailedCount) \
            retryableFailed=\(report.retryableFailedCount) \
            pending=\(report.pendingCount)
            """
        )
        if !failed.byEntityType.isEmpty {
            let entitySummary = failed.byEntityType
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.rawValue)=\($0.value)" }
                .joined(separator: ", ")
            AppLogger.sync.info("SYNC QUEUE DIAG byEntity: \(entitySummary, privacy: .public)")
        }
        if !report.holdReasonCounts.isEmpty {
            let holdSummary = HoldReason.allCases
                .compactMap { reason -> String? in
                    guard let count = report.holdReasonCounts[reason], count > 0 else { return nil }
                    return "\(reason.rawValue)=\(count)"
                }
                .joined(separator: ", ")
            AppLogger.sync.info("SYNC QUEUE DIAG heldReasons: \(holdSummary, privacy: .public)")
        }
    }
}

extension SyncQueueDiagnostics.HoldReason: CaseIterable {}
