import Foundation
import Observation

struct OperatorEditRequestRow: Identifiable, Equatable, Sendable {
    let id: EditRequestID
    let workOrderNumber: String
    let requesterName: String
    let reason: String
    let fieldLabel: String
    let status: EditRequestStatus
}

@Observable
@MainActor
final class OperatorEditRequestListViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var rows: [OperatorEditRequestRow] = []
    var selectedFilter: OperatorEditRequestFilter = .pending

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
        do {
            let requests: [EditRequest]
            if let status = selectedFilter.status {
                requests = try await dependencies.editRequestRepository.listByStatus(status)
            } else {
                requests = try await loadAllRequests()
            }
            guard asyncLoad.isCurrent(generation) else { return }
            rows = await makeRows(from: requests)
            guard asyncLoad.isCurrent(generation) else { return }
            phase = rows.isEmpty ? .empty : .loaded
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
        } catch let error as DomainError {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error(error.operatorMessage)
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error("Düzenleme talepleri yüklenemedi.")
        }
    }

    func selectFilter(_ filter: OperatorEditRequestFilter) async {
        selectedFilter = filter
        await load()
    }

    private func loadAllRequests() async throws -> [EditRequest] {
        var all: [EditRequest] = []
        for status in EditRequestStatus.allCases {
            all.append(contentsOf: try await dependencies.editRequestRepository.listByStatus(status))
        }
        return all
    }

    /// Skips orphaned requests so one missing WO/user cannot block the inbox.
    private func makeRows(from requests: [EditRequest]) async -> [OperatorEditRequestRow] {
        var rows: [OperatorEditRequestRow] = []
        for request in requests.sorted(by: { $0.createdAt > $1.createdAt }) {
            let order = try? await dependencies.getWorkOrder.execute(actor: actor, id: request.workOrderId)
            let requester = try? await dependencies.userRepository.fetch(id: request.requestedByUserId)
            let field = EditableWorkOrderField(rawValue: request.field)?.displayName ?? request.field
            rows.append(
                OperatorEditRequestRow(
                    id: request.id,
                    workOrderNumber: order?.workOrderNumber ?? request.workOrderId.rawValue,
                    requesterName: requester?.fullName ?? "Bilinmeyen kullanıcı",
                    reason: request.reason,
                    fieldLabel: field,
                    status: request.status
                )
            )
        }
        return rows
    }
}

@Observable
@MainActor
final class OperatorEditRequestDetailViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case submitting
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var request: EditRequest?
    private(set) var workOrderNumber = ""
    private(set) var requesterName = ""

    let requestId: EditRequestID
    private let actor: User
    private let dependencies: OperatorDependencies

    init(requestId: EditRequestID, actor: User, dependencies: OperatorDependencies) {
        self.requestId = requestId
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        phase = .loading
        do {
            let loaded = try await dependencies.editRequestRepository.fetch(id: requestId)
            let order = try await dependencies.getWorkOrder.execute(actor: actor, id: loaded.workOrderId)
            let requester = try await dependencies.userRepository.fetch(id: loaded.requestedByUserId)
            request = loaded
            workOrderNumber = order.workOrderNumber
            requesterName = requester.fullName
            phase = .loaded
        } catch is CancellationError {
            if phase == .loading {
                phase = .error("Yükleme iptal edildi. Tekrar deneyin.")
            }
        } catch let error as DomainError {
            phase = .error(error.operatorMessage)
        } catch {
            phase = .error("Talep detayı yüklenemedi.")
        }
    }

    func approve() async {
        phase = .submitting
        do {
            _ = try await dependencies.editRequestService.approveWithSync(
                actor: actor,
                requestId: requestId
            )
            await load()
        } catch is CancellationError {
            phase = .loaded
        } catch let error as DomainError {
            phase = .error(error.operatorMessage)
        } catch {
            phase = .error("Onaylama başarısız.")
        }
    }

    func reject() async {
        phase = .submitting
        do {
            _ = try await dependencies.editRequestService.rejectWithSync(
                actor: actor,
                requestId: requestId
            )
            await load()
        } catch is CancellationError {
            phase = .loaded
        } catch let error as DomainError {
            phase = .error(error.operatorMessage)
        } catch {
            phase = .error("Reddetme başarısız.")
        }
    }
}

#if DEBUG
extension OperatorEditRequestListViewModel {
    static func previewLoaded() -> OperatorEditRequestListViewModel {
        let vm = OperatorEditRequestListViewModel(
            actor: OperatorPreviewData.operatorUser,
            dependencies: DIContainer.mock().makeOperatorDependencies()
        )
        vm.phase = .loaded
        vm.rows = [
            OperatorEditRequestRow(
                id: OperatorPreviewData.sampleEditRequest.id,
                workOrderNumber: "WO-1026",
                requesterName: OperatorPreviewData.technicianAhmet.fullName,
                reason: OperatorPreviewData.sampleEditRequest.reason,
                fieldLabel: "serialNumber",
                status: .pending
            )
        ]
        return vm
    }
}
#endif
