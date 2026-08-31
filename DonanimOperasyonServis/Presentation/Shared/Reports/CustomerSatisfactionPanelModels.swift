import Foundation

struct CustomerSatisfactionSummary: Equatable, Sendable {
    let averageRating: Double?
    let submittedCount: Int
    let pendingCount: Int
    let expiredCount: Int
    let totalCount: Int
    let ratingDistribution: [CustomerSatisfactionRating: Int]

    var averageRatingLabel: String {
        guard let averageRating else { return "—" }
        return String(format: "%.1f", averageRating)
    }
}

struct CustomerSatisfactionRatingBar: Identifiable, Equatable, Sendable {
    let rating: CustomerSatisfactionRating
    let count: Int

    var id: Int { rating.rawValue }
    var label: String { "\(rating.rawValue)" }
}

struct CustomerSatisfactionEntry: Identifiable, Equatable, Sendable {
    let id: CustomerSatisfactionID
    let satisfaction: CustomerSatisfaction
    let workOrderId: WorkOrderID
    let workOrderNumber: String
    let customerName: String
    let technicianName: String
    let workTypeLabel: String
    let scheduledDate: Date?
    let sortDate: Date

    var statusLabel: String { satisfaction.status.displayName }

    var ratingLabel: String? {
        guard let rating = satisfaction.rating else { return nil }
        return "\(rating.displayName) / 5"
    }

    var commentText: String? {
        guard satisfaction.status == .submitted else { return nil }
        return satisfaction.comment
    }
}

struct CustomerSatisfactionTechnicianSummary: Identifiable, Equatable, Sendable {
    let id: UserID
    let name: String
    let averageRating: Double
    let submittedCount: Int
    let fiveStarRatio: Double

    var averageRatingLabel: String {
        String(format: "%.1f", averageRating)
    }

    var fiveStarRatioLabel: String {
        String(format: "%.0f%%", fiveStarRatio)
    }
}
