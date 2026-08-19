import SwiftUI

struct OperatorWorkOrderDetailView: View {
    @Bindable var viewModel: OperatorWorkOrderDetailViewModel
    var onShowReport: (WorkOrderID) -> Void
    var onShowEditRequests: () -> Void

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading:
                LoadingView(message: "Detay yükleniyor...")

            case .error(let message):
                ErrorBanner(title: "Detay yüklenemedi", message: message) {
                    Task { await viewModel.load() }
                }
                .padding(AppSpacing.l)

            case .loaded:
                if let content = viewModel.content {
                    detailContent(content)
                }
            }
        }
        .navigationTitle("İş Emri Detayı")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .alert(
            "Düzenleme",
            isPresented: Binding(
                get: { viewModel.editBlockedMessage != nil },
                set: { if !$0 { viewModel.clearEditMessage() } }
            )
        ) {
            Button("Düzenleme Talepleri") { onShowEditRequests() }
            Button("Tamam", role: .cancel) { viewModel.clearEditMessage() }
        } message: {
            Text(viewModel.editBlockedMessage ?? "")
        }
    }

    @ViewBuilder
    private func detailContent(_ content: OperatorWorkOrderDetailContent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                headerSection(content)
                statusFlowSection(content.workOrder)
                if content.pendingSyncCount > 0 {
                    syncBanner
                }
                customerSection(content)
                deviceSection(content.workOrder)
                workSection(content)
                if !content.notes.isEmpty {
                    notesSection(content.notes)
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

    private var syncBanner: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(AppColor.info)
            Text("Kaydedildi · Senkronizasyon bekliyor")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(AppColor.info.opacity(0.08))
        )
    }

    private func customerSection(_ content: OperatorWorkOrderDetailContent) -> some View {
        detailCard(title: "Müşteri Bilgileri") {
            InfoRow(title: "Müşteri", value: content.customer.name, systemImage: "building.2")
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
            SecondaryButton(title: "Takip Et", systemImage: "location") {}
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
            onShowEditRequests: {}
        )
    }
}
#endif
