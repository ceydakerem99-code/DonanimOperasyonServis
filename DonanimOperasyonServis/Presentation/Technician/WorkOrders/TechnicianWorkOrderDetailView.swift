import SwiftUI
import PhotosUI
import UIKit

struct TechnicianWorkOrderDetailView: View {
    @Bindable var viewModel: TechnicianWorkOrderDetailViewModel
    var onShowReport: (WorkOrderID) -> Void
    @Environment(\.diContainer) private var container

    @State private var noteText = ""
    @State private var selectedPauseReason: PauseReason = .partWaiting
    @State private var customerSignerName = ""
    @State private var photoDraftByCategory: [PhotoCategory: Data] = [:]
    @State private var technicianSignatureStrokes: [[CGPoint]] = []
    @State private var customerSignatureStrokes: [[CGPoint]] = []
    @State private var editRequestedValue = ""
    @State private var editReason = ""
    @State private var editRequestedDate = Date()
    @State private var editRequestedPriority: WorkOrderPriority = .normal

    var body: some View {
        Group {
            if viewModel.phase == .submitting {
                if let content = viewModel.content {
                    detailBody(content)
                        .disabled(true)
                        .overlay {
                            ProgressView("Kaydediliyor…")
                                .padding(AppSpacing.l)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.card))
                        }
                } else {
                    LoadingView(message: "Kaydediliyor...")
                }
            } else {
                AsyncLoadContainerView(
                    isLoading: viewModel.phase == .loading,
                    showsLoadingIndicator: viewModel.showsLoadingIndicator,
                    hasCachedContent: viewModel.hasCachedContent,
                    errorMessage: AsyncLoadPhaseParsing.errorMessage(viewModel.phase),
                    isEmpty: false,
                    loadingMessage: "Detay yükleniyor...",
                    errorTitle: "Hata",
                    onRetry: { Task { await viewModel.load() } }
                ) {
                    if let content = viewModel.content {
                        detailBody(content)
                    }
                }
            }
        }
        .id(viewModel.workOrderId)
        .navigationTitle("İş Emri Detayı")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.prepareForAppearance() }
        .onDisappear { viewModel.stopLoad() }
        .onChange(of: container.syncProgressStore.isSyncing) { wasSyncing, isSyncing in
            guard wasSyncing == true, isSyncing == false else { return }
            Task { await viewModel.refreshSyncIndicatorIfNeeded() }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showPauseSheet },
            set: { viewModel.setPauseSheetVisible($0) }
        )) {
            pauseSheet
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showNoteSheet },
            set: { viewModel.setNoteSheetVisible($0) }
        )) {
            noteSheet
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showPhotoSheet },
            set: { viewModel.setPhotoSheetVisible($0) }
        )) {
            photoSheet
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showLocationSheet },
            set: { viewModel.setLocationSheetVisible($0) }
        )) {
            locationSheet
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showSignatureSheet },
            set: { viewModel.setSignatureSheetVisible($0) }
        )) {
            signatureSheet
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showEditRequestSheet },
            set: { viewModel.setEditRequestSheetVisible($0) }
        )) {
            editRequestSheet
        }
        .alert(
            "Servis Notu",
            isPresented: Binding(
                get: { viewModel.noteError != nil && !viewModel.showNoteSheet },
                set: { if !$0 { viewModel.clearNoteError() } }
            )
        ) {
            Button("Tamam", role: .cancel) { viewModel.clearNoteError() }
        } message: {
            Text(viewModel.noteError ?? "")
        }
        .alert(
            "Fotoğraf",
            isPresented: Binding(
                get: { viewModel.photoError != nil && !viewModel.showPhotoSheet },
                set: { if !$0 { viewModel.clearPhotoError() } }
            )
        ) {
            Button("Tamam", role: .cancel) { viewModel.clearPhotoError() }
        } message: {
            Text(viewModel.photoError ?? "")
        }
        .alert(
            "GPS Konumu",
            isPresented: Binding(
                get: { viewModel.locationError != nil && !viewModel.showLocationSheet },
                set: { if !$0 { viewModel.clearLocationError() } }
            )
        ) {
            Button("Tamam", role: .cancel) { viewModel.clearLocationError() }
        } message: {
            Text(viewModel.locationError ?? "")
        }
        .alert(
            "İmza",
            isPresented: Binding(
                get: { viewModel.signatureError != nil && !viewModel.showSignatureSheet },
                set: { if !$0 { viewModel.clearSignatureError() } }
            )
        ) {
            Button("Tamam", role: .cancel) { viewModel.clearSignatureError() }
        } message: {
            Text(viewModel.signatureError ?? "")
        }
    }

    @ViewBuilder
    private func detailBody(_ content: TechnicianWorkOrderDetailContent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                header(content)
                if let timeStatus = WorkOrderPresentationMapping.timeStatus(for: content.workOrder) {
                    WorkOrderTimeStatusDetailBanner(
                        status: timeStatus,
                        plannedScheduleLabel: WorkOrderPresentationMapping.plannedScheduleLabel(for: content.workOrder)
                    )
                }
                StepIndicator(
                    currentStep: WorkOrderPresentationMapping.statusStepIndex(for: content.workOrder.status),
                    totalSteps: 6,
                    titles: WorkOrderPresentationMapping.statusFlowTitles
                )
                syncBanner(content)
                customerSection(content)
                WorkOrderMapSection(
                    customerName: content.customer.name,
                    address: content.customer.address,
                    city: content.customer.city,
                    capturedLocations: content.locations
                )
                deviceSection(content.workOrder)
                workSection(content)
                notesSection(content)
                if viewModel.isFieldWorkActive || !content.photos.isEmpty {
                    photosSection(content)
                }
                locationsSection(content)
                if viewModel.isDeliveryPhase || !content.signatures.isEmpty {
                    signaturesSection(content)
                }
                deliveryChecklistSection(content)
                timelineSection(content)
                actionSection(content)
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
    }

    private func header(_ content: TechnicianWorkOrderDetailContent) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(content.workOrder.workOrderNumber).font(AppFont.title)
                PriorityBadge(priority: WorkOrderPresentationMapping.appPriority(from: content.workOrder.priority))
            }
            Spacer()
            StatusChip(status: WorkOrderPresentationMapping.appStatus(from: content.workOrder.status))
        }
    }

    @ViewBuilder
    private func syncBanner(_ content: TechnicianWorkOrderDetailContent) -> some View {
        if content.hasConflict {
            ErrorBanner(title: "Senkronizasyon çakışması", message: "Çakışma çözülmeden otomatik birleştirme yapılmaz.")
        } else if let label = content.pendingSyncLabel {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text(label).font(AppFont.caption)
            }
            .foregroundStyle(AppColor.info)
            .padding(AppSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.info.opacity(0.08)))
            #if DEBUG
            .onAppear {
                AppLogger.sync.info(
                    "DETAIL SYNC BANNER workOrderId=\(content.workOrder.id.rawValue, privacy: .public) label=\(label, privacy: .public)"
                )
            }
            #endif
        }
    }

    private func customerSection(_ content: TechnicianWorkOrderDetailContent) -> some View {
        card(title: "Müşteri Bilgileri") {
            InfoRow(title: "Müşteri", value: content.customer.name, systemImage: "building.2")
            if let phone = content.customer.phoneNumber?.rawValue {
                InfoRow(title: "Telefon", value: phone, systemImage: "phone")
            }
            InfoRow(title: "Adres", value: content.customer.address, systemImage: "mappin.and.ellipse")
        }
    }

    private func deviceSection(_ order: WorkOrder) -> some View {
        card(title: "Cihaz Bilgileri") {
            InfoRow(title: "Cihaz", value: order.deviceCategory.displayName, systemImage: "creditcard")
            InfoRow(title: "Marka / Model", value: "\(order.deviceBrand) \(order.deviceModel)", systemImage: "wrench.and.screwdriver")
            InfoRow(title: "Seri No", value: order.serialNumber, systemImage: "number")
        }
    }

    private func workSection(_ content: TechnicianWorkOrderDetailContent) -> some View {
        card(title: "İş Bilgileri") {
            InfoRow(title: "İş Türü", value: content.workOrder.workType.displayName, systemImage: "briefcase")
            if let description = content.workOrder.issueDescription {
                InfoRow(title: "Açıklama", value: description, systemImage: "text.alignleft")
            }
            InfoRow(
                title: "Planlanan Zaman",
                value: WorkOrderPresentationMapping.formatDateTime(content.workOrder.scheduledDate),
                systemImage: "calendar"
            )
        }
    }

    private func notesSection(_ content: TechnicianWorkOrderDetailContent) -> some View {
        card(title: "Servis Notları") {
            if content.notes.isEmpty {
                Text("Henüz servis notu yok.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            } else {
                ForEach(content.notes, id: \.id) { note in
                    InfoRow(
                        title: WorkOrderPresentationMapping.formatDateTime(note.createdAt),
                        value: note.text,
                        systemImage: "note.text"
                    )
                }
            }
            if viewModel.canAddNote {
                SecondaryButton(title: "Not Ekle", systemImage: "plus.circle") {
                    noteText = ""
                    viewModel.openNoteSheet()
                }
            }
        }
    }

    private func photosSection(_ content: TechnicianWorkOrderDetailContent) -> some View {
        card(title: "Saha Fotoğrafları") {
            if !viewModel.isFieldWorkActive {
                Text("Fotoğraflar “İşe Başla” sonrasında eklenir.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }

            ForEach(viewModel.requiredPhotoCategories, id: \.self) { category in
                let photos = viewModel.photos(for: category)
                HStack(spacing: AppSpacing.m) {
                    Image(systemName: photos.isEmpty ? "circle" : "checkmark.circle.fill")
                        .foregroundStyle(photos.isEmpty ? AppColor.secondaryText : AppColor.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.displayName).font(AppFont.body)
                        Text(photos.isEmpty ? "Bekleniyor" : "\(photos.count) fotoğraf")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    Spacer()
                    if let first = photos.first {
                        photoThumbnail(for: first)
                    }
                }
                .frame(minHeight: AppSpacing.minimumTouchTarget)
            }

            if viewModel.canAddPhoto {
                SecondaryButton(title: "Fotoğraf Yükle", systemImage: "camera") {
                    photoDraftByCategory = [:]
                    viewModel.openPhotoSheet()
                }
            }
        }
    }

    private func locationsSection(_ content: TechnicianWorkOrderDetailContent) -> some View {
        card(title: "GPS Kayıtları") {
            if content.locations.isEmpty {
                Text("Henüz GPS kaydı yok.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            } else {
                ForEach(content.locations, id: \.id) { location in
                    locationRow(location)
                }
            }
            if viewModel.canCaptureLocation {
                SecondaryButton(title: "Konum Ekle", systemImage: "location") {
                    viewModel.openLocationSheet()
                }
                .disabled(viewModel.isCapturingLocation)
            }
        }
    }

    private func signaturesSection(_ content: TechnicianWorkOrderDetailContent) -> some View {
        card(title: "İş Teslimi — İmzalar") {
            if content.signatures.isEmpty {
                Text("Teknisyen ve müşteri imzası teslim aşamasında alınır.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            } else {
                ForEach(content.signatures, id: \.id) { signature in
                    signatureRow(signature)
                }
            }
            if viewModel.canCaptureSignature {
                SecondaryButton(title: "Dijital İmzalar", systemImage: "signature") {
                    technicianSignatureStrokes = []
                    customerSignatureStrokes = []
                    customerSignerName = ""
                    viewModel.openSignatureSheet()
                }
                .disabled(viewModel.isCapturingSignature)
            }
        }
    }

    private func signatureRow(_ signature: Signature) -> some View {
        HStack(spacing: AppSpacing.m) {
            signatureThumbnail(for: signature)
            VStack(alignment: .leading, spacing: 2) {
                Text(signature.kind.displayName)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.primaryText)
                if let name = signature.signerName, !name.isEmpty {
                    Text(name)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                Text(WorkOrderPresentationMapping.formatDateTime(signature.capturedAt))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                if signature.isUploadPending {
                    Text("Senkronizasyon bekliyor")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.info)
                }
            }
            Spacer()
        }
        .frame(minHeight: AppSpacing.minimumTouchTarget)
    }

    @ViewBuilder
    private func signatureThumbnail(for signature: Signature) -> some View {
        let data = TechnicianLocalMediaStore.loadSignature(
            workOrderId: signature.workOrderId,
            signatureId: signature.id
        )
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: "signature")
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
        .frame(width: 72, height: 48)
        .background(AppColor.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .strokeBorder(AppColor.divider)
        )
    }

    private func locationRow(_ location: WorkOrderLocation) -> some View {
        HStack(spacing: AppSpacing.m) {
            Image(systemName: "location.fill")
                .foregroundStyle(AppColor.brandPrimary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(location.event.displayName)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.primaryText)
                Text(WorkOrderPresentationMapping.formatDateTime(location.capturedAt))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                Text(
                    String(
                        format: "%.5f, %.5f",
                        location.coordinate.latitude,
                        location.coordinate.longitude
                    )
                )
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            }
            Spacer()
            if let url = mapsURL(for: location.coordinate) {
                Link(destination: url) {
                    Image(systemName: "map")
                        .foregroundStyle(AppColor.brandPrimary)
                        .frame(minWidth: AppSpacing.minimumTouchTarget, minHeight: AppSpacing.minimumTouchTarget)
                }
            }
        }
        .frame(minHeight: AppSpacing.minimumTouchTarget)
    }

    private func mapsURL(for coordinate: LocationCoordinate) -> URL? {
        URL(string: "http://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=\(coordinate.latitude),\(coordinate.longitude)")
    }

    private func photoRow(_ photo: WorkOrderPhoto) -> some View {
        HStack(spacing: AppSpacing.m) {
            photoThumbnail(for: photo)
            VStack(alignment: .leading, spacing: 2) {
                Text(photo.category.displayName)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.primaryText)
                Text(WorkOrderPresentationMapping.formatDateTime(photo.capturedAt))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                if photo.isUploadPending {
                    Text("Senkronizasyon bekliyor")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.info)
                }
            }
            Spacer()
        }
        .frame(minHeight: AppSpacing.minimumTouchTarget)
    }

    @ViewBuilder
    private func photoThumbnail(for photo: WorkOrderPhoto) -> some View {
        let data = TechnicianLocalMediaStore.loadPhoto(
            workOrderId: photo.workOrderId,
            photoId: photo.id
        )
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
        .frame(width: 56, height: 56)
        .background(AppColor.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .strokeBorder(AppColor.divider)
        )
    }

    @ViewBuilder
    private func deliveryChecklistSection(_ content: TechnicianWorkOrderDetailContent) -> some View {
        if content.workOrder.status == .inProgress {
            card(title: "İş Teslimi Kontrol Listesi") {
                if content.blockingCompletionGaps.isEmpty {
                    Text("Teslim için zorunlu alanlar tamam.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.success)
                } else {
                    Text("Tamamlamadan önce eksikler:")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                    ForEach(content.blockingCompletionGaps, id: \.self) { item in
                        Text("• \(item.technicianDisplayName)")
                            .font(AppFont.label)
                            .foregroundStyle(AppColor.warning)
                    }
                    Text("Tamamlanma GPS kaydı “Tamamla” sırasında alınır.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                if !viewModel.completionErrors.isEmpty {
                    ForEach(viewModel.completionErrors, id: \.self) { item in
                        Text("Eksik: \(item.technicianDisplayName)")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.danger)
                    }
                }
            }
        }
    }

    private func timelineSection(_ content: TechnicianWorkOrderDetailContent) -> some View {
        card(title: "Zaman Çizelgesi") {
            if content.timeline.isEmpty {
                Text("Henüz kayıt yok.").font(AppFont.caption).foregroundStyle(AppColor.secondaryText)
            } else {
                ForEach(Array(content.timeline.enumerated()), id: \.element.id) { index, entry in
                    TimelineItem(
                        time: WorkOrderPresentationMapping.formatTime(entry.occurredAt),
                        title: entry.toStatus.displayName,
                        subtitle: entry.pauseReason?.displayName,
                        accentColor: WorkOrderPresentationMapping.appStatus(from: entry.toStatus).accentColor,
                        systemImage: WorkOrderPresentationMapping.appStatus(from: entry.toStatus).symbolName,
                        showsConnector: index < content.timeline.count - 1
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func actionSection(_ content: TechnicianWorkOrderDetailContent) -> some View {
        if content.workOrder.status == .completed {
            VStack(spacing: AppSpacing.m) {
                SecondaryButton(title: "Servis Raporu", systemImage: "doc.text") {
                    onShowReport(content.workOrder.id)
                }
                if viewModel.canCreateEditRequest {
                    PrimaryButton(title: "Düzenleme Talebi", systemImage: "pencil") {
                        prepareEditRequestSheet(for: content.workOrder)
                        viewModel.openEditRequestSheet()
                    }
                }
            }
        } else if content.workOrder.status == .inProgress {
            HStack(spacing: AppSpacing.m) {
                SecondaryButton(title: "Duraklat", systemImage: "pause.circle") {
                    viewModel.setPauseSheetVisible(true)
                }
                PrimaryButton(
                    title: "Tamamla",
                    systemImage: "checkmark.seal",
                    isEnabled: viewModel.canComplete
                ) {
                    Task { await viewModel.completeWork() }
                }
            }
        } else if let action = viewModel.primaryAction {
            VStack(spacing: AppSpacing.m) {
                PrimaryButton(title: action.title, systemImage: action.systemImage) {
                    Task { await viewModel.performPrimaryAction() }
                }
                if viewModel.canReject {
                    SecondaryButton(title: "Reddet", systemImage: "xmark.circle") {
                        Task { await viewModel.rejectWorkOrder() }
                    }
                }
            }
        }
    }

    private var pauseSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                Text("Duraklatma Nedeni").font(AppFont.subtitle)
                Picker("Neden", selection: $selectedPauseReason) {
                    ForEach(PauseReason.allCases, id: \.self) { reason in
                        Text(reason.displayName).tag(reason)
                    }
                }
                .pickerStyle(.inline)
                PrimaryButton(title: "Duraklat") {
                    Task { await viewModel.pause(reason: selectedPauseReason) }
                }
            }
            .padding(AppSpacing.l)
            .navigationTitle("Duraklat")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private var noteSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                Text("Servis Notu").font(AppFont.subtitle)
                if let noteError = viewModel.noteError {
                    Text(noteError)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.danger)
                }
                TextEditor(text: $noteText)
                    .frame(minHeight: 120)
                    .padding(AppSpacing.s)
                    .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
                    .disabled(viewModel.isAddingNote)
                PrimaryButton(
                    title: "Kaydet",
                    isLoading: viewModel.isAddingNote,
                    isEnabled: !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && !viewModel.isAddingNote
                ) {
                    Task {
                        await viewModel.addNote(noteText)
                        if viewModel.noteError == nil {
                            noteText = ""
                        }
                    }
                }
            }
            .padding(AppSpacing.l)
            .navigationTitle("Not Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { viewModel.setNoteSheetVisible(false) }
                        .disabled(viewModel.isAddingNote)
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(viewModel.isAddingNote)
    }

    private var photoSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    if viewModel.isPreparingCamera {
                        HStack(spacing: AppSpacing.s) {
                            ProgressView()
                            Text("Kamera hazırlanıyor...")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                    }

                    if let photoError = viewModel.photoError {
                        Text(photoError)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.danger)
                    }

                    Text("Her kategori için ayrı fotoğraf yükleyin.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)

                    ForEach(viewModel.requiredPhotoCategories, id: \.self) { category in
                        photoCategorySection(category)
                        if category != viewModel.requiredPhotoCategories.last {
                            Divider()
                        }
                    }
                }
                .padding(AppSpacing.l)
            }
            .navigationTitle("Saha Fotoğrafları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(viewModel.requiredPhotoCategories.allSatisfy { viewModel.hasPhoto(for: $0) } ? "Kapat" : "Vazgeç") {
                        viewModel.setPhotoSheetVisible(false)
                    }
                    .disabled(viewModel.isAddingPhoto || viewModel.isPreparingCamera)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(viewModel.isAddingPhoto || viewModel.isPreparingCamera)
        .fullScreenCover(
            isPresented: Binding(
                get: { viewModel.presentingCameraCategory != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissCameraCapture()
                    }
                }
            )
        ) {
            if let category = viewModel.presentingCameraCategory {
                TechnicianCameraPicker(
                    onCapture: { data in
                        viewModel.dismissCameraCapture()
                        photoDraftByCategory[category] = data
                        viewModel.selectPhotoCategory(category)
                        viewModel.clearPhotoError()
                    },
                    onCancel: {
                        viewModel.dismissCameraCapture()
                    }
                )
                .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private func photoCategorySection(_ category: PhotoCategory) -> some View {
        let existing = viewModel.photos(for: category)
        let isComplete = !existing.isEmpty

        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text(category.displayName).font(AppFont.subtitle)
            HStack(spacing: AppSpacing.s) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isComplete ? AppColor.success : AppColor.secondaryText)
                Text(isComplete ? "Tamamlandı" : "Bekleniyor")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }

            if let first = existing.first {
                photoThumbnail(for: first)
            }

            if !isComplete {
                CategoryPhotoCaptureControls(
                    category: category,
                    draft: Binding(
                        get: { photoDraftByCategory[category] },
                        set: { photoDraftByCategory[category] = $0 }
                    ),
                    isBusy: viewModel.isAddingPhoto || viewModel.isPreparingCamera,
                    isCameraPresented: viewModel.presentingCameraCategory == category,
                    onSave: { data in
                        Task {
                            await viewModel.addPhoto(
                                imageData: data,
                                category: category,
                                dismissOnSuccess: false
                            )
                            if viewModel.photoError == nil {
                                photoDraftByCategory[category] = nil
                            }
                        }
                    },
                    onRequestCamera: {
                        Task {
                            _ = await viewModel.requestCameraCapture(for: category)
                        }
                    }
                )
            }
        }
    }

    private var locationSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                Text("Konum Olayı").font(AppFont.subtitle)
                Picker("Olay", selection: Binding(
                    get: { viewModel.selectedLocationEvent },
                    set: { viewModel.selectLocationEvent($0) }
                )) {
                    ForEach(LocationEvent.allCases, id: \.self) { event in
                        Text(event.displayName).tag(event)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.isCapturingLocation)

                if let locationError = viewModel.locationError {
                    Text(locationError)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.danger)
                }

                #if DEBUG
                if let diagnostics = viewModel.lastLocationSampleDiagnostics {
                    Text(diagnostics.debugSummary)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                #endif

                Text("Cihaz GPS konumunuz mevcut iş emrine kaydedilir.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)

                PrimaryButton(
                    title: "Konumu Kaydet",
                    isLoading: viewModel.isCapturingLocation,
                    isEnabled: !viewModel.isCapturingLocation
                ) {
                    Task {
                        let allowed = viewModel.prepareLocationCapture(
                            authorizationStatus: TechnicianLocationAccess.authorizationStatus
                        )
                        guard allowed else { return }
                        await viewModel.captureLocation()
                    }
                }
            }
            .padding(AppSpacing.l)
            .navigationTitle("GPS Konumu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { viewModel.setLocationSheetVisible(false) }
                        .disabled(viewModel.isCapturingLocation)
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(viewModel.isCapturingLocation)
    }

    private var signatureSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    if let signatureError = viewModel.signatureError {
                        Text(signatureError)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.danger)
                    }

                    if viewModel.areBothSignaturesComplete {
                        Text("İmzalar tamamlandı")
                            .font(AppFont.subtitle)
                            .foregroundStyle(AppColor.success)
                    }

                    signatureSection(
                        title: "Teknisyen İmzası",
                        isComplete: viewModel.hasTechnicianSignature,
                        strokes: $technicianSignatureStrokes,
                        isEnabled: !viewModel.hasTechnicianSignature && !viewModel.isCapturingSignature,
                        saveTitle: "Kaydet",
                        onSave: {
                            guard let data = SignatureImageExport.pngData(strokes: technicianSignatureStrokes),
                                  !data.isEmpty
                            else {
                                Task { await viewModel.captureSignature(imageData: Data(), kind: .technician) }
                                return
                            }
                            Task {
                                await viewModel.captureSignature(
                                    imageData: data,
                                    kind: .technician,
                                    dismissOnSuccess: false
                                )
                                if viewModel.signatureError == nil {
                                    technicianSignatureStrokes = []
                                }
                            }
                        }
                    )

                    Divider()

                    signatureSection(
                        title: "Müşteri İmzası",
                        isComplete: viewModel.hasCustomerSignature,
                        strokes: $customerSignatureStrokes,
                        isEnabled: viewModel.hasTechnicianSignature
                            && !viewModel.hasCustomerSignature
                            && !viewModel.isCapturingSignature,
                        saveTitle: "Kaydet",
                        onSave: {
                            guard let data = SignatureImageExport.pngData(strokes: customerSignatureStrokes),
                                  !data.isEmpty
                            else {
                                Task {
                                    await viewModel.captureSignature(
                                        imageData: Data(),
                                        kind: .customer,
                                        signerName: customerSignerName.isEmpty ? nil : customerSignerName
                                    )
                                }
                                return
                            }
                            Task {
                                await viewModel.captureSignature(
                                    imageData: data,
                                    kind: .customer,
                                    signerName: customerSignerName.isEmpty ? nil : customerSignerName,
                                    dismissOnSuccess: false
                                )
                                if viewModel.signatureError == nil {
                                    customerSignatureStrokes = []
                                }
                            }
                        },
                        showCustomerName: true
                    )
                }
                .padding(AppSpacing.l)
            }
            .navigationTitle("Dijital İmzalar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(viewModel.areBothSignaturesComplete ? "Kapat" : "Vazgeç") {
                        viewModel.setSignatureSheetVisible(false)
                    }
                    .disabled(viewModel.isCapturingSignature)
                }
            }
            .onAppear {
                if !viewModel.hasTechnicianSignature {
                    viewModel.selectSignatureKind(.technician)
                } else if !viewModel.hasCustomerSignature {
                    viewModel.selectSignatureKind(.customer)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(viewModel.isCapturingSignature)
    }

    @ViewBuilder
    private func signatureSection(
        title: String,
        isComplete: Bool,
        strokes: Binding<[[CGPoint]]>,
        isEnabled: Bool,
        saveTitle: String,
        onSave: @escaping () -> Void,
        showCustomerName: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text(title).font(AppFont.subtitle)
            HStack(spacing: AppSpacing.s) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isComplete ? AppColor.success : AppColor.secondaryText)
                Text(isComplete ? "Tamamlandı" : "Bekleniyor")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }

            if showCustomerName, !isComplete {
                TextField("Müşteri adı (opsiyonel)", text: $customerSignerName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!isEnabled)
            }

            if isComplete {
                Text("Kayıtlı imza korunuyor.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            } else {
                SignatureCanvas(
                    title: title,
                    subtitle: showCustomerName && !customerSignerName.isEmpty ? customerSignerName : nil,
                    strokes: strokes
                )
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.45)

                PrimaryButton(
                    title: saveTitle,
                    isLoading: viewModel.isCapturingSignature && isEnabled,
                    isEnabled: isEnabled && !strokes.wrappedValue.isEmpty && !viewModel.isCapturingSignature
                ) {
                    onSave()
                }
            }
        }
    }

    private var editRequestSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    Text("Düzenlenecek Alan").font(AppFont.subtitle)
                    Picker("Alan", selection: Binding(
                        get: { viewModel.selectedEditField },
                        set: { viewModel.selectEditField($0) }
                    )) {
                        ForEach(EditableWorkOrderField.allCases, id: \.self) { field in
                            Text(field.displayName).tag(field)
                        }
                    }
                    .pickerStyle(.menu)

                    InfoRow(
                        title: "Mevcut Değer",
                        value: viewModel.selectedEditFieldCurrentDisplay,
                        systemImage: "text.alignleft"
                    )

                    Text("Yeni Değer").font(AppFont.subtitle)
                    editRequestedValueControl

                    Text("Gerekçe").font(AppFont.subtitle)
                    if let editRequestError = viewModel.editRequestError {
                        Text(editRequestError)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.danger)
                    }
                    TextEditor(text: $editReason)
                        .frame(minHeight: 100)
                        .padding(AppSpacing.s)
                        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
                        .disabled(viewModel.isSubmittingEditRequest)

                    PrimaryButton(
                        title: "Talep Gönder",
                        isLoading: viewModel.isSubmittingEditRequest,
                        isEnabled: !viewModel.isSubmittingEditRequest
                            && !editReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        Task {
                            await viewModel.submitEditRequest(
                                requestedValue: resolvedEditRequestedValue(),
                                reason: editReason
                            )
                            if viewModel.editRequestError == nil {
                                editRequestedValue = ""
                                editReason = ""
                            }
                        }
                    }
                }
                .padding(AppSpacing.l)
            }
            .navigationTitle("Düzenleme Talebi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { viewModel.setEditRequestSheetVisible(false) }
                        .disabled(viewModel.isSubmittingEditRequest)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(viewModel.isSubmittingEditRequest)
    }

    @ViewBuilder
    private var editRequestedValueControl: some View {
        switch viewModel.selectedEditField {
        case .priority:
            Picker("Öncelik", selection: $editRequestedPriority) {
                ForEach(WorkOrderPriority.allCases, id: \.self) { priority in
                    Text(priority.displayName).tag(priority)
                }
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.isSubmittingEditRequest)
        case .scheduledDate:
            DatePicker(
                "Planlanan Tarih",
                selection: $editRequestedDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .disabled(viewModel.isSubmittingEditRequest)
        default:
            TextField("Yeni değer", text: $editRequestedValue, axis: .vertical)
                .lineLimit(2...4)
                .padding(AppSpacing.s)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
                .disabled(viewModel.isSubmittingEditRequest)
        }
    }

    private func prepareEditRequestSheet(for order: WorkOrder) {
        editReason = ""
        editRequestedValue = ""
        editRequestedDate = order.scheduledDate.addingTimeInterval(3600)
        editRequestedPriority = order.priority == .normal ? .high : .normal
    }

    private func resolvedEditRequestedValue() -> String {
        switch viewModel.selectedEditField {
        case .priority:
            return editRequestedPriority.rawValue
        case .scheduledDate:
            return String(editRequestedDate.timeIntervalSince1970)
        default:
            return editRequestedValue
        }
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text(title).font(AppFont.subtitle)
            content()
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
    }
}

/// Per-category gallery picker so each photo section has its own draft state.
private struct CategoryPhotoCaptureControls: View {
    let category: PhotoCategory
    @Binding var draft: Data?
    let isBusy: Bool
    var isCameraPresented: Bool = false
    let onSave: (Data) -> Void
    let onRequestCamera: () -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoadingGallery = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            PhotosPicker(
                selection: $pickerItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label(
                    galleryLabel,
                    systemImage: draft == nil ? "photo.on.rectangle" : "checkmark.circle.fill"
                )
                .font(AppFont.body)
                .frame(maxWidth: .infinity, minHeight: AppSpacing.minimumTouchTarget)
                .foregroundStyle(AppColor.brandPrimary)
            }
            .disabled(isBusy || isLoadingGallery || isCameraPresented)
            .onChange(of: pickerItem) { _, item in
                guard item != nil else { return }
                Task {
                    isLoadingGallery = true
                    defer {
                        isLoadingGallery = false
                        pickerItem = nil
                    }
                    await loadDraft(item)
                }
            }

            if isLoadingGallery {
                HStack(spacing: AppSpacing.s) {
                    ProgressView()
                    Text("Galeri yükleniyor...")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }

            Button(action: onRequestCamera) {
                Label("Kamera ile Çek", systemImage: "camera")
                    .font(AppFont.body)
                    .frame(maxWidth: .infinity, minHeight: AppSpacing.minimumTouchTarget)
                    .foregroundStyle(AppColor.brandPrimary)
            }
            .buttonStyle(.plain)
            .disabled(isBusy || isLoadingGallery || isCameraPresented)

            if let draft, let image = UIImage(data: draft) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            }

            PrimaryButton(
                title: "Kaydet",
                isLoading: isBusy,
                isEnabled: draft != nil && !isBusy && !isLoadingGallery
            ) {
                guard let draft else { return }
                onSave(draft)
            }
        }
    }

    private var galleryLabel: String {
        if isLoadingGallery { return "Galeri yükleniyor..." }
        return draft == nil ? "Galeriden Seç" : "Galeri fotoğrafı seçildi"
    }

    private func loadDraft(_ item: PhotosPickerItem?) async {
        guard let item else {
            draft = nil
            return
        }
        do {
            draft = try await item.loadTransferable(type: Data.self)
        } catch {
            draft = nil
        }
    }
}

#if DEBUG
#Preview("Technician Detail") {
    NavigationStack {
        TechnicianWorkOrderDetailView(
            viewModel: .previewLoaded(),
            onShowReport: { _ in }
        )
    }
}
#endif
