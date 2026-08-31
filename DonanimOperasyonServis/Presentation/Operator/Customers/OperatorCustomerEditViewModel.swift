import Foundation
import Observation

@Observable
@MainActor
final class OperatorCustomerEditViewModel {
    let customerId: CustomerID

    var name = ""
    var contactPersonName = ""
    var phone = ""
    var email = ""
    var address = ""
    var city = ""
    var notes = ""

    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var loadError: String?
    private(set) var saveError: String?
    private(set) var didSave = false

    private let actor: User
    private let dependencies: OperatorDependencies

    init(customerId: CustomerID, actor: User, dependencies: OperatorDependencies) {
        self.customerId = customerId
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let customer = try await dependencies.customerRepository.fetch(id: customerId)
            name = customer.name
            contactPersonName = customer.contactPersonName ?? ""
            phone = customer.phoneNumber?.rawValue ?? ""
            email = customer.email ?? ""
            address = customer.address
            city = customer.city ?? ""
            notes = customer.notes ?? ""
        } catch let error as DomainError {
            loadError = error.operatorMessage
        } catch {
            loadError = "Müşteri bilgileri yüklenemedi."
        }
    }

    func save() async {
        saveError = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let phoneNumber = phone.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            _ = try await dependencies.customerService.updateWithSync(
                actor: actor,
                customerId: customerId,
                name: name,
                contactPersonName: contactPersonName.nilIfEmpty,
                phoneNumber: phoneNumber.map { PhoneNumber($0) },
                email: email.nilIfEmpty,
                address: address,
                city: city.nilIfEmpty,
                notes: notes.nilIfEmpty
            )
            didSave = true
        } catch let error as DomainError {
            saveError = error.operatorMessage
        } catch {
            saveError = "Müşteri güncellenemedi."
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
