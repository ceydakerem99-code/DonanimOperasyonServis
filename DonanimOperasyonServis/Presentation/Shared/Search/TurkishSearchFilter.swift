import Foundation

/// Case-insensitive, Turkish-locale aware local text matching for list filters.
enum TurkishSearchFilter {
    private static let locale = Locale(identifier: "tr_TR")

    static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
            .lowercased()
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "İ", with: "i")
    }

    static func matches(query: String, in haystacks: [String]) -> Bool {
        let needle = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return true }
        return haystacks.contains { normalize($0).contains(needle) }
    }
}
