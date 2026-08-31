import Foundation
import Observation

struct OperatorCustomerRow: Identifiable, Equatable, Sendable {
    let id: CustomerID
    let name: String
    let subtitle: String
}

@Observable
@MainActor
final class OperatorCustomerListViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var rows: [OperatorCustomerRow] = []
    var searchText = ""

    private let actor: User
    private let dependencies: OperatorDependencies
    private let asyncLoad = AsyncLoadSession()

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { !rows.isEmpty }

    init(actor: User, dependencies: OperatorDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        let context = asyncLoad.start(hadCachedContent: hasCachedContent)
        if !context.hadCachedContentAtStart { phase = .loading }
        defer { asyncLoad.finish(generation: context.generation) }
        let generation = context.generation
        let search = searchText.isEmpty ? nil : searchText

        do {
            let customers = try await dependencies.customerRepository.list(searchText: search)
            guard asyncLoad.isCurrent(generation) else { return }
            applyCustomers(customers)
        } catch is CancellationError {
            guard asyncLoad.isCurrent(generation) else { return }
            if let settled = asyncLoad.settleCancelledLoad(
                context: context,
                phase: phase,
                loadingPhase: Phase.loading,
                loadedPhase: Phase.loaded,
                emptyPhase: Phase.empty
            ) {
                phase = settled
            }
            return
        } catch let error as DomainError {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error(error.operatorMessage)
            return
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error("Müşteriler yüklenemedi.")
            return
        }

        guard asyncLoad.isCurrent(generation) else { return }
        if await dependencies.networkReachability.isReachable {
            await dependencies.localDirectoryCacheRefresh.refreshCustomers()
            if let refreshed = try? await dependencies.customerRepository.list(searchText: search) {
                guard asyncLoad.isCurrent(generation) else { return }
                applyCustomers(refreshed)
            }
        }
    }

    private func applyCustomers(_ customers: [Customer]) {
        rows = customers.map(Self.makeRow)
        phase = rows.isEmpty ? .empty : .loaded
    }

    private static func makeRow(from customer: Customer) -> OperatorCustomerRow {
        var parts: [String] = []
        if let city = customer.city, !city.isEmpty {
            parts.append(city)
        }
        if let phone = customer.phoneNumber?.rawValue, !phone.isEmpty {
            parts.append(phone)
        }
        if parts.isEmpty, !customer.address.isEmpty {
            parts.append(customer.address)
        }
        return OperatorCustomerRow(
            id: customer.id,
            name: customer.name,
            subtitle: parts.joined(separator: " · ")
        )
    }
}

#if DEBUG
extension OperatorCustomerListViewModel {
    static func previewLoaded() -> OperatorCustomerListViewModel {
        let vm = OperatorCustomerListViewModel(
            actor: OperatorPreviewData.operatorUser,
            dependencies: DIContainer.mock().makeOperatorDependencies()
        )
        vm.phase = .loaded
        vm.rows = [
            OperatorCustomerRow(
                id: OperatorPreviewData.customerABC.id,
                name: OperatorPreviewData.customerABC.name,
                subtitle: "Çorum · +905301112233"
            )
        ]
        return vm
    }
}
#endif
