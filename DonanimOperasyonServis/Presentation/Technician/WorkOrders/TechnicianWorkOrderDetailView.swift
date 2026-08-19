import SwiftUI

struct TechnicianWorkOrderDetailView: View {
    @Bindable var viewModel: TechnicianWorkOrderDetailViewModel
    var onShowReport: (WorkOrderID) -> Void

    @State private var noteText = ""
    @State private var selectedPauseReason: PauseReason = .partWaiting
    @State private var customerSignerName = ""

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading:
                LoadingView(message: "Detay yükleniyor...")
            case .submitting:
                LoadingView(message: "Kaydediliyor...")
            case .error(let message):
                ErrorBanner(title: "Hata", message: message) { Task { await viewModel.load() } }
                    .padding(AppSpacing.l)
            case .loaded:
                if let content = viewModel.content {
                    detailBody(content)
                }
            }
        }
        .navigationTitle("İş Emri Detayı")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
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
    }

    @ViewBuilder
    private func detailBody(_ content: TechnicianWorkOrderDetailContent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                header(content)
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
                evidenceSection(content)
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

    private func evidenceSection(_ content: TechnicianWorkOrderDetailContent) -> some View {
        card(title: "Saha Kanıtları") {
            evidenceRow(title: "Servis Notları", count: content.notes.count, systemImage: "note.text") {
                viewModel.setNoteSheetVisible(true)
            }
            evidenceRow(title: "Fotoğraflar", count: content.photos.count, systemImage: "photo") {
                Task { await viewModel.addPhoto(category: .before) }
            }
            evidenceRow(title: "GPS Kayıtları", count: content.locations.count, systemImage: "location") {}
            evidenceRow(title: "İmzalar", count: content.signatures.count, systemImage: "signature") {
                Task { await viewModel.captureSignature(kind: .technician, signerName: nil) }
            }
            if !content.missingRequirements.isEmpty && content.workOrder.status == .inProgress {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Tamamlama Gereksinimleri")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                    ForEach(content.missingRequirements, id: \.self) { item in
                        Text("• \(item.technicianDisplayName)")
                            .font(AppFont.label)
                            .foregroundStyle(AppColor.warning)
                    }
                }
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
            SecondaryButton(title: "Servis Raporu", systemImage: "doc.text") {
                onShowReport(content.workOrder.id)
            }
        } else if content.workOrder.status == .inProgress {
            HStack(spacing: AppSpacing.m) {
                SecondaryButton(title: "Duraklat", systemImage: "pause.circle") {
                    viewModel.setPauseSheetVisible(true)
                }
                PrimaryButton(title: "Tamamla", systemImage: "checkmark.seal") {
                    Task { await viewModel.completeWork() }
                }
            }
        } else if let action = viewModel.primaryAction {
            PrimaryButton(title: action.title, systemImage: action.systemImage) {
                Task { await viewModel.performPrimaryAction() }
            }
        }
    }

    private func evidenceRow(
        title: String,
        count: Int,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text("\(count)").font(AppFont.caption).foregroundStyle(AppColor.secondaryText)
            if contentEditable {
                Button("Ekle", action: action)
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.brandPrimary)
            }
        }
        .frame(minHeight: AppSpacing.minimumTouchTarget)
    }

    private var contentEditable: Bool {
        viewModel.content?.workOrder.status.isTerminal == false
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
                TextEditor(text: $noteText)
                    .frame(minHeight: 120)
                    .padding(AppSpacing.s)
                    .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
                PrimaryButton(title: "Kaydet") {
                    Task { await viewModel.addNote(noteText) }
                }
            }
            .padding(AppSpacing.l)
            .navigationTitle("Not Ekle")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
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
