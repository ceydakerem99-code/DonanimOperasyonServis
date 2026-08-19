import Foundation
import Observation

struct NewWorkOrderDraft: Equatable, Sendable {
    var workType: WorkType?
    var customer: Customer?
    var deviceCategory: DeviceCategory = .pos
    var deviceBrand = ""
    var deviceModel = ""
    var serialNumber = ""
    var issueDescription = ""
    var priority: WorkOrderPriority = .normal
    var scheduledDate = Date()
    var scheduledStart = Date()
    var scheduledEnd = Date().addingTimeInterval(3600)
    var technician: User?
}

enum NewWorkOrderValidationField: String, CaseIterable, Hashable, Sendable {
    case workType
    case customer
    case deviceBrand
    case deviceModel
    case serialNumber
    case technician
}

@Observable
@MainActor
final class NewWorkOrderWizardViewModel {
    enum Phase: Equatable {
        case editing
        case submitting
        case success(WorkOrderID)
        case error(String)
    }

    static let stepTitles = ["İş Türü", "Müşteri", "Cihaz", "Öncelik", "Teknisyen", "Özet"]
    static let totalSteps = 6

    private(set) var currentStep = 1
    private(set) var phase: Phase = .editing
    private(set) var fieldErrors: [NewWorkOrderValidationField: String] = [:]
    private(set) var customers: [Customer] = []
    private(set) var technicians: [User] = []
    var customerSearchText = ""
    var technicianSearchText = ""
    private(set) var isOffline = false
    var showsCreateCustomer = false
    var isCreatingCustomer = false
    var newCustomerError: String?
    var newCustomerName = ""
    var newCustomerContact = ""
    var newCustomerPhone = ""
    var newCustomerEmail = ""
    var newCustomerAddress = ""
    var newCustomerCity = ""
    var newCustomerNotes = ""

    var draft = NewWorkOrderDraft()

    private let actor: User
    private let dependencies: OperatorDependencies

    init(actor: User, dependencies: OperatorDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func loadSelections() async {
        isOffline = !(await dependencies.networkReachability.isReachable)
        do {
            customers = try await dependencies.customerRepository.list(searchText: nil)
            technicians = try await dependencies.userRepository.list(role: .technician, isActive: true)
        } catch is CancellationError {
            return
        } catch {
            phase = .error("Seçim listeleri yüklenemedi.")
        }
    }

    func openCreateCustomer() {
        newCustomerError = nil
        newCustomerName = ""
        newCustomerContact = ""
        newCustomerPhone = ""
        newCustomerEmail = ""
        newCustomerAddress = ""
        newCustomerCity = ""
        newCustomerNotes = ""
        showsCreateCustomer = true
    }

    func createCustomer() async {
        isCreatingCustomer = true
        newCustomerError = nil
        defer { isCreatingCustomer = false }
        do {
            let phone: PhoneNumber?
            let trimmedPhone = newCustomerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            phone = trimmedPhone.isEmpty ? nil : PhoneNumber(trimmedPhone)
            let created = try await dependencies.customerService.createWithSync(
                actor: actor,
                name: newCustomerName,
                contactPersonName: newCustomerContact,
                phoneNumber: phone,
                email: newCustomerEmail,
                address: newCustomerAddress,
                city: newCustomerCity,
                notes: newCustomerNotes
            )
            customers.insert(created, at: 0)
            selectCustomer(created)
            showsCreateCustomer = false
        } catch let error as DomainError {
            newCustomerError = error.operatorMessage
        } catch {
            newCustomerError = "Müşteri kaydedilemedi."
        }
    }

    func nextStep() {
        guard validateCurrentStep() else { return }
        if currentStep < Self.totalSteps {
            currentStep += 1
        }
    }

    func previousStep() {
        if currentStep > 1 {
            currentStep -= 1
        }
    }

    func selectWorkType(_ type: WorkType) {
        draft.workType = type
        fieldErrors.removeValue(forKey: .workType)
    }

    func selectCustomer(_ customer: Customer) {
        draft.customer = customer
        fieldErrors.removeValue(forKey: .customer)
    }

    func selectTechnician(_ user: User) {
        draft.technician = user
        fieldErrors.removeValue(forKey: .technician)
    }

    func updateCustomerSearch(_ text: String) async {
        customerSearchText = text
        do {
            customers = try await dependencies.customerRepository.list(searchText: text.isEmpty ? nil : text)
        } catch {
            phase = .error("Müşteriler yüklenemedi.")
        }
    }

    var filteredTechnicians: [User] {
        let needle = technicianSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return technicians }
        return technicians.filter {
            $0.fullName.lowercased().contains(needle) || $0.email.lowercased().contains(needle)
        }
    }

    func submit() async {
        guard validateAllSteps() else {
            phase = .error("Eksik zorunlu alanları tamamlayın.")
            return
        }

        phase = .submitting
        isOffline = !(await dependencies.networkReachability.isReachable)

        guard let workType = draft.workType,
              let customer = draft.customer,
              let technician = draft.technician
        else {
            phase = .error("Eksik zorunlu alanları tamamlayın.")
            return
        }

        let request = NewWorkOrderRequest(
            id: WorkOrderID(UUID().uuidString),
            workOrderNumber: Self.makeWorkOrderNumber(),
            assignedTechnicianId: technician.id,
            customerId: customer.id,
            workType: workType,
            deviceCategory: draft.deviceCategory,
            deviceBrand: draft.deviceBrand.trimmingCharacters(in: .whitespaces),
            deviceModel: draft.deviceModel.trimmingCharacters(in: .whitespaces),
            serialNumber: draft.serialNumber.trimmingCharacters(in: .whitespaces),
            issueDescription: draft.issueDescription.isEmpty ? nil : draft.issueDescription,
            priority: draft.priority,
            scheduledDate: draft.scheduledDate,
            scheduledTimeRange: ScheduledTimeRange(start: draft.scheduledStart, end: draft.scheduledEnd)
        )

        do {
            let created = try await dependencies.workOrderService.createWithSync(
                actor: actor,
                request: request
            )
            phase = .success(created.id)
        } catch let error as DomainError {
            phase = .error(error.operatorMessage)
        } catch {
            phase = .error("İş emri oluşturulamadı.")
        }
    }

    private func validateCurrentStep() -> Bool {
        fieldErrors.removeAll()
        switch currentStep {
        case 1:
            if draft.workType == nil {
                fieldErrors[.workType] = "İş türü seçin."
            }
        case 2:
            if draft.customer == nil {
                fieldErrors[.customer] = "Müşteri seçin."
            }
        case 3:
            validateDeviceFields()
        case 4:
            break
        case 5:
            if draft.technician == nil {
                fieldErrors[.technician] = "Teknisyen seçin."
            }
        default:
            break
        }
        return fieldErrors.isEmpty
    }

    private func validateAllSteps() -> Bool {
        fieldErrors.removeAll()
        if draft.workType == nil { fieldErrors[.workType] = "İş türü seçin." }
        if draft.customer == nil { fieldErrors[.customer] = "Müşteri seçin." }
        validateDeviceFields()
        if draft.technician == nil { fieldErrors[.technician] = "Teknisyen seçin." }
        return fieldErrors.isEmpty
    }

    private func validateDeviceFields() {
        if draft.deviceBrand.trimmingCharacters(in: .whitespaces).isEmpty {
            fieldErrors[.deviceBrand] = "Marka girin."
        }
        if draft.deviceModel.trimmingCharacters(in: .whitespaces).isEmpty {
            fieldErrors[.deviceModel] = "Model girin."
        }
        if draft.serialNumber.trimmingCharacters(in: .whitespaces).isEmpty {
            fieldErrors[.serialNumber] = "Seri numarası girin."
        }
    }

    private static func makeWorkOrderNumber() -> String {
        "WO-\(Int(Date().timeIntervalSince1970).description.suffix(6))"
    }
}

#if DEBUG
extension NewWorkOrderWizardViewModel {
    static func previewInitial() -> NewWorkOrderWizardViewModel {
        let vm = NewWorkOrderWizardViewModel(
            actor: OperatorPreviewData.operatorUser,
            dependencies: DIContainer.mock().makeOperatorDependencies()
        )
        vm.customers = [OperatorPreviewData.customerABC, OperatorPreviewData.customerXYZ]
        vm.technicians = [OperatorPreviewData.technicianAhmet, OperatorPreviewData.technicianMehmet]
        return vm
    }
}
#endif
