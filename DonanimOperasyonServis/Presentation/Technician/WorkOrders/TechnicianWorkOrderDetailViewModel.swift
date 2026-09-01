import Foundation
import Observation
import AVFoundation
import CoreLocation

struct TechnicianWorkOrderDetailContent: Equatable, Sendable {
    let workOrder: WorkOrder
    let customer: Customer
    let notes: [WorkOrderNote]
    let photos: [WorkOrderPhoto]
    let locations: [WorkOrderLocation]
    let signatures: [Signature]
    let timeline: [WorkOrderStatusHistory]
    var editRequests: [EditRequest] = []
    let pendingSyncLabel: String?
    let hasConflict: Bool
    /// Full `CompletionRequirements.check` gaps (includes `.completed` GPS).
    let missingRequirements: [MissingRequirement]
    /// Gaps that block the Tamamla UI (excludes `.completed` GPS).
    let blockingCompletionGaps: [MissingRequirement]

    var reportSnapshot: WorkOrderReportSnapshot {
        WorkOrderReportSnapshot(
            workOrder: workOrder,
            customerName: customer.name,
            customerAddress: [customer.address, customer.city].compactMap { $0 }.joined(separator: ", "),
            technicianName: nil,
            notes: notes,
            photos: photos,
            locations: locations,
            signatures: signatures,
            timeline: timeline,
            editRequests: editRequests
        )
    }
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
    private(set) var showPhotoSheet = false
    private(set) var isAddingNote = false
    private(set) var isAddingPhoto = false
    private(set) var isCapturingLocation = false
    private(set) var isCapturingSignature = false
    private(set) var noteError: String?
    private(set) var photoError: String?
    private(set) var cameraPresentation: TechnicianCameraPresentationState = .idle
    private(set) var locationError: String?
    private(set) var signatureError: String?
    private(set) var selectedPhotoCategory: PhotoCategory = .before
    private(set) var selectedLocationEvent: LocationEvent = .arrived
    private(set) var selectedSignatureKind: SignatureKind = .technician
    private(set) var showLocationSheet = false
    private(set) var showSignatureSheet = false
    private(set) var showEditRequestSheet = false
    private(set) var isSubmittingEditRequest = false
    private(set) var editRequestError: String?
    private(set) var selectedEditField: EditableWorkOrderField = .issueDescription
    private(set) var completionErrors: [MissingRequirement] = []

    let workOrderId: WorkOrderID
    private let actor: User
    private let dependencies: TechnicianDependencies
    private let locationSampler: LocationSampling

    #if DEBUG
    var lastLocationSampleDiagnostics: LocationSampleDiagnostics? {
        if let sampler = locationSampler as? CoreLocationSampler {
            return sampler.lastSampleDiagnostics
        }
        if let sampler = locationSampler as? MockFieldLocationSampler {
            return sampler.lastSampleDiagnostics
        }
        return nil
    }
    #endif
    private let asyncLoad = AsyncLoadSession()
    private var activeLoadTask: Task<Void, Never>?
    private var isCompletingWorkOrder = false

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { content != nil }

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

    var canReject: Bool {
        content?.workOrder.status == .assigned
    }

    func rejectWorkOrder() async {
        guard canReject else { return }
        if content != nil { phase = .submitting }
        do {
            _ = try await dependencies.workOrderService.transitionStatus(
                actor: actor,
                orderId: workOrderId,
                newStatus: .rejected
            )
            let order = content?.workOrder
            let notification = AppNotification(
                id: NotificationID(UUID().uuidString),
                recipientUserId: order?.createdByUserId ?? UserID(""),
                type: .workOrderStatusChanged,
                title: "İş Emri Reddedildi",
                body: "\(order?.workOrderNumber ?? "") · \(actor.fullName) tarafından reddedildi. Yeniden atama yapılmalı.",
                relatedWorkOrderId: workOrderId,
                createdAt: Date()
            )
            try? await dependencies.notificationRepository.save(notification)
            await load()
        } catch is CancellationError {
            phase = content == nil ? .error("İşlem iptal edildi.") : .loaded
        } catch let error as DomainError {
            phase = .error(error.technicianMessage)
        } catch {
            phase = .error("İş emri reddedilemedi.")
        }
    }

    /// Field evidence (photos) after “İşe Başla”.
    var isFieldWorkActive: Bool {
        guard let status = content?.workOrder.status else { return false }
        return status == .inProgress || status == .paused
    }

    /// Digital signatures belong to iş teslimi (complete) — only while in progress.
    var isDeliveryPhase: Bool {
        content?.workOrder.status == .inProgress
    }

    var canAddNote: Bool {
        guard let order = content?.workOrder else { return false }
        return RoleAccessPolicy.can(.addWorkOrderNote, as: actor.role)
            && RoleAccessPolicy.canAct(on: order, as: actor)
    }

    var canAddPhoto: Bool {
        guard let order = content?.workOrder else { return false }
        guard isFieldWorkActive else { return false }
        return RoleAccessPolicy.can(.addWorkOrderPhoto, as: actor.role)
            && RoleAccessPolicy.canAct(on: order, as: actor)
    }

    var canCaptureLocation: Bool {
        guard let order = content?.workOrder else { return false }
        return RoleAccessPolicy.can(.captureLocationSample, as: actor.role)
            && RoleAccessPolicy.canAct(on: order, as: actor)
    }

    /// Tamamla UI gate — domain still enforces full CompletionRequirements.
    var canComplete: Bool {
        guard let content else { return false }
        guard content.workOrder.status == .inProgress else { return false }
        guard RoleAccessPolicy.can(.completeWorkOrder, as: actor.role) else { return false }
        guard RoleAccessPolicy.canAct(on: content.workOrder, as: actor) else { return false }
        return content.blockingCompletionGaps.isEmpty
    }

    var canCaptureSignature: Bool {
        guard let order = content?.workOrder else { return false }
        guard isDeliveryPhase else { return false }
        return RoleAccessPolicy.can(.captureSignature, as: actor.role)
            && RoleAccessPolicy.canAct(on: order, as: actor)
    }

    /// Required photo categories for the loaded work type (sectioned UI).
    var requiredPhotoCategories: [PhotoCategory] {
        guard let workType = content?.workOrder.workType else {
            return PhotoCategory.allCases
        }
        let required = PhotoRequirements.requiredCategories(for: workType)
        return required.isEmpty ? PhotoCategory.allCases : required
    }

    func photos(for category: PhotoCategory) -> [WorkOrderPhoto] {
        content?.photos.filter { $0.category == category } ?? []
    }

    func hasPhoto(for category: PhotoCategory) -> Bool {
        !photos(for: category).isEmpty
    }

    /// Shared field-work gate for photos / signatures / pause actions.
    var canMutateEvidence: Bool {
        guard let order = content?.workOrder else { return false }
        return RoleAccessPolicy.canAct(on: order, as: actor)
    }

    /// Completed + assigned technician may open an edit request.
    var canCreateEditRequest: Bool {
        guard let order = content?.workOrder else { return false }
        return RoleAccessPolicy.can(.createEditRequest, as: actor.role)
            && RoleAccessPolicy.canRequestEdit(on: order, as: actor)
    }

    /// Human-readable current value for the selected edit field.
    var selectedEditFieldCurrentDisplay: String {
        guard let order = content?.workOrder else { return "" }
        switch selectedEditField {
        case .scheduledDate:
            return WorkOrderPresentationMapping.formatDateTime(order.scheduledDate)
        case .priority:
            return order.priority.displayName
        default:
            return selectedEditField.value(on: order)
        }
    }

    func prepareForAppearance() {
        if isCompletingWorkOrder { return }
        if let content, content.workOrder.status == .completed, case .loaded = phase {
            Task { await refreshSyncIndicatorIfNeeded() }
            return
        }
        startLoad()
    }

    func startLoad() {
        guard !isCompletingWorkOrder else { return }
        activeLoadTask?.cancel()
        activeLoadTask = Task { @MainActor in
            await load()
            if !Task.isCancelled {
                activeLoadTask = nil
            }
        }
    }

    func stopLoad() {
        activeLoadTask?.cancel()
        activeLoadTask = nil
    }

    func load() async {
        if isCompletingWorkOrder, content != nil { return }

        let context = asyncLoad.start(hadCachedContent: hasCachedContent)
        if !context.hadCachedContentAtStart, content?.workOrder.status != .completed {
            phase = .loading
        }
        defer { asyncLoad.finish(generation: context.generation) }
        let generation = context.generation
        do {
            let loaded = try await fetchContent()
            if let existing = content,
               existing.workOrder.status == .completed,
               loaded.workOrder.status != .completed {
                phase = .loaded
                return
            }
            if content == nil || asyncLoad.isCurrent(generation) {
                content = loaded
                phase = .loaded
            }
        } catch is CancellationError {
            guard asyncLoad.isCurrent(generation) else { return }
            if content != nil {
                phase = .loaded
                return
            }
            if let settled = asyncLoad.settleCancelledLoad(
                context: context,
                phase: phase,
                loadingPhase: Phase.loading,
                loadedPhase: Phase.loaded,
                emptyPhase: Phase.error("Yükleme iptal edildi. Tekrar deneyin.")
            ) {
                phase = settled
            }
        } catch let error as DomainError {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error(error.technicianMessage)
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error("Detay yüklenemedi.")
        }
    }

    func performPrimaryAction() async {
        guard let action = primaryAction else { return }
        let keepContentVisible = content != nil
        if !keepContentVisible {
            phase = .submitting
        }
        do {
            if let event = action.locationEvent {
                let coordinate = try await locationSampler.sample(for: event)
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
        } catch is CancellationError {
            phase = content == nil ? .error("İşlem iptal edildi.") : .loaded
        } catch let error as LocationSamplingError {
            phase = .error(error.technicianMessage)
        } catch let error as DomainError {
            phase = .error(error.technicianMessage)
        } catch {
            phase = .error("Durum güncellenemedi.")
        }
    }

    func pause(reason: PauseReason) async {
        if content == nil {
            phase = .submitting
        }
        do {
            _ = try await dependencies.workOrderService.transitionStatus(
                actor: actor,
                orderId: workOrderId,
                newStatus: .paused,
                pauseReason: reason
            )
            showPauseSheet = false
            await load()
        } catch is CancellationError {
            phase = content == nil ? .error("İşlem iptal edildi.") : .loaded
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
        isCompletingWorkOrder = true
        stopLoad()
        defer { isCompletingWorkOrder = false }

        let keepContentVisible = content != nil
        if !keepContentVisible {
            phase = .submitting
        }
        do {
            let existingLocations = try await dependencies.workOrderLocationRepository.list(for: workOrderId)
            let completedLocationId: String
            if let existing = existingLocations.first(where: { $0.event == .completed }) {
                completedLocationId = existing.id
            } else {
                let coordinate = try await locationSampler.sample(for: .completed)
                let location = try await dependencies.workOrderService.recordLocation(
                    actor: actor,
                    orderId: workOrderId,
                    event: .completed,
                    coordinate: coordinate
                )
                completedLocationId = location.id
            }
            let order = try await dependencies.workOrderService.complete(
                actor: actor,
                orderId: workOrderId,
                completedLocationId: completedLocationId
            )
            completionErrors = []
            applyLocalCompletion(order)
            Task { await refreshSyncIndicatorIfNeeded() }
        } catch is CancellationError {
            if content?.workOrder.status == .completed {
                phase = .loaded
            } else {
                phase = content == nil ? .error("İşlem iptal edildi.") : .loaded
            }
        } catch let error as LocationSamplingError {
            phase = .error(error.technicianMessage)
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

    func openNoteSheet() {
        noteError = nil
        guard canAddNote else {
            noteError = DomainError.unauthorized(action: .addWorkOrderNote).technicianMessage
            return
        }
        showNoteSheet = true
    }

    func setNoteSheetVisible(_ visible: Bool) {
        guard !isAddingNote else { return }
        showNoteSheet = visible
        if !visible {
            noteError = nil
        }
    }

    func clearNoteError() {
        noteError = nil
    }

    /// Saves via existing `AddWorkOrderNoteUseCase` + sync enqueue.
    /// Does not flip the whole detail into `.submitting`.
    func addNote(_ text: String) async {
        guard !isAddingNote else { return }
        guard canAddNote else {
            noteError = DomainError.unauthorized(action: .addWorkOrderNote).technicianMessage
            return
        }

        isAddingNote = true
        noteError = nil
        do {
            _ = try await dependencies.workOrderService.addNote(
                actor: actor,
                orderId: workOrderId,
                text: text
            )
            showNoteSheet = false
            isAddingNote = false
            await load()
        } catch is CancellationError {
            isAddingNote = false
            if phase == .loading {
                phase = content == nil ? .error("Yükleme iptal edildi. Tekrar deneyin.") : .loaded
            }
        } catch let error as DomainError {
            isAddingNote = false
            noteError = error.technicianMessage
            if phase != .loaded, content != nil {
                phase = .loaded
            }
        } catch {
            isAddingNote = false
            noteError = "Not eklenemedi."
            if phase != .loaded, content != nil {
                phase = .loaded
            }
        }
    }

    func addPhoto(
        imageData: Data,
        category: PhotoCategory? = nil,
        dismissOnSuccess: Bool = false
    ) async {
        guard !isAddingPhoto else { return }
        guard canAddPhoto else {
            photoError = DomainError.unauthorized(action: .addWorkOrderPhoto).technicianMessage
            return
        }

        isAddingPhoto = true
        photoError = nil
        let resolvedCategory = category ?? selectedPhotoCategory
        do {
            _ = try await dependencies.workOrderService.addPhoto(
                actor: actor,
                orderId: workOrderId,
                category: resolvedCategory,
                imageData: imageData
            )
            if dismissOnSuccess {
                showPhotoSheet = false
            }
            isAddingPhoto = false
            await load()
        } catch is CancellationError {
            isAddingPhoto = false
            if phase == .loading {
                phase = content == nil ? .error("Yükleme iptal edildi. Tekrar deneyin.") : .loaded
            }
        } catch let error as DomainError {
            isAddingPhoto = false
            photoError = error.technicianMessage
            if phase != .loaded, content != nil {
                phase = .loaded
            }
        } catch {
            isAddingPhoto = false
            photoError = "Fotoğraf eklenemedi."
            if phase != .loaded, content != nil {
                phase = .loaded
            }
        }
    }

    func openPhotoSheet(category: PhotoCategory? = nil) {
        photoError = nil
        guard canAddPhoto else {
            photoError = DomainError.unauthorized(action: .addWorkOrderPhoto).technicianMessage
            return
        }
        if let category {
            selectedPhotoCategory = category
        } else if let firstMissing = requiredPhotoCategories.first(where: { !hasPhoto(for: $0) }) {
            selectedPhotoCategory = firstMissing
        } else {
            selectedPhotoCategory = requiredPhotoCategories.first ?? .before
        }
        showPhotoSheet = true
    }

    func setPhotoSheetVisible(_ visible: Bool) {
        guard !isAddingPhoto else { return }
        if !visible {
            resetCameraPresentation()
            photoError = nil
        }
        showPhotoSheet = visible
    }

    func resetCameraPresentation() {
        cameraPresentation = .idle
    }

    /// Opens the camera UI after permission/hardware checks.
    /// Returns `false` when presentation must not proceed.
    func requestCameraCapture(
        for category: PhotoCategory,
        isHardwareAvailable: Bool = TechnicianCameraAccess.isHardwareAvailable,
        authorizationStatus: AVAuthorizationStatus = TechnicianCameraAccess.authorizationStatus,
        requestAccess: () async -> Bool = { await TechnicianCameraAccess.requestAccess() }
    ) async -> Bool {
        guard !cameraPresentation.isBusy else { return false }
        cameraPresentation = .preparing
        defer {
            if case .preparing = cameraPresentation {
                cameraPresentation = .idle
            }
        }

        selectPhotoCategory(category)
        guard await prepareCameraCapture(
            isHardwareAvailable: isHardwareAvailable,
            authorizationStatus: authorizationStatus,
            requestAccess: requestAccess
        ) else {
            return false
        }

        cameraPresentation = .presenting(category: category)
        return true
    }

    func dismissCameraCapture() {
        if case .presenting = cameraPresentation {
            cameraPresentation = .idle
        }
    }

    var isPreparingCamera: Bool {
        if case .preparing = cameraPresentation { return true }
        return false
    }

    var presentingCameraCategory: PhotoCategory? {
        cameraPresentation.presentingCategory
    }

    func selectPhotoCategory(_ category: PhotoCategory) {
        selectedPhotoCategory = category
    }

    func clearPhotoError() {
        photoError = nil
    }

    /// Validates hardware + permission before presenting the camera UI.
    /// Returns `true` when the camera sheet may open.
    func prepareCameraCapture(
        isHardwareAvailable: Bool = TechnicianCameraAccess.isHardwareAvailable,
        authorizationStatus: AVAuthorizationStatus = TechnicianCameraAccess.authorizationStatus,
        requestAccess: () async -> Bool = { await TechnicianCameraAccess.requestAccess() }
    ) async -> Bool {
        photoError = nil
        guard canAddPhoto else {
            photoError = DomainError.unauthorized(action: .addWorkOrderPhoto).technicianMessage
            return false
        }
        guard isHardwareAvailable else {
            photoError = TechnicianCameraAccess.unavailableMessage
            return false
        }
        switch authorizationStatus {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await requestAccess()
            if granted { return true }
            photoError = TechnicianCameraAccess.deniedMessage
            return false
        case .denied, .restricted:
            photoError = TechnicianCameraAccess.deniedMessage
            return false
        @unknown default:
            photoError = TechnicianCameraAccess.unavailableMessage
            return false
        }
    }

    func openLocationSheet() {
        locationError = nil
        guard canCaptureLocation else {
            locationError = DomainError.unauthorized(action: .captureLocationSample).technicianMessage
            return
        }
        selectedLocationEvent = .arrived
        showLocationSheet = true
    }

    func setLocationSheetVisible(_ visible: Bool) {
        guard !isCapturingLocation else { return }
        showLocationSheet = visible
        if !visible {
            locationError = nil
        }
    }

    func selectLocationEvent(_ event: LocationEvent) {
        selectedLocationEvent = event
    }

    func clearLocationError() {
        locationError = nil
    }

    /// Pre-flight for services / authorization before starting a GPS capture.
    /// Returns `true` when sampling may proceed.
    func prepareLocationCapture(
        areServicesEnabled: Bool = true,
        authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    ) -> Bool {
        locationError = nil
        guard canCaptureLocation else {
            locationError = DomainError.unauthorized(action: .captureLocationSample).technicianMessage
            return false
        }
        guard areServicesEnabled else {
            locationError = TechnicianLocationAccess.unavailableMessage
            return false
        }
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse, .notDetermined:
            return true
        case .denied:
            locationError = TechnicianLocationAccess.deniedMessage
            return false
        case .restricted:
            locationError = LocationSamplingError.permissionRestricted.technicianMessage
            return false
        @unknown default:
            locationError = LocationSamplingError.failed.technicianMessage
            return false
        }
    }

    /// Saves via existing `CaptureWorkOrderLocationUseCase` + sync enqueue.
    /// Does not flip the whole detail into `.submitting`.
    func captureLocation(event: LocationEvent? = nil) async {
        guard !isCapturingLocation else { return }
        guard canCaptureLocation else {
            locationError = DomainError.unauthorized(action: .captureLocationSample).technicianMessage
            return
        }

        isCapturingLocation = true
        locationError = nil
        let resolvedEvent = event ?? selectedLocationEvent
        do {
            let coordinate = try await locationSampler.sample(for: resolvedEvent)
            _ = try await dependencies.workOrderService.recordLocation(
                actor: actor,
                orderId: workOrderId,
                event: resolvedEvent,
                coordinate: coordinate
            )
            showLocationSheet = false
            isCapturingLocation = false
            await load()
        } catch is CancellationError {
            isCapturingLocation = false
            if phase == .loading {
                phase = content == nil ? .error("Yükleme iptal edildi. Tekrar deneyin.") : .loaded
            }
        } catch let error as LocationSamplingError {
            isCapturingLocation = false
            locationError = error.technicianMessage
            if phase != .loaded, content != nil {
                phase = .loaded
            }
        } catch let error as DomainError {
            isCapturingLocation = false
            locationError = error.technicianMessage
            if phase != .loaded, content != nil {
                phase = .loaded
            }
        } catch {
            isCapturingLocation = false
            locationError = "Konum kaydedilemedi."
            if phase != .loaded, content != nil {
                phase = .loaded
            }
        }
    }

    func captureSignature(
        imageData: Data,
        kind: SignatureKind? = nil,
        signerName: String? = nil,
        dismissOnSuccess: Bool = false
    ) async {
        guard !isCapturingSignature else { return }
        guard canCaptureSignature else {
            signatureError = DomainError.unauthorized(action: .captureSignature).technicianMessage
            return
        }

        isCapturingSignature = true
        signatureError = nil
        let resolvedKind = kind ?? selectedSignatureKind
        do {
            _ = try await dependencies.workOrderService.recordSignature(
                actor: actor,
                orderId: workOrderId,
                kind: resolvedKind,
                imageData: imageData,
                signerName: signerName
            )
            if dismissOnSuccess {
                showSignatureSheet = false
            } else if resolvedKind == .technician {
                selectedSignatureKind = .customer
            } else if resolvedKind == .customer {
                // Keep sheet open so both completion states are visible.
            }
            isCapturingSignature = false
            await load()
        } catch is CancellationError {
            isCapturingSignature = false
            if phase == .loading {
                phase = content == nil ? .error("Yükleme iptal edildi. Tekrar deneyin.") : .loaded
            }
        } catch let error as DomainError {
            isCapturingSignature = false
            signatureError = error.technicianMessage
            if phase != .loaded, content != nil {
                phase = .loaded
            }
        } catch {
            isCapturingSignature = false
            signatureError = "İmza kaydedilemedi."
            if phase != .loaded, content != nil {
                phase = .loaded
            }
        }
    }

    var hasTechnicianSignature: Bool {
        content?.signatures.contains(where: { $0.kind == .technician }) == true
    }

    var hasCustomerSignature: Bool {
        content?.signatures.contains(where: { $0.kind == .customer }) == true
    }

    var areBothSignaturesComplete: Bool {
        hasTechnicianSignature && hasCustomerSignature
    }

    func openSignatureSheet(kind: SignatureKind = .technician) {
        signatureError = nil
        guard canCaptureSignature else {
            signatureError = DomainError.unauthorized(action: .captureSignature).technicianMessage
            return
        }
        selectedSignatureKind = kind
        showSignatureSheet = true
    }

    func setSignatureSheetVisible(_ visible: Bool) {
        guard !isCapturingSignature else { return }
        showSignatureSheet = visible
        if !visible {
            signatureError = nil
        }
    }

    func selectSignatureKind(_ kind: SignatureKind) {
        selectedSignatureKind = kind
    }

    func clearSignatureError() {
        signatureError = nil
    }

    func openEditRequestSheet() {
        editRequestError = nil
        guard canCreateEditRequest else {
            editRequestError = DomainError.unauthorized(action: .createEditRequest).technicianMessage
            return
        }
        selectedEditField = .issueDescription
        showEditRequestSheet = true
    }

    func setEditRequestSheetVisible(_ visible: Bool) {
        guard !isSubmittingEditRequest else { return }
        showEditRequestSheet = visible
        if !visible {
            editRequestError = nil
        }
    }

    func selectEditField(_ field: EditableWorkOrderField) {
        selectedEditField = field
        editRequestError = nil
    }

    /// Submits a new edit request for the loaded completed work order.
    func submitEditRequest(requestedValue: String, reason: String) async {
        editRequestError = nil
        guard canCreateEditRequest, let order = content?.workOrder else {
            editRequestError = DomainError.unauthorized(action: .createEditRequest).technicianMessage
            return
        }
        isSubmittingEditRequest = true
        do {
            let resolvedRequested: String
            switch selectedEditField {
            case .priority:
                let trimmed = requestedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard WorkOrderPriority(rawValue: trimmed) != nil else {
                    throw DomainError.invalidData(reason: "workOrder.priorityInvalid")
                }
                resolvedRequested = trimmed
            case .scheduledDate:
                let trimmed = requestedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard TimeInterval(trimmed) != nil else {
                    throw DomainError.invalidData(reason: "workOrder.scheduledDateInvalid")
                }
                resolvedRequested = trimmed
            default:
                resolvedRequested = requestedValue
            }
            _ = try await dependencies.editRequestService.createWithSync(
                actor: actor,
                orderId: order.id,
                field: selectedEditField,
                currentValue: selectedEditField.value(on: order),
                requestedValue: resolvedRequested,
                reason: reason
            )
            showEditRequestSheet = false
            isSubmittingEditRequest = false
            await load()
        } catch is CancellationError {
            isSubmittingEditRequest = false
        } catch let error as DomainError {
            isSubmittingEditRequest = false
            editRequestError = error.technicianMessage
        } catch {
            isSubmittingEditRequest = false
            editRequestError = "Düzenleme talebi oluşturulamadı."
        }
    }

    func setPauseSheetVisible(_ visible: Bool) { showPauseSheet = visible }

    private func applyLocalCompletion(_ order: WorkOrder) {
        guard let existing = content else { return }
        content = TechnicianWorkOrderDetailContent(
            workOrder: order,
            customer: existing.customer,
            notes: existing.notes,
            photos: existing.photos,
            locations: existing.locations,
            signatures: existing.signatures,
            timeline: existing.timeline,
            editRequests: existing.editRequests,
            pendingSyncLabel: SyncStatus.pending.technicianDisplayName,
            hasConflict: existing.hasConflict,
            missingRequirements: [],
            blockingCompletionGaps: []
        )
        phase = .loaded
    }

    /// Recomputes sync indicator fields without entering `.loading`.
    /// Called after completion and when the sync drain finishes.
    func refreshSyncIndicatorIfNeeded() async {
        let orderID = workOrderId.rawValue
        guard content != nil else {
            #if DEBUG
            AppLogger.sync.info(
                "DETAIL SYNC REFRESH SKIP workOrderId=\(orderID, privacy: .public) reason=noContent"
            )
            #endif
            return
        }
        guard !isCompletingWorkOrder else {
            #if DEBUG
            AppLogger.sync.info(
                "DETAIL SYNC REFRESH SKIP workOrderId=\(orderID, privacy: .public) reason=completing"
            )
            #endif
            return
        }
        #if DEBUG
        AppLogger.sync.info(
            "DETAIL SYNC REFRESH START workOrderId=\(orderID, privacy: .public)"
        )
        #endif
        let context = asyncLoad.start(hadCachedContent: true)
        defer { asyncLoad.finish(generation: context.generation) }
        let generation = context.generation
        do {
            let loaded = try await fetchContent()
            if asyncLoad.isCurrent(generation) {
                content = loaded
                phase = .loaded
                #if DEBUG
                AppLogger.sync.info(
                    "DETAIL SYNC REFRESH APPLIED workOrderId=\(orderID, privacy: .public) pendingSyncLabel=\(loaded.pendingSyncLabel ?? "nil", privacy: .public)"
                )
                #endif
            }
        } catch is CancellationError {
            if content != nil {
                phase = .loaded
            }
        } catch {
            #if DEBUG
            AppLogger.sync.error(
                "DETAIL SYNC REFRESH FAILED workOrderId=\(orderID, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            #endif
            if content != nil {
                phase = .loaded
            }
        }
    }

    private func hasPendingChildEvidenceSync(
        notes: [WorkOrderNote],
        locations: [WorkOrderLocation],
        workOrder: WorkOrder
    ) async throws -> Bool {
        for note in notes {
            let ops = (try? await dependencies.syncOperationRepository.list(
                entityType: .workOrderNote,
                entityId: note.id
            )) ?? []
            for operation in ops {
                if try await SyncQueueOperationalStaleness.isChildEvidenceOperationDetailBlocking(
                    operation,
                    workOrder: workOrder,
                    queue: dependencies.syncOperationRepository
                ) {
                    return true
                }
            }
        }
        for location in locations {
            let ops = (try? await dependencies.syncOperationRepository.list(
                entityType: .workOrderLocation,
                entityId: location.id
            )) ?? []
            for operation in ops {
                if try await SyncQueueOperationalStaleness.isChildEvidenceOperationDetailBlocking(
                    operation,
                    workOrder: workOrder,
                    queue: dependencies.syncOperationRepository
                ) {
                    return true
                }
            }
        }
        return false
    }

    private func fetchContent() async throws -> TechnicianWorkOrderDetailContent {
        let order = try await dependencies.getWorkOrder.execute(actor: actor, id: workOrderId)

        async let customerTask = dependencies.customerRepository.fetch(id: order.customerId)
        async let notesTask = dependencies.workOrderNoteRepository.list(for: order.id)
        async let photosTask = dependencies.workOrderPhotoRepository.list(for: order.id)
        async let locationsTask = dependencies.workOrderLocationRepository.list(for: order.id)
        async let signaturesTask = dependencies.signatureRepository.list(for: order.id)
        async let timelineTask = dependencies.statusHistoryRepository.list(for: order.id)

        let syncOps = (try? await dependencies.syncOperationRepository.list(
            entityType: .workOrder,
            entityId: order.id.rawValue
        )) ?? []

        let customer = try await customerTask
        let notes = try await notesTask
        let photos = try await photosTask
        let locations = try await locationsTask
        let signatures = try await signaturesTask
        let timeline = try await timelineTask

        var workOrderPending: SyncOperation?
        for operation in syncOps {
            if try await SyncQueueOperationalStaleness.isWorkOrderOperationDetailBlocking(
                operation,
                workOrder: order,
                queue: dependencies.syncOperationRepository
            ) {
                workOrderPending = operation
                break
            }
        }

        var blockingPhotos: [WorkOrderPhoto] = []
        for photo in photos {
            if try await SyncQueueOperationalStaleness.isMediaUploadDetailBlocking(
                hasPendingStoragePath: photo.isUploadPending,
                entityType: .workOrderPhoto,
                entityId: photo.id,
                workOrder: order,
                queue: dependencies.syncOperationRepository
            ) {
                blockingPhotos.append(photo)
            }
        }
        var blockingSignatures: [Signature] = []
        for signature in signatures {
            if try await SyncQueueOperationalStaleness.isMediaUploadDetailBlocking(
                hasPendingStoragePath: signature.isUploadPending,
                entityType: .signature,
                entityId: signature.id,
                workOrder: order,
                queue: dependencies.syncOperationRepository
            ) {
                blockingSignatures.append(signature)
            }
        }
        let mediaUploadPending = !blockingPhotos.isEmpty || !blockingSignatures.isEmpty
        let childEvidenceSyncPending = try await hasPendingChildEvidenceSync(
            notes: notes,
            locations: locations,
            workOrder: order
        )

        #if DEBUG
        await logDetailSyncDiagnostics(
            workOrderId: order.id,
            workOrderStatus: order.status,
            syncOps: syncOps,
            workOrderPending: workOrderPending,
            photos: photos,
            signatures: signatures,
            blockingPhotos: blockingPhotos,
            blockingSignatures: blockingSignatures,
            mediaUploadPending: mediaUploadPending,
            childEvidenceSyncPending: childEvidenceSyncPending,
            notes: notes,
            locations: locations
        )
        #endif

        var hasConflict = syncOps.contains { $0.status == .conflict }
        if !hasConflict {
            for operation in syncOps {
                if let conflict = try await dependencies.syncConflictRepository.fetch(
                    syncOperationId: operation.id
                ), !conflict.isResolved {
                    hasConflict = true
                    break
                }
            }
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
        let blockingGaps = CompletionRequirements.missingBeforeCompleteAction(context)

        let pendingLabel: String?
        let pendingBranch: String
        if let workOrderPending {
            pendingLabel = workOrderPending.status.technicianDisplayName
            pendingBranch = "WORKORDER_PENDING"
        } else if mediaUploadPending || childEvidenceSyncPending {
            pendingLabel = SyncStatus.pending.technicianDisplayName
            pendingBranch = mediaUploadPending && childEvidenceSyncPending
                ? "MEDIA_PENDING+CHILD_EVIDENCE_PENDING"
                : (mediaUploadPending ? "MEDIA_PENDING" : "CHILD_EVIDENCE_PENDING")
        } else {
            pendingLabel = nil
            pendingBranch = "NO_PENDING"
        }

        #if DEBUG
        AppLogger.sync.info(
            "DETAIL SYNC LABEL workOrderId=\(order.id.rawValue, privacy: .public) branch=\(pendingBranch, privacy: .public) pendingSyncLabel=\(pendingLabel ?? "nil", privacy: .public)"
        )
        #endif

        let editRequests = (try? await dependencies.editRequestRepository.list(for: order.id)) ?? []

        return TechnicianWorkOrderDetailContent(
            workOrder: order,
            customer: customer,
            notes: notes.sorted { $0.createdAt > $1.createdAt },
            photos: photos.sorted { $0.capturedAt > $1.capturedAt },
            locations: locations.sorted { $0.capturedAt > $1.capturedAt },
            signatures: signatures.sorted { $0.capturedAt > $1.capturedAt },
            timeline: timeline.sorted { $0.occurredAt < $1.occurredAt },
            editRequests: editRequests.sorted { $0.createdAt > $1.createdAt },
            pendingSyncLabel: pendingLabel,
            hasConflict: hasConflict,
            missingRequirements: missing,
            blockingCompletionGaps: blockingGaps
        )
    }

    #if DEBUG
    private func logDetailSyncDiagnostics(
        workOrderId: WorkOrderID,
        workOrderStatus: WorkOrderStatus,
        syncOps: [SyncOperation],
        workOrderPending: SyncOperation?,
        photos: [WorkOrderPhoto],
        signatures: [Signature],
        blockingPhotos: [WorkOrderPhoto],
        blockingSignatures: [Signature],
        mediaUploadPending: Bool,
        childEvidenceSyncPending: Bool,
        notes: [WorkOrderNote],
        locations: [WorkOrderLocation]
    ) async {
        AppLogger.sync.info(
            "DETAIL SYNC DIAG workOrderId=\(workOrderId.rawValue, privacy: .public) status=\(workOrderStatus.rawValue, privacy: .public) workOrderPending=\(workOrderPending?.id.rawValue ?? "nil", privacy: .public) mediaUploadPending=\(mediaUploadPending, privacy: .public) childEvidenceSyncPending=\(childEvidenceSyncPending, privacy: .public)"
        )
        for operation in syncOps {
            AppLogger.sync.info(
                "DETAIL SYNC DIAG workOrder op id=\(operation.id.rawValue, privacy: .public) type=\(operation.operationType.rawValue, privacy: .public) status=\(operation.status.rawValue, privacy: .public) actor=\(operation.actorUserId ?? "-", privacy: .public) localVersion=\(operation.localVersion, privacy: .public) dependsOn=\(operation.dependsOnOperationId?.rawValue ?? "-", privacy: .public)"
            )
        }
        if let workOrderPending {
            AppLogger.sync.info(
                "DETAIL SYNC DIAG WORKORDER_PENDING op=\(workOrderPending.id.rawValue, privacy: .public) status=\(workOrderPending.status.rawValue, privacy: .public)"
            )
        }
        for photo in blockingPhotos {
            AppLogger.sync.info(
                "DETAIL SYNC DIAG MEDIA_PENDING photoId=\(photo.id, privacy: .public) storagePath=\(photo.storagePath ?? "nil", privacy: .public) pendingPath=\(photo.isUploadPending, privacy: .public)"
            )
        }
        for signature in blockingSignatures {
            AppLogger.sync.info(
                "DETAIL SYNC DIAG MEDIA_PENDING signatureId=\(signature.id, privacy: .public) storagePath=\(signature.storagePath ?? "nil", privacy: .public) pendingPath=\(signature.isUploadPending, privacy: .public)"
            )
        }
        for photo in photos where photo.isUploadPending && !blockingPhotos.contains(where: { $0.id == photo.id }) {
            AppLogger.sync.info(
                "DETAIL SYNC DIAG MEDIA_STALE_IGNORED photoId=\(photo.id, privacy: .public) storagePath=\(photo.storagePath ?? "nil", privacy: .public)"
            )
        }
        for signature in signatures where signature.isUploadPending && !blockingSignatures.contains(where: { $0.id == signature.id }) {
            AppLogger.sync.info(
                "DETAIL SYNC DIAG MEDIA_STALE_IGNORED signatureId=\(signature.id, privacy: .public) storagePath=\(signature.storagePath ?? "nil", privacy: .public)"
            )
        }
        for note in notes {
            let ops = (try? await dependencies.syncOperationRepository.list(
                entityType: .workOrderNote,
                entityId: note.id
            )) ?? []
            for operation in ops where SyncQueueOperationalStaleness.isDetailBlocking(
                operation,
                workOrderStatus: workOrderStatus
            ) {
                AppLogger.sync.info(
                    "DETAIL SYNC DIAG CHILD_EVIDENCE noteId=\(note.id, privacy: .public) op=\(operation.id.rawValue, privacy: .public) status=\(operation.status.rawValue, privacy: .public) actor=\(operation.actorUserId ?? "-", privacy: .public)"
                )
            }
        }
        for location in locations {
            let ops = (try? await dependencies.syncOperationRepository.list(
                entityType: .workOrderLocation,
                entityId: location.id
            )) ?? []
            for operation in ops where SyncQueueOperationalStaleness.isDetailBlocking(
                operation,
                workOrderStatus: workOrderStatus
            ) {
                AppLogger.sync.info(
                    "DETAIL SYNC DIAG CHILD_EVIDENCE locationId=\(location.id, privacy: .public) op=\(operation.id.rawValue, privacy: .public) status=\(operation.status.rawValue, privacy: .public) actor=\(operation.actorUserId ?? "-", privacy: .public)"
                )
            }
        }
    }
    #endif
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
            missingRequirements: [.missingNote, .missingTechnicianSignature],
            blockingCompletionGaps: [.missingNote, .missingTechnicianSignature]
        )
        return vm
    }
}
#endif
