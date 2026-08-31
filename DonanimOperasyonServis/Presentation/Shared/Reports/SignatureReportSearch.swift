import Foundation

enum SignatureReportSearch {
    static func filter(_ entries: [SignatureReportEntry], query: String) -> [SignatureReportEntry] {
        ReportSearchFilters.filterSignatures(entries, query: query)
    }
}
