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

struct CustomerSatisfactionStructuredComment: Equatable, Sendable {
    let serviceQualityRating: Int?
    let staffCareRating: Int?
    let resolutionSpeedRating: Int?
    let experienceTags: [String]
    let freeformComment: String?

    static func parse(from rawComment: String?) -> CustomerSatisfactionStructuredComment {
        guard let rawComment,
              !rawComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return CustomerSatisfactionStructuredComment(
                serviceQualityRating: nil,
                staffCareRating: nil,
                resolutionSpeedRating: nil,
                experienceTags: [],
                freeformComment: nil
            )
        }

        var serviceQuality: Int?
        var staffCare: Int?
        var resolutionSpeed: Int?
        var experienceTags: [String] = []
        var freeform: String?
        var hasStructuredLine = false

        for line in rawComment.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let value = parseRatingLine(trimmed, prefix: "Servis Kalitesi:") {
                serviceQuality = value
                hasStructuredLine = true
            } else if let value = parseRatingLine(trimmed, prefix: "Personel İlgisi:") {
                staffCare = value
                hasStructuredLine = true
            } else if let value = parseRatingLine(trimmed, prefix: "Çözüm Hızı:") {
                resolutionSpeed = value
                hasStructuredLine = true
            } else if trimmed.hasPrefix("Deneyim:") {
                let tagsPart = trimmed.dropFirst("Deneyim:".count)
                    .trimmingCharacters(in: .whitespaces)
                experienceTags = tagsPart
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                hasStructuredLine = true
            } else if trimmed.hasPrefix("Yorum:") {
                freeform = String(trimmed.dropFirst("Yorum:".count))
                    .trimmingCharacters(in: .whitespaces)
                hasStructuredLine = true
            }
        }

        if !hasStructuredLine {
            freeform = rawComment.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return CustomerSatisfactionStructuredComment(
            serviceQualityRating: serviceQuality,
            staffCareRating: staffCare,
            resolutionSpeedRating: resolutionSpeed,
            experienceTags: experienceTags,
            freeformComment: freeform
        )
    }

    private static func parseRatingLine(_ line: String, prefix: String) -> Int? {
        guard line.hasPrefix(prefix) else { return nil }
        let remainder = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard let valuePart = remainder.split(separator: "/").first,
              let value = Int(valuePart) else {
            return nil
        }
        return value
    }
}

struct CustomerSatisfactionEntry: Identifiable, Equatable, Hashable, Sendable {
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

    var structuredComment: CustomerSatisfactionStructuredComment {
        CustomerSatisfactionStructuredComment.parse(from: satisfaction.comment)
    }

    var overallRatingValue: Int? {
        satisfaction.rating?.rawValue
    }

    var ratingLabel: String? {
        guard let overallRatingValue else { return nil }
        return "\(overallRatingValue) / 5"
    }

    var freeformCommentText: String? {
        guard satisfaction.status == .submitted else { return nil }
        guard let text = structuredComment.freeformComment?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    func dimensionScoreLabel(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value) / 5"
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
