import Foundation

/// Outcome of comparing one local entity against its remote counterpart.
///
/// This is a **decision**, not a UI action and not a conflict
/// resolution. `ConflictResolver` (later) is what may turn
/// `.conflict` into `useLocal` / `useRemote`.
enum ReconciliationResult: String, CaseIterable, Hashable, Sendable, Codable {
    /// Local and remote represent the same state. Do not rewrite local.
    case noChange
    /// Remote is ahead and local has no pending mutation. Safe to pull.
    case applyRemote
    /// Local has a mutation (or is the source of truth) and remote is
    /// not newer. Keep the SwiftData row; do not overwrite it.
    case keepLocal
    /// Both sides changed, versions are indeterminate, or a completed
    /// work-order rule forbids automatic merge.
    case conflict
}

extension ReconciliationResult {
    var displayName: String {
        switch self {
        case .noChange:    return "Değişiklik Yok"
        case .applyRemote: return "Sunucu Verisini Kullan"
        case .keepLocal:   return "Yerel Veriyi Koru"
        case .conflict:    return "Çakışma"
        }
    }
}
