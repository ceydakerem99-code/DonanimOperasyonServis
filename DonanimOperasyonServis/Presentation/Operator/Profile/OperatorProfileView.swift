import SwiftUI

struct OperatorProfileView: View {
    let user: User
    let accountService: ProfileAccountService
    var onShowReports: () -> Void = {}
    var onShowConflicts: () -> Void = {}
    var onShowCustomers: () -> Void = {}
    var onShowNotificationSettings: () -> Void = {}
    var onShowChangePassword: () -> Void = {}
    #if DEBUG
    var onShowDebugTools: () -> Void = {}
    #endif
    let onLogout: () -> Void

    var body: some View {
        AppShellTabScrollContent {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                profileHeader

                profileCard(title: "Kişisel Bilgiler") {
                    InfoRow(title: "Ad Soyad", value: user.fullName, systemImage: "person")
                    InfoRow(title: "E-posta", value: user.email, systemImage: "envelope")
                    if let phone = user.phoneNumber?.rawValue, !phone.isEmpty {
                        InfoRow(title: "Telefon", value: phone, systemImage: "phone")
                    }
                    InfoRow(title: "Rol", value: UserRole.operator.displayName, systemImage: "person.badge.key")
                }

                profileCard(title: "Operasyon") {
                    profileActionRow(
                        title: "Müşteriler",
                        systemImage: "building.2",
                        action: onShowCustomers
                    )
                    profileActionRow(
                        title: "Raporlar",
                        systemImage: "chart.bar.doc.horizontal",
                        action: onShowReports
                    )
                    profileActionRow(
                        title: "Senkron Çakışmaları",
                        systemImage: "exclamationmark.triangle",
                        action: onShowConflicts
                    )
                }

                profileCard(title: "Hesap") {
                    profileActionRow(
                        title: "Bildirim Ayarları",
                        systemImage: "bell",
                        action: onShowNotificationSettings
                    )
                    profileActionRow(
                        title: "Şifre Değiştir",
                        systemImage: "lock",
                        action: onShowChangePassword
                    )

                    InfoRow(title: "Dil", value: "Türkçe", systemImage: "globe")
                    InfoRow(title: "Uygulama Hakkında", value: "DOPS 0.1.0", systemImage: "info.circle")
                }

                #if DEBUG
                profileCard(title: "Geliştirici / Test") {
                    profileActionRow(
                        title: "Demo Veri & Sync",
                        systemImage: "wrench.and.screwdriver",
                        action: onShowDebugTools
                    )
                }
                #endif

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
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var profileHeader: some View {
        HStack(spacing: AppSpacing.m) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.brandPrimary)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(user.fullName)
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.primaryText)
                Text(UserRole.operator.displayName)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                ConnectionStatusIndicator()
            }
        }
        .padding(.top, AppSpacing.s)
    }

    private func profileCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text(title)
                .font(AppFont.subtitle)
            content()
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
    }

    private func profileActionRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ProfileNavigationRow(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

#if DEBUG
#Preview("Profile") {
    NavigationStack {
        OperatorProfileView(
            user: OperatorPreviewData.operatorUser,
            accountService: DIContainer.mock().makeProfileAccountService(),
            onLogout: {}
        )
        .environment(\.appShellTabBarOccupiedHeight, CustomTabBarLayout.estimatedReservedHeight(hasCenterFAB: true))
    }
}
#endif
