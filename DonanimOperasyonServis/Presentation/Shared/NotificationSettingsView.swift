import SwiftUI

struct NotificationSettingsView: View {
    @Bindable var viewModel: NotificationSettingsViewModel

    var body: some View {
        AsyncLoadContainerView(
            isLoading: viewModel.phase == .loading,
            showsLoadingIndicator: viewModel.showsLoadingIndicator,
            hasCachedContent: viewModel.hasCachedContent,
            errorMessage: AsyncLoadPhaseParsing.errorMessage(viewModel.phase),
            isEmpty: false,
            loadingMessage: "Ayarlar yükleniyor...",
            errorTitle: "Yüklenemedi",
            onRetry: { Task { await viewModel.load() } }
        ) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(viewModel.systemAuthStatusDescription)
                            .font(AppFont.body)
                        Text("Uygulama içi bildirim ayarları ile iOS sistem izni birbirinden bağımsızdır. Gerçek push (APNs/FCM) bu sürümde yapılandırılmamıştır.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    if viewModel.systemAuthDenied == false {
                        Button("iOS Bildirim İzni İste") {
                            Task { await viewModel.requestSystemPermission() }
                        }
                    }
                } header: {
                    Text("Cihaz İzni")
                }

                if !viewModel.operationalKeys.isEmpty {
                    Section {
                        ForEach(viewModel.operationalKeys, id: \.self) { key in
                            preferenceToggle(key)
                        }
                    } header: {
                        Text("Operasyonel Bildirimler")
                    }
                }

                if !viewModel.systemKeys.isEmpty {
                    Section {
                        ForEach(viewModel.systemKeys, id: \.self) { key in
                            preferenceToggle(key)
                        }
                    } header: {
                        Text("Sistem Bildirimleri")
                    } footer: {
                        Text("Kapalı ayarlar yalnızca listeleme / uyarı gösterimini etkiler. İş emri ve senkronizasyon kayıtları yazılmaya devam eder.")
                    }
                }

                if case .error(let message) = viewModel.phase, viewModel.hasCachedContent {
                    Section {
                        Text(message)
                            .foregroundStyle(AppColor.danger)
                    }
                }
            }
        }
        .navigationTitle("Bildirim Ayarları")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(viewModel.phase == .saving)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private func preferenceToggle(_ key: NotificationPreferenceKey) -> some View {
        Toggle(key.displayName, isOn: Binding(
            get: { viewModel.isEnabled(key) },
            set: { newValue in
                Task { await viewModel.set(key, enabled: newValue) }
            }
        ))
    }
}
