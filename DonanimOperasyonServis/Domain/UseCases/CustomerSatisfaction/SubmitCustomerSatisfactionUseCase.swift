import Foundation

/// Submits a pending `CustomerSatisfaction` survey with a required
/// rating and an optional comment.
///
/// Authorization is intentionally omitted: the customer-facing survey
/// surface (web form / SMS) has no authenticated `User` actor in v1.
/// Callers must ensure the survey id is presented only to the intended
/// respondent.
struct SubmitCustomerSatisfactionUseCase: Sendable {
    let customerSatisfactionRepository: CustomerSatisfactionRepository

    init(customerSatisfactionRepository: CustomerSatisfactionRepository) {
        self.customerSatisfactionRepository = customerSatisfactionRepository
    }

    @discardableResult
    func execute(
        satisfactionId: CustomerSatisfactionID,
        rating: CustomerSatisfactionRating,
        comment: String? = nil,
        at now: Date = Date()
    ) async throws -> CustomerSatisfaction {
        var satisfaction = try await customerSatisfactionRepository.fetch(id: satisfactionId)

        guard satisfaction.status == .pending else {
            throw DomainError.invalidCustomerSatisfaction(reason: .notPending)
        }

        _ = try CustomerSatisfactionStateMachine.transition(
            from: satisfaction.status,
            to: .submitted
        )

        let trimmedComment = comment?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedComment = trimmedComment?.isEmpty == true ? nil : trimmedComment

        satisfaction.status = .submitted
        satisfaction.rating = rating
        satisfaction.comment = normalizedComment
        satisfaction.submittedAt = now
        satisfaction.updatedAt = now

        try await customerSatisfactionRepository.save(satisfaction)
        return satisfaction
    }
}
