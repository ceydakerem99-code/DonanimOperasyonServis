#if DEBUG
import SwiftUI

/// Demo-only SMS preview for the customer satisfaction E2E flow.
/// No message leaves the device; no external SMS provider is called.
struct CustomerSatisfactionSMSSimulationView: View {
    var onOpenSurvey: ((CustomerSatisfactionID) -> Void)? = nil

    @Environment(\.diContainer) private var container
    @Environment(\.openURL) private var openURL
    @State private var viewModel = CustomerSatisfactionSMSSimulationViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                demoBanner

                if viewModel.isLoading {
                    LoadingView(message: "Tamamlanan iş emirleri taranıyor...")
                        .frame(minHeight: 160)
                } else if let loadError = viewModel.loadError, viewModel.options.isEmpty {
                    EmptyState(
                        systemImage: "message.badge",
                        title: "Simülasyon için kayıt yok",
                        message: loadError
                    )
                } else {
                    workOrderPickerSection
                    if let option = viewModel.selectedOption {
                        smsStatusSection
                        customerSMSPreviewSection(option)
                        openSurveySection(option)
                        debugActionsSection(option)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.vertical, AppSpacing.m)
        }
        .navigationTitle("Müşteriye Giden SMS")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load(container: container) }
        .refreshable { await viewModel.load(container: container) }
    }

    private var demoBanner: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("SMS Simülasyonu")
                .font(AppFont.subtitle)
                .foregroundStyle(AppColor.primaryText)
            Text("Gerçek SMS gönderilmez. İş emri tamamlandığında SMS otomatik simüle edilir; müşteri web anket bağlantısını Safari/Chrome üzerinden açar.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.semanticPausedSurface))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card)
                .strokeBorder(AppColor.statusOverdue.opacity(0.25), lineWidth: 1)
        )
    }

    private var workOrderPickerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Tamamlanan İş Emri")
            Picker("İş Emri", selection: Binding(
                get: { viewModel.selectedOrderId },
                set: { newValue in
                    if let newValue { viewModel.selectOrder(newValue) }
                }
            )) {
                ForEach(viewModel.options) { option in
                    Text("\(option.workOrderNumber) · \(option.customerName)")
                        .tag(Optional(option.id))
                }
            }
            .pickerStyle(.menu)
            if let phone = viewModel.selectedOption?.customerPhone {
                InfoRow(title: "Alıcı", value: phone)
            } else {
                Text("Alıcı telefonu kayıtlı değil (simülasyon yine de çalışır).")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
        .padding(AppSpacing.m)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
    }

    private var smsStatusSection: some View {
        Group {
            if viewModel.showsSentStatus {
                HStack(spacing: AppSpacing.s) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.success)
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("SMS Gönderildi (Simülasyon)")
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.success)
                        Text("Bu bir gerçek SMS değildir; müşteri deneyimini göstermek için simüle edilmiştir.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
                .padding(AppSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.semanticAvailableSurface))
            } else {
                HStack(spacing: AppSpacing.s) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(AppColor.statusOverdue)
                    Text("SMS henüz simüle edilmedi. İş emri tamamlandığında otomatik gönderilir.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                .padding(AppSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            }
        }
    }

    private func customerSMSPreviewSection(_ option: CompletedWorkOrderSurveyOption) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Müşteriye Giden SMS Önizlemesi")
            if viewModel.showsSentStatus {
                CustomerSatisfactionSMSMessagePreview(
                    content: option.smsPreviewContent,
                    onOpenSurvey: openWebSurveyAction(for: option)
                )
            } else {
                Text("Anket bağlantısı, değerlendirme kaydı Firestore'a yazıldıktan sonra gösterilir.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                    .padding(AppSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.card)
                            .fill(AppColor.elevatedSurface)
                    )
            }
        }
    }

    private func openSurveySection(_ option: CompletedWorkOrderSurveyOption) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Müşteri Akışı")
            PrimaryButton(
                title: "Değerlendirmeye Git",
                systemImage: "safari",
                isEnabled: viewModel.showsSentStatus
            ) {
                openWebSurvey(for: option)
            }

            Text("Müşteri web anket bağlantısını Safari/Chrome üzerinden açar, puanını gönderir.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
        }
        .padding(AppSpacing.m)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
    }

    private func debugActionsSection(_ option: CompletedWorkOrderSurveyOption) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            SectionHeader(title: "Test Araçları")
            SecondaryButton(title: "SMS'i Yeniden Simüle Et (Test)") {
                Task { await viewModel.resimulateSendSMS(container: container) }
            }
            .disabled(viewModel.isSending)

            if let deliveryError = viewModel.deliveryError {
                Text(deliveryError)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.danger)
            }

            if let onOpenSurvey {
                SecondaryButton(title: "Yerel iOS Formunu Aç (Debug)") {
                    onOpenSurvey(option.satisfactionId)
                }
            } else {
                NavigationLink {
                    CustomerSatisfactionFormView(satisfactionId: option.satisfactionId)
                } label: {
                    Text("Yerel iOS Formunu Aç (Debug)")
                        .font(AppFont.buttonLabel)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppSpacing.minimumTouchTarget + AppSpacing.xs)
                        .foregroundStyle(AppColor.brandPrimary)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.card)
                                .strokeBorder(AppColor.brandPrimary, lineWidth: 1)
                        )
                }
            }

            Text("Web URL: \(viewModel.showsSentStatus ? option.smsPreviewContent.surveyLink : "senkronizasyon bekleniyor")")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(AppColor.secondaryText)
                .textSelection(.enabled)
            Text("Anket ID: \(option.satisfactionId.rawValue)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(AppColor.secondaryText)
                .textSelection(.enabled)
        }
        .padding(AppSpacing.m)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
    }

    private func openWebSurveyAction(for option: CompletedWorkOrderSurveyOption) -> (() -> Void)? {
        guard viewModel.showsSentStatus else { return nil }
        return { openWebSurvey(for: option) }
    }

    private func openWebSurvey(for option: CompletedWorkOrderSurveyOption) {
        guard let url = URL(string: option.smsPreviewContent.surveyLink) else { return }
        openURL(url)
    }
}

#Preview("SMS Simulation") {
    NavigationStack {
        CustomerSatisfactionSMSSimulationView()
    }
    .environment(\.diContainer, DIContainer.mock())
}
#endif
