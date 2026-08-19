import Foundation
import Observation

struct TechnicianWorkOrderDetailContent: Equatable, Sendable {
    let workOrder: WorkOrder
    let customer: Customer
    let notes: [WorkOrderNote]
    let photos: [WorkOrderPhoto]
    let locations: [WorkOrderLocation]
    let signatures: [Signature]
    let timeline: [WorkOrderStatusHistory]
    let pendingSyncLabel: String?
    let hasConflict: Bool
    let missingRequirements: [MissingRequirement]
}

@Observable
@MainActor
final class TechnicianWorkOrderDetailViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case submitting
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var content: TechnicianWorkOrderDetailContent?
    private(set) var showPauseSheet = false
    private(set) var showNoteSheet = false
    private(set) var completionErrors: [MissingRequirement] = []

    let workOrderId: WorkOrderID
    private let actor: User
    private let dependencies: TechnicianDependencies
    private let locationSampler: LocationSampling

    init(
        workOrderId: WorkOrderID,
        actor: User,
        dependencies: TechnicianDependencies,
        locationSampler: LocationSampling = FixedLocationSampler(
            coordinate: LocationCoordinate(latitude: 41.0082, longitude: 28.9784, accuracy: 8)
        )
    ) {
        self.workOrderId = workOrderId
        self.actor = actor
        self.dependencies = dependencies
        self.locationSampler = locationSampler
    }

    var primaryAction: TechnicianWorkOrderActionMapping.PrimaryAction? {
        content.map { TechnicianWorkOrderActionMapping.primaryAction(for: $0.workOrder.status) } ?? nil
    }

    func load() async {
        phase = .loading
        do {
            let order = try await dependencies.getWorkOrder.execute(actor: actor, id: workOrderId)
            let customer = try await dependencies.customerRepository.fetch(id: order.customerId)
            let notes = try await dependencies.workOrderNoteRepository.list(for: order.id)
            let photos = try await dependencies.workOrderPhotoRepository.list(for: order.id)
            let locations = try await dependencies.workOrderLocationRepository.list(for: order.id)
            let signatures = try await dependencies.signatureRepository.list(for: order.id)
            let timeline = try await dependencies.statusHistoryRepository.list(for: order.id)
            let syncOps = try await dependencies.syncOperationRepository.list(
                entityType: .workOrder,
                entityId: order.id.rawValue
            )
            let pending = syncOps.first { $0.status == .pending || $0.status == .failed }
            let conflicts = try await dependencies.syncConflictRepository.listUnresolved()
            let hasConflict = conflicts.contains { conflict in
                syncOps.contains { $0.id == conflict.syncOperationId }
            }
            let context = CompletionContext(
                workType: order.workType,
                notes: notes,
                photos: photos,
                locations: locations,
                signatures: signatures
            )
            let missing: [MissingRequirement]
            if case .failure(let failure) = CompletionRequirements.check(context) {
                missing = failure.items
            } else {
                missing = []
            }

            content = TechnicianWorkOrderDetailContent(
                workOrder: order,
                customer: customer,
                notes: notes,
                photos: photos,
                locations: locations,
                signatures: signatures,
                timeline: timeline.sorted { $0.occurredAt < $1.occurredAt },
                pendingSyncLabel: pending?.status.technicianDisplayName,
                hasConflict: hasConflict,
                missingRequirements: missing
            )
            phase = .loaded
        } catch let error as DomainError {
            phase = .error(error.technicianMessage)
        } catch {
            phase = .error("Detay yüklenemedi.")
        }
    }

    func performPrimaryAction() async {
        guard let action = primaryAction else { return }
        phase = .submitting
        do {
            if let event = action.locationEvent {
                let coordinate = try await locationSampler.sample()
                _ = try await dependencies.workOrderService.recordLocation(
                    actor: actor,
                    orderId: workOrderId,
                    event: event,
                    coordinate: coordinate
                )
            }
            _ = try await dependencies.workOrderService.transitionStatus(
                actor: actor,
                orderId: workOrderId,
                newStatus: action.targetStatus
            )
            await load()
        } catch let error as DomainError {
            phase = .error(error.technicianMessage)
        } catch {
            phase = .error("Durum güncellenemedi.")
        }
    }

    func pause(reason: PauseReason) async {
        phase = .submitting
        do {
            _ = try await dependencies.workOrderService.transitionStatus(
                actor: actor,
                orderId: workOrderId,
                newStatus: .paused,
                pauseReason: reason
            )
            showPauseSheet = false
            await load()
        } catch let error as DomainError {
            phase = .error(error.technicianMessage)
        } catch {
            phase = .error("Duraklatılamadı.")
        }
    }

    func resumeWork() async {
        await performPrimaryAction()
    }

    func completeWork() async {
        phase = .submitting
        do {
            let coordinate = try await locationSampler.sample()
            _ = try await dependencies.workOrderService.recordLocation(
                actor: actor,
                orderId: workOrderId,
                event: .completed,
                coordinate: coordinate
            )
            _ = try await dependencies.workOrderService.complete(
                actor: actor,
                orderId: workOrderId
            )
            completionErrors = []
            await load()
        } catch let error as DomainError {
            if case .incompleteWorkOrder(let items) = error {
                completionErrors = items
                phase = .loaded
            } else {
                phase = .error(error.technicianMessage)
            }
        } catch {
            phase = .error("Tamamlanamadı.")
        }
    }

    func addNote(_ text: String) async {
        phase = .submitting
        do {
            _ = try await dependencies.workOrderService.addNote(
                actor: actor,
                orderId: workOrderId,
                text: text
            )
            showNoteSheet = false
            await load()
        } catch let error as DomainError {
            phase = .error(error.technicianMessage)
        } catch {
            phase = .error("Not eklenemedi.")
        }
    }

    func addPhoto(category: PhotoCategory) async {
        phase = .submitting
        do {
            _ = try await dependencies.workOrderService.addPhoto(
                actor: actor,
                orderId: workOrderId,
                category: category,
                imageData: TechnicianPlaceholderImage.pngData
            )
            await load()
        } catch let error as DomainError {
            phase = .error(error.technicianMessage)
        } catch {
            phase = .error("Fotoğraf eklenemedi.")
        }
    }

    func captureSignature(kind: SignatureKind, signerName: String?) async {
        phase = .submitting
        do {
            _ = try await dependencies.workOrderService.recordSignature(
                actor: actor,
                orderId: workOrderId,
                kind: kind,
                imageData: TechnicianPlaceholderImage.pngData,
                signerName: signerName
            )
            await load()
        } catch let error as DomainError {
            phase = .error(error.technicianMessage)
        } catch {
            phase = .error("İmza kaydedilemedi.")
        }
    }

    func setPauseSheetVisible(_ visible: Bool) { showPauseSheet = visible }
    func setNoteSheetVisible(_ visible: Bool) { showNoteSheet = visible }
}

#if DEBUG
extension TechnicianWorkOrderDetailViewModel {
    static func previewLoaded() -> TechnicianWorkOrderDetailViewModel {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: WorkOrderID("wo-tech-1"),
            actor: TechnicianPreviewData.technician,
            dependencies: DIContainer.mock().makeTechnicianDependencies()
        )
        let order = TechnicianPreviewData.workOrder(status: .inProgress)
        vm.phase = .loaded
        vm.content = TechnicianWorkOrderDetailContent(
            workOrder: order,
            customer: TechnicianPreviewData.customer,
            notes: [],
            photos: [],
            locations: [],
            signatures: [],
            timeline: [],
            pendingSyncLabel: nil,
            hasConflict: false,
            missingRequirements: [.missingNote, .missingTechnicianSignature]
        )
        return vm
    }
}
#endif
