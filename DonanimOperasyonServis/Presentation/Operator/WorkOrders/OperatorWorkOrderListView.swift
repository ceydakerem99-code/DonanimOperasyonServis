import SwiftUI

struct OperatorWorkOrderListView: View {
    @Bindable var viewModel: OperatorWorkOrderListViewModel
    var onSelectWorkOrder: (WorkOrderID) -> Void
    var onShowEditRequests: () -> Void
    var onShowConflicts: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.m) {
                searchField
                filterChips
                if viewModel.isSelectionMode {
                    selectionToolbar
                }
                if viewModel.priorityFilter == .urgent || viewModel.dashboardScope == .urgent {
                    scopeBanner(title: "Filtre: Acil") {
                        Task { await viewModel.clearDashboardScope() }
                    }
                } else if viewModel.dashboardScope == .open {
                    scopeBanner(title: "Filtre: Açık İşler") {
                        Task { await viewModel.clearDashboardScope() }
                    }
                } else if viewModel.dashboardScope == .overdue {
                    scopeBanner(title: "Filtre: Geciken") {
                        Task { await viewModel.clearDashboardScope() }
                    }
                } else if viewModel.dashboardScope == .paused {
                    scopeBanner(title: "Filtre: Beklemede") {
                        Task { await viewModel.clearDashboardScope() }
                    }
                } else if viewModel.dashboardScope == .completed {
                    scopeBanner(title: "Filtre: Tamamlanan") {
                        Task { await viewModel.clearDashboardScope() }
                    }
                }

                AsyncLoadContainerView(
                    isLoading: viewModel.phase == .loading,
                    showsLoadingIndicator: viewModel.showsLoadingIndicator,
                    hasCachedContent: viewModel.hasCachedContent,
                    errorMessage: AsyncLoadPhaseParsing.errorMessage(viewModel.phase),
                    isEmpty: viewModel.phase == .empty,
                    loadingMessage: "İş emirleri yükleniyor...",
                    errorTitle: "Liste yüklenemedi",
                    onRetry: { Task { await viewModel.load() } },
                    content: {
                        ForEach(viewModel.cards) { card in
                            workOrderRow(for: card)
                        }
                    },
                    empty: {
                        EmptyState(
                            systemImage: "doc.text.magnifyingglass",
                            title: "İş emri bulunamadı",
                            message: "Filtreleri değiştirin veya yeni iş emri oluşturun."
                        )
                    }
                )
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, viewModel.canPerformBulkActions ? AppSpacing.xxl : AppSpacing.xl)
        }
        .navigationTitle("İş Emirleri")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if viewModel.isSelectionMode {
                    Button("Bitti") {
                        viewModel.setSelectionMode(false)
                    }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    viewModel.setSelectionMode(!viewModel.isSelectionMode)
                } label: {
                    Image(systemName: viewModel.isSelectionMode ? "checkmark.circle.fill" : "checklist")
                }
                .accessibilityLabel(viewModel.isSelectionMode ? "Seçim modunu kapat" : "Seçim modu")
                Button(action: onShowConflicts) {
                    Image(systemName: "exclamationmark.triangle")
                }
                .accessibilityLabel("Senkron Çakışmaları")
                Button(action: onShowEditRequests) {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .accessibilityLabel("Düzenleme Talepleri")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.canPerformBulkActions {
                bulkActionBar
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .onChange(of: viewModel.searchText) { _, _ in
            Task { await viewModel.applyLocalSearch() }
        }
        .onAppear {
            Task { await viewModel.load() }
        }
        .sheet(isPresented: $viewModel.showsBulkAssignSheet) {
            bulkAssignSheet
        }
        .sheet(isPresented: $viewModel.showsBulkPrioritySheet) {
            bulkPrioritySheet
        }
        .sheet(isPresented: $viewModel.showsBulkScheduleSheet) {
            bulkScheduleSheet
        }
        .alert(
            "Toplu İşlem Sonucu",
            isPresented: Binding(
                get: { viewModel.bulkResultSummary != nil },
                set: { if !$0 { viewModel.dismissBulkResult() } }
            )
        ) {
            Button("Tamam", role: .cancel) { viewModel.dismissBulkResult() }
        } message: {
            Text(viewModel.bulkResultDetailMessage)
        }
    }

    @ViewBuilder
    private func workOrderRow(for card: WorkOrderCardData) -> some View {
        let orderId = WorkOrderID(card.id)
        if viewModel.isSelectionMode {
            HStack(alignment: .top, spacing: AppSpacing.s) {
                selectionCheckbox(for: orderId)
                WorkOrderCard(data: card) {
                    viewModel.toggleSelection(orderId)
                }
            }
        } else {
            WorkOrderCard(data: card) {
                onSelectWorkOrder(orderId)
            }
        }
    }

    private func selectionCheckbox(for orderId: WorkOrderID) -> some View {
        let selectable = viewModel.canSelect(orderId)
        let selected = viewModel.isSelected(orderId)
        return Button {
            viewModel.toggleSelection(orderId)
        } label: {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(
                    selectable
                        ? (selected ? AppColor.brandPrimary : AppColor.secondaryText)
                        : AppColor.divider
                )
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .padding(.top, AppSpacing.m)
        .accessibilityLabel(selected ? "Seçili" : "Seçili değil")
    }

    private var selectionToolbar: some View {
        HStack {
            Text(viewModel.selectionSummaryText)
                .font(AppFont.label)
                .foregroundStyle(AppColor.primaryText)
            Spacer()
            Button("Tümünü Seç") {
                viewModel.selectAllEligible()
            }
            .font(AppFont.label)
            .foregroundStyle(AppColor.brandPrimary)
            .disabled(viewModel.eligibleSelectableCount == 0)
            Button("Temizle") {
                viewModel.clearSelection()
            }
            .font(AppFont.label)
            .foregroundStyle(AppColor.brandPrimary)
            .disabled(viewModel.selectedCount == 0)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private var bulkActionBar: some View {
        VStack(spacing: AppSpacing.s) {
            Text(viewModel.selectionSummaryText)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            HStack(spacing: AppSpacing.s) {
                bulkActionButton(title: "Teknisyen Ata", systemImage: "person.badge.key") {
                    Task { await viewModel.prepareBulkAssignSheet() }
                }
                bulkActionButton(title: "Öncelik", systemImage: "exclamationmark.triangle") {
                    viewModel.showsBulkPrioritySheet = true
                }
                bulkActionButton(title: "Tarih", systemImage: "calendar") {
                    viewModel.showsBulkScheduleSheet = true
                }
            }
        }
        .padding(AppSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(AppColor.elevatedSurface)
                .shadow(color: .black.opacity(0.08), radius: 8, y: -2)
        )
        .padding(.horizontal, AppSpacing.l)
    }

    private func bulkActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: systemImage)
                Text(title)
                    .font(AppFont.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.s)
            .foregroundStyle(AppColor.brandPrimary)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                    .fill(AppColor.brandPrimary.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isPerformingBulkMutation)
    }

    private var bulkAssignSheet: some View {
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
                            Text("\(viewModel.selectedCount) iş emrine atanacak teknisyen")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                            TextField("Teknisyen ara...", text: $viewModel.technicianSearchText)
                                .padding(AppSpacing.m)
                                .background(
                                    RoundedRectangle(cornerRadius: AppRadius.card)
                                        .fill(AppColor.elevatedSurface)
                                )
                            ForEach(viewModel.filteredAssignableTechnicians) { tech in
                                TechnicianAssignmentOptionCard(
                                    title: tech.fullName,
                                    workingStatus: viewModel.workingStatus(for: tech),
                                    workload: viewModel.workload(for: tech),
                                    isRecommended: viewModel.isRecommended(tech),
                                    isSelected: viewModel.selectedTechnicianId == tech.id,
                                    isDisabled: viewModel.isPerformingBulkMutation,
                                    locationLabel: viewModel.locationLabel(for: tech),
                                    action: { viewModel.selectTechnicianForBulkAssign(tech) }
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
                    Button("Vazgeç") { viewModel.showsBulkAssignSheet = false }
                        .disabled(viewModel.isPerformingBulkMutation)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(
                    title: "Onayla",
                    isLoading: viewModel.isPerformingBulkMutation,
                    isEnabled: viewModel.selectedTechnicianId != nil && !viewModel.isPerformingBulkMutation
                ) {
                    Task { await viewModel.confirmBulkAssign() }
                }
                .padding(AppSpacing.l)
                .background(AppColor.brandSurface)
            }
        }
    }

    private var bulkPrioritySheet: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(viewModel.selectedCount) iş emrinin önceliği değiştirilecek")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                Section("Öncelik") {
                    ForEach(WorkOrderPriority.allCases, id: \.self) { priority in
                        Button {
                            viewModel.selectBulkPriority(priority)
                        } label: {
                            HStack {
                                PriorityBadge(priority: WorkOrderPresentationMapping.appPriority(from: priority))
                                Spacer()
                                if viewModel.bulkPrioritySelection == priority {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppColor.brandPrimary)
                                }
                            }
                        }
                        .disabled(viewModel.isPerformingBulkMutation)
                    }
                }
            }
            .navigationTitle("Öncelik Değiştir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { viewModel.showsBulkPrioritySheet = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(
                    title: "Onayla",
                    isLoading: viewModel.isPerformingBulkMutation,
                    isEnabled: !viewModel.isPerformingBulkMutation
                ) {
                    Task { await viewModel.confirmBulkPriorityUpdate() }
                }
                .padding(AppSpacing.l)
                .background(AppColor.brandSurface)
            }
        }
    }

    private var bulkScheduleSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(viewModel.selectedCount) iş emrinin planlanan tarihi değiştirilecek")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                Section("Planlama") {
                    DatePicker("Planlanan Tarih", selection: $viewModel.bulkScheduledDate, displayedComponents: .date)
                    DatePicker("Başlangıç", selection: $viewModel.bulkScheduledStart, displayedComponents: .hourAndMinute)
                    DatePicker("Bitiş", selection: $viewModel.bulkScheduledEnd, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("Tarih Değiştir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { viewModel.showsBulkScheduleSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Onayla") {
                        Task { await viewModel.confirmBulkScheduleUpdate() }
                    }
                    .disabled(viewModel.isPerformingBulkMutation)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColor.secondaryText)
            TextField("Ara...", text: $viewModel.searchText)
                .font(AppFont.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(AppSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(AppColor.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .strokeBorder(AppColor.divider, lineWidth: 1)
        )
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.s) {
                ForEach(OperatorWorkOrderListFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
        }
    }

    private func filterChip(_ filter: OperatorWorkOrderListFilter) -> some View {
        let selected = viewModel.selectedFilter == filter
        return Button {
            Task { await viewModel.selectFilter(filter) }
        } label: {
            Text(filter.title)
                .font(AppFont.label)
                .foregroundStyle(selected ? AppColor.onPrimary : AppColor.primaryText)
                .padding(.horizontal, AppSpacing.m)
                .padding(.vertical, AppSpacing.s)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? AppColor.brandPrimary : AppColor.elevatedSurface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(AppColor.divider, lineWidth: selected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(filter.title) filtresi"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func scopeBanner(title: String, onClear: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            Spacer()
            Button("Temizle", action: onClear)
                .font(AppFont.label)
                .foregroundStyle(AppColor.brandPrimary)
        }
    }
}

#if DEBUG
#Preview("WorkOrder List — loaded") {
    NavigationStack {
        OperatorWorkOrderListView(
            viewModel: .previewLoaded(),
            onSelectWorkOrder: { _ in },
            onShowEditRequests: {},
            onShowConflicts: {}
        )
    }
}

#Preview("WorkOrder List — empty") {
    NavigationStack {
        OperatorWorkOrderListView(
            viewModel: .previewEmpty(),
            onSelectWorkOrder: { _ in },
            onShowEditRequests: {},
            onShowConflicts: {}
        )
    }
}
#endif
