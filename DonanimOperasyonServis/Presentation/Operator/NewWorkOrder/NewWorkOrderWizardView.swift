import SwiftUI

struct NewWorkOrderWizardView: View {
    @Bindable var viewModel: NewWorkOrderWizardViewModel
    var onFinished: (WorkOrderID) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StepIndicator(
                currentStep: viewModel.currentStep,
                totalSteps: NewWorkOrderWizardViewModel.totalSteps,
                titles: NewWorkOrderWizardViewModel.stepTitles
            )
            .padding(.horizontal, AppSpacing.l)
            .padding(.vertical, AppSpacing.m)

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    if case .error(let message) = viewModel.phase {
                        ErrorBanner(title: "Form hatası", message: message)
                    }
                    if let message = viewModel.templateUnavailableMessage {
                        ErrorBanner(title: "Şablon", message: message)
                    }
                    if viewModel.currentStep == 1 {
                        templateStartSection
                    }
                    if let appliedName = viewModel.appliedTemplateName {
                        appliedTemplateBanner(appliedName)
                    }

                    stepContent
                }
                .padding(.horizontal, AppSpacing.l)
                .padding(.bottom, AppSpacing.xl)
            }

            footerButtons
        }
        .navigationTitle("Yeni İş Emri")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("İptal", action: onCancel)
            }
        }
        .task { await viewModel.loadSelections() }
        .onChange(of: viewModel.phase) { _, phase in
            if case .success(let id) = phase {
                onFinished(id)
            }
        }
        .sheet(isPresented: $viewModel.showsTemplatePicker) {
            WorkOrderTemplatePickerView(
                listViewModel: viewModel.templateListViewModel,
                actor: viewModel.templatePickerActor,
                service: viewModel.templatePickerService,
                onSelect: { viewModel.applyTemplate($0) },
                onDismiss: { viewModel.showsTemplatePicker = false }
            )
        }
    }

    private var templateStartSection: some View {
        SecondaryButton(title: "Şablondan Başla", systemImage: "doc.on.doc") {
            viewModel.openTemplatePicker()
        }
    }

    private func appliedTemplateBanner(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Label("Şablon: \(name)", systemImage: "doc.on.doc")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                Spacer()
                Button("Temizle") { viewModel.clearAppliedTemplate() }
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.brandPrimary)
            }
            if let summary = viewModel.appliedTemplateFieldSummary {
                Text(summary)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.primaryText)
            }
        }
        .padding(AppSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(AppColor.brandPrimary.opacity(0.08))
        )
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case 1: workTypeStep
        case 2: customerStep
        case 3: deviceStep
        case 4: priorityStep
        case 5: technicianStep
        default: summaryStep
        }
    }

    private var workTypeStep: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("İş türünü seçin")
                .font(AppFont.subtitle)
            if let error = viewModel.fieldErrors[.workType] {
                fieldError(error)
            }
            ForEach(WorkType.allCases, id: \.self) { type in
                selectionCard(
                    title: type.displayName,
                    systemImage: workTypeIcon(type),
                    selected: viewModel.draft.workType == type
                ) {
                    viewModel.selectWorkType(type)
                }
            }
        }
    }

    private var customerStep: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Müşteri seçin")
                .font(AppFont.subtitle)
            if let error = viewModel.fieldErrors[.customer] {
                fieldError(error)
            }
            TextField("Müşteri ara...", text: Binding(
                get: { viewModel.customerSearchText },
                set: { newValue in Task { await viewModel.updateCustomerSearch(newValue) } }
            ))
            .padding(AppSpacing.m)
            .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))

            PrimaryButton(title: "Yeni Müşteri Ekle", systemImage: "plus.circle") {
                viewModel.openCreateCustomer()
            }

            if viewModel.customers.isEmpty {
                EmptyState(
                    systemImage: "building.2",
                    title: "Kayıtlı müşteri yok",
                    message: "Devam etmek için yeni müşteri ekleyin."
                )
            } else {
                ForEach(viewModel.customers) { customer in
                    selectionCard(
                        title: customer.name,
                        subtitle: customer.address,
                        systemImage: "building.2",
                        selected: viewModel.draft.customer?.id == customer.id
                    ) {
                        viewModel.selectCustomer(customer)
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showsCreateCustomer) {
            NavigationStack {
                CreateCustomerFormView(viewModel: viewModel) {
                    viewModel.showsCreateCustomer = false
                }
            }
        }
    }

    private var deviceStep: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Cihaz bilgileri")
                .font(AppFont.subtitle)

            Picker("Cihaz Türü", selection: $viewModel.draft.deviceCategory) {
                ForEach(DeviceCategory.allCases, id: \.self) { category in
                    Text(category.displayName).tag(category)
                }
            }
            .pickerStyle(.menu)

            formField(title: "Marka", text: $viewModel.draft.deviceBrand, error: viewModel.fieldErrors[.deviceBrand])
            formField(title: "Model", text: $viewModel.draft.deviceModel, error: viewModel.fieldErrors[.deviceModel])
            formField(title: "Seri No", text: $viewModel.draft.serialNumber, error: viewModel.fieldErrors[.serialNumber])

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Arıza / Talep Açıklaması")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                TextEditor(text: $viewModel.draft.issueDescription)
                    .frame(minHeight: 100)
                    .padding(AppSpacing.s)
                    .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            }
        }
    }

    private var priorityStep: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Öncelik ve zaman")
                .font(AppFont.subtitle)

            HStack(spacing: AppSpacing.s) {
                ForEach(WorkOrderPriority.allCases, id: \.self) { priority in
                    priorityButton(priority)
                }
            }

            DatePicker("Planlanan Tarih", selection: $viewModel.draft.scheduledDate, displayedComponents: .date)
            DatePicker("Başlangıç", selection: $viewModel.draft.scheduledStart, displayedComponents: .hourAndMinute)
            DatePicker("Bitiş", selection: $viewModel.draft.scheduledEnd, displayedComponents: .hourAndMinute)
        }
    }

    private var technicianStep: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Servis yetkilisi seçin")
                .font(AppFont.subtitle)
            if let error = viewModel.fieldErrors[.technician] {
                fieldError(error)
            }
            TextField("Teknisyen ara...", text: $viewModel.technicianSearchText)
                .padding(AppSpacing.m)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))

            ForEach(viewModel.filteredTechnicians) { tech in
                TechnicianAssignmentOptionCard(
                    title: tech.fullName,
                    workingStatus: viewModel.workingStatus(for: tech),
                    workload: viewModel.workload(for: tech),
                    isRecommended: viewModel.isRecommended(tech),
                    isSelected: viewModel.draft.technician?.id == tech.id,
                    locationLabel: viewModel.locationLabel(for: tech),
                    action: { viewModel.selectTechnician(tech) }
                )
            }
        }
    }

    private var summaryStep: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Özet")
                .font(AppFont.subtitle)

            if viewModel.draft.priority == .urgent {
                Label("Acil öncelikli iş emri", systemImage: "exclamationmark.triangle.fill")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.priorityUrgent)
            }

            summaryRow("İş Türü", viewModel.draft.workType?.displayName)
            summaryRow("Müşteri", viewModel.draft.customer?.name)
            summaryRow("Cihaz", viewModel.draft.deviceCategory.displayName)
            summaryRow("Marka / Model", "\(viewModel.draft.deviceBrand) \(viewModel.draft.deviceModel)")
            summaryRow("Seri No", viewModel.draft.serialNumber)
            summaryRow("Öncelik", viewModel.draft.priority.displayName)
            summaryRow("Planlanan", WorkOrderPresentationMapping.formatDateTime(viewModel.draft.scheduledDate))
            summaryRow("Teknisyen", viewModel.draft.technician?.fullName)
        }
    }

    private var footerButtons: some View {
        HStack(spacing: AppSpacing.m) {
            if viewModel.currentStep > 1 {
                SecondaryButton(title: "Geri") { viewModel.previousStep() }
            }
            if viewModel.currentStep < NewWorkOrderWizardViewModel.totalSteps {
                PrimaryButton(title: "Devam") { viewModel.nextStep() }
            } else {
                PrimaryButton(
                    title: "İş Emrini Oluştur",
                    isLoading: viewModel.phase == .submitting
                ) {
                    Task { await viewModel.submit() }
                }
            }
        }
        .padding(AppSpacing.l)
        .background(AppColor.brandSurface)
    }

    private func selectionCard(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.m) {
                Image(systemName: systemImage)
                    .foregroundStyle(selected ? AppColor.onPrimary : AppColor.brandPrimary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.body)
                        .foregroundStyle(selected ? AppColor.onPrimary : AppColor.primaryText)
                    if let subtitle {
                        Text(subtitle)
                            .font(AppFont.caption)
                            .foregroundStyle(selected ? AppColor.onPrimary.opacity(0.85) : AppColor.secondaryText)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? AppColor.onPrimary : AppColor.secondaryText)
            }
            .padding(AppSpacing.m)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(selected ? AppColor.brandPrimary : AppColor.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(AppColor.divider, lineWidth: selected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func priorityButton(_ priority: WorkOrderPriority) -> some View {
        let selected = viewModel.draft.priority == priority
        let color = WorkOrderPresentationMapping.appPriority(from: priority).accentColor
        return Button {
            viewModel.draft.priority = priority
        } label: {
            Text(priority.displayName)
                .font(AppFont.label)
                .foregroundStyle(selected ? AppColor.onPrimary : color)
                .padding(.horizontal, AppSpacing.m)
                .padding(.vertical, AppSpacing.s)
                .background(Capsule().fill(selected ? color : color.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func formField(title: String, text: Binding<String>, error: String?) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            TextField(title, text: text)
                .padding(AppSpacing.m)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            if let error {
                fieldError(error)
            }
        }
    }

    private func summaryRow(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            Spacer()
            Text(value ?? "—")
                .font(AppFont.body)
                .foregroundStyle(AppColor.primaryText)
        }
    }

    private func fieldError(_ message: String) -> some View {
        Text(message)
            .font(AppFont.caption)
            .foregroundStyle(AppColor.danger)
    }

    private func workTypeIcon(_ type: WorkType) -> String {
        switch type {
        case .installation: return "shippingbox"
        case .maintenance: return "wrench.and.screwdriver"
        case .repair: return "exclamationmark.triangle"
        case .delivery: return "truck.box"
        }
    }
}

#if DEBUG
#Preview("New WorkOrder Wizard") {
    NavigationStack {
        NewWorkOrderWizardView(
            viewModel: .previewInitial(),
            onFinished: { _ in },
            onCancel: {}
        )
    }
}
#endif
