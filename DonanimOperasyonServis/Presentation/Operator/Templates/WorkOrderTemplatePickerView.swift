import SwiftUI

struct WorkOrderTemplatePickerView: View {
    @Bindable var listViewModel: WorkOrderTemplateListViewModel
    let actor: User
    let service: OperatorWorkOrderTemplateService
    var onSelect: (WorkOrderTemplate) -> Void
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch listViewModel.phase {
                case .loading:
                    LoadingView(message: "Şablonlar yükleniyor...")
                case .empty:
                    EmptyState(
                        systemImage: "doc.on.doc",
                        title: "Şablon bulunamadı",
                        message: "Sık kullandığınız iş emirleri için yeni bir şablon oluşturun."
                    )
                case .error(let message):
                    ErrorBanner(title: "Şablonlar yüklenemedi", message: message)
                case .loaded:
                    ScrollView {
                        LazyVStack(spacing: AppSpacing.m) {
                            ForEach(listViewModel.templates) { template in
                                templateRow(template)
                            }
                        }
                        .padding(AppSpacing.l)
                    }
                }
            }
            .navigationTitle("Şablondan Başla")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat", action: onDismiss)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        listViewModel.openCreateEditor()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Yeni şablon")
                }
            }
            .task { await listViewModel.load() }
            .sheet(isPresented: $listViewModel.showsEditor) {
                WorkOrderTemplateEditorView(
                    viewModel: WorkOrderTemplateEditorViewModel(
                        actor: actor,
                        service: service,
                        editingTemplate: listViewModel.editorTemplate
                    ),
                    onSaved: {
                        listViewModel.showsEditor = false
                        Task { await listViewModel.load() }
                    },
                    onCancel: { listViewModel.showsEditor = false }
                )
            }
            .alert(
                "Şablonu Sil",
                isPresented: Binding(
                    get: { listViewModel.pendingDeleteTemplate != nil },
                    set: { if !$0 { listViewModel.cancelDelete() } }
                )
            ) {
                Button("İptal", role: .cancel) { listViewModel.cancelDelete() }
                Button("Sil", role: .destructive) {
                    Task { await listViewModel.confirmDelete() }
                }
            } message: {
                if let template = listViewModel.pendingDeleteTemplate {
                    Text("'\(template.name)' şablonu kalıcı olarak silinecek.")
                }
            }
        }
    }

    @ViewBuilder
    private func templateRow(_ template: WorkOrderTemplate) -> some View {
        VStack(spacing: AppSpacing.s) {
            WorkOrderTemplateCard(
                data: WorkOrderTemplatePresentationMapping.cardData(from: template),
                action: { onSelect(template) }
            )

            HStack(spacing: AppSpacing.m) {
                Button("Düzenle") { listViewModel.openEditEditor(template) }
                Button("Kopyala") { Task { await listViewModel.duplicate(template) } }
                Spacer()
                Button("Sil", role: .destructive) { listViewModel.requestDelete(template) }
            }
            .font(AppFont.label)
            .disabled(listViewModel.isPerformingMutation)
        }
    }
}

struct WorkOrderTemplateEditorView: View {
    @Bindable var viewModel: WorkOrderTemplateEditorViewModel
    var onSaved: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(AppColor.danger)
                            .font(AppFont.caption)
                    }
                }

                Section("Şablon Bilgileri") {
                    TextField("Şablon adı", text: $viewModel.name)
                    TextField("Kısa açıklama", text: $viewModel.summary)
                }

                Section("İş Bilgileri") {
                    Picker("İş Türü", selection: $viewModel.workType) {
                        ForEach(WorkType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    Picker("Cihaz Türü", selection: $viewModel.deviceCategory) {
                        ForEach(DeviceCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    Picker("Öncelik", selection: $viewModel.priority) {
                        ForEach(WorkOrderPriority.allCases, id: \.self) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                }

                Section("Varsayılan Cihaz (isteğe bağlı)") {
                    TextField("Marka", text: $viewModel.deviceBrand)
                    TextField("Model", text: $viewModel.deviceModel)
                }

                Section("Varsayılan Açıklama (isteğe bağlı)") {
                    TextField("Açıklama / not", text: $viewModel.issueDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(viewModel.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç", action: onCancel)
                        .disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        Task {
                            if await viewModel.save() != nil {
                                onSaved()
                            }
                        }
                    }
                    .disabled(viewModel.isSaving || viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Template Picker") {
    let deps = DIContainer.mock().makeOperatorDependencies()
    WorkOrderTemplatePickerView(
        listViewModel: WorkOrderTemplateListViewModel(
            actor: OperatorPreviewData.operatorUser,
            service: deps.workOrderTemplateService
        ),
        actor: OperatorPreviewData.operatorUser,
        service: deps.workOrderTemplateService,
        onSelect: { _ in },
        onDismiss: {}
    )
}
#endif
