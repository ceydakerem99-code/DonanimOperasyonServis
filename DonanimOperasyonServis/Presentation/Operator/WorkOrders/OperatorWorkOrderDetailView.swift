import SwiftUI

struct OperatorWorkOrderDetailView: View {
    @Bindable var viewModel: OperatorWorkOrderDetailViewModel
    var onShowReport: (WorkOrderID) -> Void
    var onShowTracking: (WorkOrderID) -> Void
    var onShowEditRequests: () -> Void
    var onShowCustomer: (CustomerID) -> Void = { _ in }

    var body: some View {
        Group {
            AsyncLoadContainerView(
                isLoading: viewModel.phase == .loading,
                showsLoadingIndicator: viewModel.showsLoadingIndicator,
                hasCachedContent: viewModel.hasCachedContent,
                errorMessage: AsyncLoadPhaseParsing.errorMessage(viewModel.phase),
                isEmpty: false,
                loadingMessage: "Detay yükleniyor...",
                errorTitle: "Detay yüklenemedi",
                onRetry: { Task { await viewModel.load() } }
            ) {
                if let content = viewModel.content {
                    detailContent(content)
                }
            }
        }
        .id(viewModel.workOrderId)
        .navigationTitle("İş Emri Detayı")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.startLoad() }
        .onDisappear { viewModel.stopLoad() }
        .sheet(
            isPresented: Binding(
                get: { viewModel.showsAssignSheet },
                set: { if !$0 { viewModel.dismissAssignSheet() } }
            )
        ) {
            assignTechnicianSheet
        }
        .alert(
            "Düzenleme",
            isPresented: Binding(
                get: { viewModel.editBlockedMessage != nil },
                set: { if !$0 { viewModel.clearEditMessage() } }
            )
        ) {
            if viewModel.offersEditRequestNavigation {
                Button("Düzenleme Talepleri") { onShowEditRequests() }
            }
            Button("Tamam", role: .cancel) { viewModel.clearEditMessage() }
        } message: {
            Text(viewModel.editBlockedMessage ?? "")
        }
        .alert(
            "Teknisyen Atama",
            isPresented: Binding(
                get: { viewModel.assignmentError != nil },
                set: { if !$0 { viewModel.clearAssignmentError() } }
            )
        ) {
            Button("Tamam", role: .cancel) { viewModel.clearAssignmentError() }
        } message: {
            Text(viewModel.assignmentError ?? "")
        }
    }

    @ViewBuilder
    private func detailContent(_ content: OperatorWorkOrderDetailContent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                headerSection(content)
                if let timeStatus = WorkOrderPresentationMapping.timeStatus(for: content.workOrder) {
                    WorkOrderTimeStatusDetailBanner(
                        status: timeStatus,
                        plannedScheduleLabel: WorkOrderPresentationMapping.plannedScheduleLabel(for: content.workOrder)
                    )
                }
                statusFlowSection(content.workOrder)
                customerSection(content)
                deviceSection(content.workOrder)
                workSection(content)
                if !content.notes.isEmpty {
                    notesSection(content.notes)
                }
                if !content.photos.isEmpty {
                    photosPreviewSection(content)
                }
                if !content.signatures.isEmpty {
                    signaturesPreviewSection(content)
                }
                timelineSection(content)
                actionButtons(content)
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
    }

    private func headerSection(_ content: OperatorWorkOrderDetailContent) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(content.workOrder.workOrderNumber)
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.primaryText)
                PriorityBadge(priority: WorkOrderPresentationMapping.appPriority(from: content.workOrder.priority))
            }
            Spacer()
            StatusChip(status: WorkOrderPresentationMapping.appStatus(from: content.workOrder.status))
        }
    }

    private func statusFlowSection(_ order: WorkOrder) -> some View {
        StepIndicator(
            currentStep: WorkOrderPresentationMapping.statusStepIndex(for: order.status),
            totalSteps: 6,
            titles: WorkOrderPresentationMapping.statusFlowTitles
        )
        .padding(.vertical, AppSpacing.s)
    }

    private func customerSection(_ content: OperatorWorkOrderDetailContent) -> some View {
        detailCard(title: "Müşteri Bilgileri") {
            Button {
                onShowCustomer(content.customer.id)
            } label: {
                HStack {
                    InfoRow(title: "Müşteri", value: content.customer.name, systemImage: "building.2")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Müşteri detayını aç")
            if let contact = content.customer.contactPersonName {
                InfoRow(title: "Yetkili", value: contact, systemImage: "person")
            }
            if let phone = content.customer.phoneNumber?.rawValue, !phone.isEmpty {
                InfoRow(title: "Telefon", value: phone, systemImage: "phone")
            }
            InfoRow(title: "Adres", value: content.customer.address, systemImage: "mappin.and.ellipse")
        }
    }

    private func deviceSection(_ order: WorkOrder) -> some View {
        detailCard(title: "Cihaz Bilgileri") {
            InfoRow(title: "Cihaz Türü", value: order.deviceCategory.displayName, systemImage: "creditcard")
            InfoRow(title: "Marka / Model", value: "\(order.deviceBrand) \(order.deviceModel)", systemImage: "wrench.and.screwdriver")
            InfoRow(title: "Seri No", value: order.serialNumber, systemImage: "number")
        }
    }

    private func workSection(_ content: OperatorWorkOrderDetailContent) -> some View {
        detailCard(title: "İş Bilgileri") {
            InfoRow(title: "İş Türü", value: content.workOrder.workType.displayName, systemImage: "briefcase")
            if let description = content.workOrder.issueDescription, !description.isEmpty {
                InfoRow(title: "Açıklama", value: description, systemImage: "text.alignleft")
            }
            InfoRow(
                title: "Planlanan Zaman",
                value: WorkOrderPresentationMapping.formatDateTime(content.workOrder.scheduledDate),
                systemImage: "calendar"
            )
            InfoRow(title: "Servis Yetkilisi", value: content.technicianName, systemImage: "person.crop.circle")
        }
    }

    private func notesSection(_ notes: [WorkOrderNote]) -> some View {
        detailCard(title: "Notlar") {
            ForEach(notes, id: \.id) { note in
                InfoRow(
                    title: WorkOrderPresentationMapping.formatTime(note.createdAt),
                    value: note.text,
                    systemImage: "note.text"
                )
            }
        }
    }

    private func timelineSection(_ content: OperatorWorkOrderDetailContent) -> some View {
        detailCard(title: "Zaman Çizelgesi") {
            if content.timeline.isEmpty {
                Text("Henüz durum geçmişi yok.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            } else {
                ForEach(Array(content.timeline.enumerated()), id: \.element.id) { index, entry in
                    TimelineItem(
                        time: WorkOrderPresentationMapping.formatTime(entry.occurredAt),
                        title: entry.toStatus.displayName,
                        subtitle: entry.fromStatus?.displayName,
                        accentColor: WorkOrderPresentationMapping.appStatus(from: entry.toStatus).accentColor,
                        systemImage: WorkOrderPresentationMapping.appStatus(from: entry.toStatus).symbolName,
                        showsConnector: index < content.timeline.count - 1
                    )
                }
            }
        }
    }

    private func photosPreviewSection(_ content: OperatorWorkOrderDetailContent) -> some View {
        detailCard(title: "Fotoğraflar (\(content.photoCount))") {
            if let firstPhoto = content.photos.first {
                DetailPhotoThumbnail(
                    photo: firstPhoto,
                    mediaLoader: viewModel.mediaLoader
                )
            }
            if content.photos.count > 1 {
                Text("+\(content.photos.count - 1) fotoğraf daha")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
            Button {
                onShowReport(content.workOrder.id)
            } label: {
                Label("Rapora Git", systemImage: "arrow.right.circle")
                    .font(AppFont.label)
            }
        }
    }

    private func signaturesPreviewSection(_ content: OperatorWorkOrderDetailContent) -> some View {
        detailCard(title: "İmzalar (\(content.signatureCount))") {
            if let firstSig = content.signatures.first {
                DetailSignatureThumbnail(
                    signature: firstSig,
                    mediaLoader: viewModel.mediaLoader
                )
            }
            if content.signatures.count > 1 {
                Text("+\(content.signatures.count - 1) imza daha")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
            Button {
                onShowReport(content.workOrder.id)
            } label: {
                Label("Rapora Git", systemImage: "arrow.right.circle")
                    .font(AppFont.label)
            }
        }
    }

    private func actionButtons(_ content: OperatorWorkOrderDetailContent) -> some View {
        VStack(spacing: AppSpacing.m) {
            HStack(spacing: AppSpacing.m) {
                SecondaryButton(title: "Düzenle", systemImage: "pencil") {
                    viewModel.attemptEdit()
                }
                SecondaryButton(title: "Rapor", systemImage: "doc.text") {
                    onShowReport(content.workOrder.id)
                }
            }
            if viewModel.canAssignTechnician {
                SecondaryButton(title: viewModel.assignActionTitle, systemImage: "person.badge.key") {
                    viewModel.attemptAssign()
                }
            }
            SecondaryButton(title: "Takip Et", systemImage: "location") {
                onShowTracking(content.workOrder.id)
            }
        }
    }

    private var assignTechnicianSheet: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingTechnicians {
                    LoadingView(message: "Teknisyenler yükleniyor...")
                } else if viewModel.filteredAssignableTechnicians.isEmpty {
                    EmptyState(
                        systemImage: "person.crop.circle.badge.questionmark",
                        title: viewModel.assignableTechnicians.isEmpty ? "Aktif teknisyen yok" : "Sonuç bulunamadı",
                        message: viewModel.assignableTechnicians.isEmpty
                            ? "Atama için aktif bir servis yetkilisi bulunamadı."
                            : "Arama kriterlerinize uygun teknisyen bulunamadı."
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppSpacing.m) {
                            if let current = viewModel.content?.technicianName {
                                Text("Mevcut: \(current)")
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.secondaryText)
                            }
                            TextField("Teknisyen ara...", text: $viewModel.technicianSearchText)
                                .padding(AppSpacing.m)
                                .background(
                                    RoundedRectangle(cornerRadius: AppRadius.card)
                                        .fill(AppColor.elevatedSurface)
                                )
                            Text("Yeni servis yetkilisi seçin")
                                .font(AppFont.subtitle)
                                .foregroundStyle(AppColor.primaryText)

                            ForEach(viewModel.filteredAssignableTechnicians) { tech in
                                TechnicianAssignmentOptionCard(
                                    title: tech.fullName,
                                    workingStatus: viewModel.workingStatus(for: tech),
                                    workload: viewModel.workload(for: tech),
                                    isRecommended: viewModel.isRecommended(tech),
                                    isSelected: viewModel.selectedTechnicianId == tech.id,
                                    isDisabled: viewModel.isAssigning,
                                    locationLabel: viewModel.locationLabel(for: tech),
                                    action: { viewModel.selectTechnicianForAssign(tech) }
                                )
                            }
                        }
                        .padding(AppSpacing.l)
                    }
                }
            }
            .navigationTitle("Teknisyen Ata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { viewModel.dismissAssignSheet() }
                        .disabled(viewModel.isAssigning)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(
                    title: "Onayla",
                    isLoading: viewModel.isAssigning,
                    isEnabled: viewModel.selectedTechnicianId != nil && !viewModel.isAssigning
                ) {
                    Task { await viewModel.confirmAssignment() }
                }
                .padding(AppSpacing.l)
                .background(AppColor.brandSurface)
            }
            .task {
                await viewModel.loadAssignableTechnicians()
            }
        }
    }

    private func detailCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text(title)
                .font(AppFont.subtitle)
                .foregroundStyle(AppColor.primaryText)
            content()
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(AppColor.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .strokeBorder(AppColor.divider, lineWidth: 1)
        )
    }
}

#if DEBUG
#Preview("WorkOrder Detail") {
    NavigationStack {
        OperatorWorkOrderDetailView(
            viewModel: .previewLoaded(),
            onShowReport: { _ in },
            onShowTracking: { _ in },
            onShowEditRequests: {}
        )
    }
}
#endif
