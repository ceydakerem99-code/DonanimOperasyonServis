import SwiftUI

struct TechnicianProfileView: View {
    let user: User
    let onLogout: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                HStack(spacing: AppSpacing.m) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(AppColor.brandPrimary)
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(user.fullName).font(AppFont.title)
                        Text(UserRole.technician.displayName).font(AppFont.caption).foregroundStyle(AppColor.secondaryText)
                        HStack(spacing: AppSpacing.xs) {
                            Circle().fill(AppColor.success).frame(width: 8, height: 8)
                            Text("Çevrimiçi").font(AppFont.label).foregroundStyle(AppColor.secondaryText)
                        }
                    }
                }
                profileCard("Kişisel Bilgiler") {
                    InfoRow(title: "E-posta", value: user.email, systemImage: "envelope")
                    InfoRow(title: "Rol", value: UserRole.technician.displayName, systemImage: "person.badge.key")
                }
                profileCard("Hesap") {
                    ProfileUnsupportedRow(title: "Bildirim Ayarları", systemImage: "bell")
                    ProfileUnsupportedRow(title: "Şifre Değiştir", systemImage: "lock")
                    ProfileUnsupportedRow(title: "Dil", systemImage: "globe", value: "Türkçe")
                    InfoRow(title: "Uygulama Hakkında", value: "DOPS 0.1.0", systemImage: "info.circle")
                }
                Button(action: onLogout) {
                    Text("Çıkış Yap")
                        .font(AppFont.buttonLabel)
                        .foregroundStyle(AppColor.danger)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppSpacing.minimumTouchTarget + AppSpacing.xs)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
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
        TechnicianProfileView(user: TechnicianPreviewData.technician, onLogout: {})
    }
}
#endif
