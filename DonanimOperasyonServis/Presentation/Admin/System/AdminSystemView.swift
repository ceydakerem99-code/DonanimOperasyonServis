import SwiftUI

struct AdminSystemView: View {
    @Bindable var viewModel: AdminSystemViewModel
    var onShowWorkTypes: () -> Void
    var onShowPauseReasons: () -> Void
    var onShowConflicts: () -> Void
    var onLogout: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                switch viewModel.phase {
                case .loading:
                    LoadingView(message: "Sistem bilgileri yükleniyor...")
                        .frame(minHeight: 240)

                case .error(let message):
                    ErrorBanner(title: "Sistem yüklenemedi", message: message) {
                        Task { await viewModel.load() }
                    }

                case .loaded:
                    appInfoCard
                    syncHealthCard
                    menuSection(title: "Genel") {
                        menuRow(title: "Uygulama Sürümü", value: viewModel.appVersion, systemImage: "info.circle")
                        menuRow(
                            title: "Ağ Durumu",
                            value: viewModel.health.isOnline ? "Çevrimiçi" : "Çevrimdışı",
                            systemImage: "wifi"
                        )
                    }
                    menuSection(title: "İş Emri Ayarları") {
                        navigationRow(title: "İş Türleri Yönetimi", systemImage: "list.bullet.rectangle", action: onShowWorkTypes)
                        navigationRow(title: "Bekleme Nedenleri", systemImage: "pause.circle", action: onShowPauseReasons)
                    }
                    menuSection(title: "Entegrasyonlar") {
                        menuRow(title: "Firebase Senkron", value: "Yapılandırıldı", systemImage: "arrow.triangle.2.circlepath")
                        menuRow(title: "Kimlik Doğrulama", value: "Firebase Auth", systemImage: "person.badge.key")
                    }
                    menuSection(title: "Senkronizasyon") {
                        navigationRow(
                            title: "Çözülmemiş Çakışmalar",
                            value: "\(viewModel.health.unresolvedConflicts)",
                            systemImage: "exclamationmark.triangle",
                            action: onShowConflicts
                        )
                    }

                    Button(action: onLogout) {
                        Text("Çıkış Yap")
                            .font(AppFont.buttonLabel)
                            .foregroundStyle(AppColor.danger)
                            .frame(maxWidth: .infinity)
                            .frame(height: AppSpacing.minimumTouchTarget + AppSpacing.xs)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Çıkış Yap")
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("Sistem")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private var appInfoCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Donanım Operasyon Servis")
                .font(AppFont.subtitle)
                .foregroundStyle(AppColor.onPrimary)
            Text("Kurumsal saha operasyon yönetimi")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.onPrimary.opacity(0.85))
        }
        .padding(AppSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.brandPrimary))
    }

    private var syncHealthCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Senkron Durumu")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.m) {
                healthMetric(title: "Bekleyen", value: viewModel.health.pendingSync)
                healthMetric(title: "Başarısız", value: viewModel.health.failedSync)
                healthMetric(title: "İşlemde", value: viewModel.health.inProgressSync)
                healthMetric(title: "Çakışma", value: viewModel.health.unresolvedConflicts)
            }
        }
        .padding(AppSpacing.m)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
    }

    private func healthMetric(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            Text("\(value)")
                .font(AppFont.title)
                .foregroundStyle(AppColor.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func menuSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(title)
                .font(AppFont.subtitle)
            content()
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
    }

    private func menuRow(title: String, value: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(AppColor.brandPrimary)
                .frame(width: 24)
            Text(title)
                .font(AppFont.body)
            Spacer()
            Text(value)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
        }
        .frame(minHeight: AppSpacing.minimumTouchTarget)
    }

    private func navigationRow(
        title: String,
        value: String? = nil,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(AppColor.brandPrimary)
                    .frame(width: 24)
                Text(title)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.primaryText)
                Spacer()
                if let value {
                    Text(value)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                Image(systemName: "chevron.right")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.secondaryText)
            }
            .frame(minHeight: AppSpacing.minimumTouchTarget)
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("System — loaded") {
    NavigationStack {
        AdminSystemView(
            viewModel: .previewLoaded(),
            onShowWorkTypes: {},
            onShowPauseReasons: {},
            onShowConflicts: {},
            onLogout: {}
        )
    }
}
#endif
