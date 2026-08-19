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
                    profileMenuRow(title: "Bildirim Ayarları", systemImage: "bell")
                    profileMenuRow(title: "Şifre Değiştir", systemImage: "lock")
                    profileMenuRow(title: "Dil", value: "Türkçe", systemImage: "globe")
                    profileMenuRow(title: "Uygulama Hakkında", systemImage: "info.circle")
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

    private func profileMenuRow(title: String, value: String? = nil, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(AppColor.brandPrimary)
                .frame(width: 24)
            Text(title)
                .font(AppFont.body)
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
}

#if DEBUG
#Preview("Profile") {
    NavigationStack {
        OperatorProfileView(user: OperatorPreviewData.operatorUser, onLogout: {})
    }
}
#endif
