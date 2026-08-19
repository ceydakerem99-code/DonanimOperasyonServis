import Foundation

/// Decides whether a `SyncError` should be retried and, if so, when.
///
/// This type is a **calculation**. It does not sleep, schedule a
/// `Timer`, or talk to the network. Phase 5B/C owns the loop.
enum SyncRetryPolicy {

    /// After this many failed attempts the operation stays `.failed`.
    static let maximumRetryCount = 5

    /// Delay before the first retry (`retryCount == 0` after the
    /// initial failure). Subsequent delays double: 2s, 4s, 8s, …
    static let baseDelay: TimeInterval = 2

    static func isRetryable(_ error: SyncError) -> Bool {
        switch error {
        case .networkUnavailable, .serverError:
            return true
        case .unauthorized, .notFound, .invalidPayload, .conflict, .unknown:
            return false
        }
    }

    /// Exponential backoff for the upcoming retry. `retryCount` is
    /// the number of failures already recorded (0 after the first
    /// failure → first retry delay).
    static func delay(forRetryCount retryCount: Int) -> TimeInterval {
        let capped = max(0, retryCount)
        return baseDelay * pow(2.0, Double(capped))
    }

    static func shouldRetry(error: SyncError, retryCount: Int) -> Bool {
        guard isRetryable(error) else { return false }
        return retryCount < maximumRetryCount
    }

    /// `nil` when the error is not retryable or the cap is reached.
    static func nextRetryDate(
        error: SyncError,
        retryCount: Int,
        now: Date
    ) -> Date? {
        guard shouldRetry(error: error, retryCount: retryCount) else { return nil }
        return now.addingTimeInterval(delay(forRetryCount: retryCount))
    }
}
