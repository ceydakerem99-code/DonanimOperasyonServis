import Foundation

/// A lightweight wrapper around a phone number string. The domain
/// layer intentionally does not perform locale-aware validation or
/// formatting — that is a Presentation concern. What this type
/// guarantees is:
///
/// - `rawValue` retains whatever the caller provided (for display
///   round-trips).
/// - `normalized` strips whitespace and common separators so that
///   two phone numbers written differently compare equal for
///   deduplication purposes.
struct PhoneNumber: Hashable, Sendable, Codable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// A stripped-down version suitable for equality comparisons
    /// and storage keys. Preserves a leading `+`.
    var normalized: String {
        let allowed = Set("0123456789+")
        let filtered = rawValue.filter { allowed.contains($0) }
        // Only keep a leading '+' if present, drop any others.
        guard let first = filtered.first else { return "" }
        if first == "+" {
            let rest = filtered.dropFirst().filter { $0 != "+" }
            return "+" + rest
        }
        return filtered.filter { $0 != "+" }
    }

    /// Very loose sanity check: at least a handful of digits.
    var isPlausible: Bool {
        normalized.filter(\.isNumber).count >= 7
    }
}

extension PhoneNumber: CustomStringConvertible {
    var description: String { rawValue }
}
