import SwiftUI

struct OperatorProfileView: View {
    let user: User
    let onLogout: () -> Void

    var body: some View {
        ScrollView {
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

                profileCard(title: "Hesap") {
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
                .accessibilityLabel("Çıkış Yap")
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
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
                HStack(spacing: AppSpacing.xs) {
                    Circle().fill(AppColor.success).frame(width: 8, height: 8)
                    Text("Çevrimiçi")
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.secondaryText)
                }
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
}

#if DEBUG
#Preview("Profile") {
    NavigationStack {
        OperatorProfileView(user: OperatorPreviewData.operatorUser, onLogout: {})
    }
}
#endif
