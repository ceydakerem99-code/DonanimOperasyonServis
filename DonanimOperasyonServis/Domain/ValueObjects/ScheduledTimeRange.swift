import Foundation

/// A planned start/end window for a work order. Both endpoints are
/// full `Date` values so callers do not need a separate reference
/// date to interpret them. `end` must be strictly greater than
/// `start` — construct via `init(start:end:)` and use the returned
/// optional to enforce this at trust boundaries.
struct ScheduledTimeRange: Hashable, Sendable, Codable {
    let start: Date
    let end: Date

    /// Trusting initializer for callers that already validated the
    /// range (e.g. deserialization from persistence).
    init(uncheckedStart start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    /// Validating initializer. Returns `nil` when `end <= start`.
    init?(start: Date, end: Date) {
        guard end > start else { return nil }
        self.start = start
        self.end = end
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}
