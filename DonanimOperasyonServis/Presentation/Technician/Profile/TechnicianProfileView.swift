import SwiftUI

struct TechnicianProfileView: View {
    let user: User
    let accountService: ProfileAccountService
    var onShowNotificationSettings: () -> Void = {}
    var onShowChangePassword: () -> Void = {}
    #if DEBUG
    var onShowDebugTools: () -> Void = {}
    #endif
    let onLogout: () -> Void

    var body: some View {
        AppShellTabScrollContent {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                HStack(spacing: AppSpacing.m) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(AppColor.brandPrimary)
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(user.fullName).font(AppFont.title)
                        Text(UserRole.technician.displayName).font(AppFont.caption).foregroundStyle(AppColor.secondaryText)
                        ConnectionStatusIndicator()
                    }
                }
                profileCard("Kişisel Bilgiler") {
                    InfoRow(title: "E-posta", value: user.email, systemImage: "envelope")
                    InfoRow(title: "Rol", value: UserRole.technician.displayName, systemImage: "person.badge.key")
                }
                profileCard("Hesap") {
                    profileActionRow(title: "Bildirim Ayarları", systemImage: "bell", action: onShowNotificationSettings)
                    profileActionRow(title: "Şifre Değiştir", systemImage: "lock", action: onShowChangePassword)

                    InfoRow(title: "Dil", value: "Türkçe", systemImage: "globe")
                    InfoRow(title: "Uygulama Hakkında", value: "DOPS 0.1.0", systemImage: "info.circle")
                }
                #if DEBUG
                profileCard("Geliştirici / Test") {
                    profileActionRow(
                        title: "Demo Veri & Mock GPS",
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
            }
        }
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func profileActionRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ProfileNavigationRow(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func profileCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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
#Preview("Technician Profile") {
    NavigationStack {
        TechnicianProfileView(
            user: TechnicianPreviewData.technician,
            accountService: DIContainer.mock().makeProfileAccountService(),
            onLogout: {}
        )
        .environment(\.appShellTabBarOccupiedHeight, CustomTabBarLayout.estimatedReservedHeight(hasCenterFAB: false))
    }
}
#endif
