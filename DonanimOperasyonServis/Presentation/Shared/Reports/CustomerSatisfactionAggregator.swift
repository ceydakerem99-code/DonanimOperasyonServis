import Foundation

enum CustomerSatisfactionAggregator {

    static func summary(from satisfactions: [CustomerSatisfaction]) -> CustomerSatisfactionSummary {
        let submitted = satisfactions.filter { $0.status == .submitted }
        let ratings = submitted.compactMap(\.rating)
        let average: Double? = ratings.isEmpty
            ? nil
            : Double(ratings.map(\.rawValue).reduce(0, +)) / Double(ratings.count)

        var distribution: [CustomerSatisfactionRating: Int] = [:]
        for rating in CustomerSatisfactionRating.allCases {
            distribution[rating] = 0
        }
        for rating in ratings {
            distribution[rating, default: 0] += 1
        }

        return CustomerSatisfactionSummary(
            averageRating: average,
            submittedCount: submitted.count,
            pendingCount: satisfactions.filter { $0.status == .pending }.count,
            expiredCount: satisfactions.filter { $0.status == .expired }.count,
            totalCount: satisfactions.count,
            ratingDistribution: distribution
        )
    }

    static func ratingBars(from summary: CustomerSatisfactionSummary) -> [CustomerSatisfactionRatingBar] {
        CustomerSatisfactionRating.allCases.map { rating in
            CustomerSatisfactionRatingBar(
                rating: rating,
                count: summary.ratingDistribution[rating] ?? 0
            )
        }
    }

    static func technicianSummaries(
        satisfactions: [CustomerSatisfaction],
        workOrdersById: [WorkOrderID: WorkOrder],
        techniciansById: [UserID: User]
    ) -> [CustomerSatisfactionTechnicianSummary] {
        struct Bucket {
            var ratings: [Int] = []
            var fiveStarCount = 0
        }

        var buckets: [UserID: Bucket] = [:]

        for satisfaction in satisfactions where satisfaction.status == .submitted {
            guard let rating = satisfaction.rating,
                  let order = workOrdersById[satisfaction.workOrderId] else { continue }
            let technicianId = order.assignedTechnicianId
            var bucket = buckets[technicianId, default: Bucket()]
            bucket.ratings.append(rating.rawValue)
            if rating == .five {
                bucket.fiveStarCount += 1
            }
            buckets[technicianId] = bucket
        }

        return buckets.compactMap { technicianId, bucket in
            guard !bucket.ratings.isEmpty else { return nil }
            let count = bucket.ratings.count
            let average = Double(bucket.ratings.reduce(0, +)) / Double(count)
            let fiveStarRatio = Double(bucket.fiveStarCount) / Double(count) * 100
            let name = techniciansById[technicianId]?.fullName ?? "Bilinmeyen"
            return CustomerSatisfactionTechnicianSummary(
                id: technicianId,
                name: name,
                averageRating: average,
                submittedCount: count,
                fiveStarRatio: fiveStarRatio
            )
        }
        .sorted { lhs, rhs in
            if lhs.averageRating != rhs.averageRating {
                return lhs.averageRating > rhs.averageRating
            }
            return lhs.submittedCount > rhs.submittedCount
        }
    }

    static func entries(
        satisfactions: [CustomerSatisfaction],
        workOrdersById: [WorkOrderID: WorkOrder],
        customersById: [CustomerID: Customer],
        techniciansById: [UserID: User]
    ) -> [CustomerSatisfactionEntry] {
        satisfactions
            .map { satisfaction in
                let order = workOrdersById[satisfaction.workOrderId]
                let customer = customersById[satisfaction.customerId]
                let technicianName = order.flatMap { techniciansById[$0.assignedTechnicianId]?.fullName }
                    ?? "Bilinmeyen"
                return CustomerSatisfactionEntry(
                    id: satisfaction.id,
                    satisfaction: satisfaction,
                    workOrderId: satisfaction.workOrderId,
                    workOrderNumber: order?.workOrderNumber ?? "—",
                    customerName: customer?.name ?? "Bilinmeyen müşteri",
                    technicianName: technicianName,
                    workTypeLabel: order?.workType.displayName ?? "—",
                    scheduledDate: order?.scheduledDate,
                    sortDate: entrySortDate(for: satisfaction)
                )
            }
            .sorted { $0.sortDate > $1.sortDate }
    }

    private static func entrySortDate(for satisfaction: CustomerSatisfaction) -> Date {
        satisfaction.submittedAt ?? satisfaction.updatedAt
    }
}
