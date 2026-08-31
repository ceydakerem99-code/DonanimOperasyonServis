import Foundation
import Observation

enum CustomerSatisfactionExperienceOption: String, CaseIterable, Identifiable, Hashable {
    case fastResolution = "Hızlı çözüldü"
    case attentiveStaff = "Personel ilgiliydi"
    case fullyResolved = "Sorun tamamen çözüldü"
    case goodCommunication = "Bilgilendirme iyiydi"

    var id: String { rawValue }
}

enum CustomerSatisfactionRatingDimension: String, CaseIterable, Identifiable {
    case overall = "Genel Memnuniyet"
    case serviceQuality = "Servis Kalitesi"
    case staffCare = "Personel İlgisi"
    case resolutionSpeed = "Çözüm Hızı"

    var id: String { rawValue }
}

struct CustomerSatisfactionFormContext: Equatable {
    let workOrderNumber: String
    let customerName: String
    let workTypeLabel: String
    let completedAt: Date?
}

@Observable
@MainActor
final class CustomerSatisfactionFormViewModel {
    enum Phase: Equatable {
        case loading
        case ready
        case submitting
        case success
        case error(String)
    }

    let satisfactionId: CustomerSatisfactionID
    private let submissionService: CustomerSatisfactionSubmissionService
    private let customerSatisfactionRepository: CustomerSatisfactionRepository
    private let remoteCustomerSatisfactionRepository: CustomerSatisfactionRepository?
    private let workOrderRepository: WorkOrderRepository
    private let customerRepository: CustomerRepository

    var overallRating: CustomerSatisfactionRating?
    var serviceQualityRating: CustomerSatisfactionRating?
    var staffCareRating: CustomerSatisfactionRating?
    var resolutionSpeedRating: CustomerSatisfactionRating?
    var selectedExperienceOptions: Set<CustomerSatisfactionExperienceOption> = []
    var freeformComment = ""
    private(set) var formContext: CustomerSatisfactionFormContext?
    private(set) var phase: Phase = .loading

    var canSubmit: Bool {
        overallRating != nil
            && serviceQualityRating != nil
            && staffCareRating != nil
            && resolutionSpeedRating != nil
            && phase != .submitting
            && phase != .success
            && phase != .loading
    }

    init(
        satisfactionId: CustomerSatisfactionID,
        submissionService: CustomerSatisfactionSubmissionService,
        customerSatisfactionRepository: CustomerSatisfactionRepository,
        remoteCustomerSatisfactionRepository: CustomerSatisfactionRepository? = nil,
        workOrderRepository: WorkOrderRepository,
        customerRepository: CustomerRepository
    ) {
        self.satisfactionId = satisfactionId
        self.submissionService = submissionService
        self.customerSatisfactionRepository = customerSatisfactionRepository
        self.remoteCustomerSatisfactionRepository = remoteCustomerSatisfactionRepository
        self.workOrderRepository = workOrderRepository
        self.customerRepository = customerRepository
    }

    func load() async {
        phase = .loading
        do {
            let satisfaction = try await loadSatisfaction()
            let order = try await workOrderRepository.fetch(id: satisfaction.workOrderId)
            let customer = try await customerRepository.fetch(id: satisfaction.customerId)
            formContext = CustomerSatisfactionFormContext(
                workOrderNumber: order.workOrderNumber,
                customerName: customer.name,
                workTypeLabel: order.workType.displayName,
                completedAt: order.completedAt
            )
            phase = .ready
        } catch {
            phase = .error("Değerlendirme bilgileri yüklenemedi.")
        }
    }

    /// The native form uses the local domain repository first. If it was
    /// opened from a valid already-synced survey link on a fresh device,
    /// hydrate that domain record from Firestore before reporting it missing.
    private func loadSatisfaction() async throws -> CustomerSatisfaction {
        do {
            return try await customerSatisfactionRepository.fetch(id: satisfactionId)
        } catch let error as DomainError {
            guard case .notFound = error,
                  let remoteCustomerSatisfactionRepository else {
                throw error
            }
            let remote = try await remoteCustomerSatisfactionRepository.fetch(id: satisfactionId)
            try await customerSatisfactionRepository.save(remote)
            return remote
        }
    }

    func selectRating(_ rating: CustomerSatisfactionRating, for dimension: CustomerSatisfactionRatingDimension) {
        guard phase != .success else { return }
        switch dimension {
        case .overall: overallRating = rating
        case .serviceQuality: serviceQualityRating = rating
        case .staffCare: staffCareRating = rating
        case .resolutionSpeed: resolutionSpeedRating = rating
        }
        if case .error = phase {
            phase = .ready
        }
    }

    func rating(for dimension: CustomerSatisfactionRatingDimension) -> CustomerSatisfactionRating? {
        switch dimension {
        case .overall: return overallRating
        case .serviceQuality: return serviceQualityRating
        case .staffCare: return staffCareRating
        case .resolutionSpeed: return resolutionSpeedRating
        }
    }

    func toggleExperienceOption(_ option: CustomerSatisfactionExperienceOption) {
        guard phase != .success else { return }
        if selectedExperienceOptions.contains(option) {
            selectedExperienceOptions.remove(option)
        } else {
            selectedExperienceOptions.insert(option)
        }
        if case .error = phase {
            phase = .ready
        }
    }

    func submit() async {
        guard let overallRating,
              let serviceQualityRating,
              let staffCareRating,
              let resolutionSpeedRating else { return }
        phase = .submitting
        let comment = buildSubmissionComment(
            serviceQuality: serviceQualityRating,
            staffCare: staffCareRating,
            resolutionSpeed: resolutionSpeedRating
        )
        do {
            _ = try await submissionService.submitWithSync(
                satisfactionId: satisfactionId,
                rating: overallRating,
                comment: comment
            )
            phase = .success
        } catch let error as DomainError {
            phase = .error(error.customerSatisfactionFormMessage)
        } catch {
            phase = .error("Değerlendirme gönderilemedi. Lütfen tekrar deneyin.")
        }
    }

    private func buildSubmissionComment(
        serviceQuality: CustomerSatisfactionRating,
        staffCare: CustomerSatisfactionRating,
        resolutionSpeed: CustomerSatisfactionRating
    ) -> String {
        var lines = [
            "Servis Kalitesi: \(serviceQuality.rawValue)/5",
            "Personel İlgisi: \(staffCare.rawValue)/5",
            "Çözüm Hızı: \(resolutionSpeed.rawValue)/5"
        ]
        if !selectedExperienceOptions.isEmpty {
            let tags = CustomerSatisfactionExperienceOption.allCases
                .filter { selectedExperienceOptions.contains($0) }
                .map(\.rawValue)
                .joined(separator: ", ")
            lines.append("Deneyim: \(tags)")
        }
        let trimmedComment = freeformComment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedComment.isEmpty {
            lines.append("Yorum: \(trimmedComment)")
        }
        return lines.joined(separator: "\n")
    }
}

extension DomainError {
    var customerSatisfactionFormMessage: String {
        switch self {
        case .invalidCustomerSatisfaction(let reason):
            switch reason {
            case .notPending:
                return "Bu değerlendirme zaten yanıtlanmış veya artık geçerli değil."
            case .workOrderNotCompleted, .pendingAlreadyExists:
                return "Bu değerlendirme şu anda gönderilemiyor."
            }
        case .invalidCustomerSatisfactionTransition:
            return "Bu değerlendirme artık gönderilemez."
        case .notFound:
            return "Değerlendirme kaydı bulunamadı."
        default:
            return "Değerlendirme gönderilemedi. Lütfen tekrar deneyin."
        }
    }
}
