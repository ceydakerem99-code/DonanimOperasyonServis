import SwiftUI

struct AdminUserDetailView: View {
    @Bindable var viewModel: AdminUserDetailViewModel

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading:
                LoadingView(message: "Kullanıcı yükleniyor...")
            case .error(let message):
                ErrorBanner(title: "Detay yüklenemedi", message: message) {
                    Task { await viewModel.load() }
                }
                .padding(AppSpacing.l)
            case .loaded:
                if let content = viewModel.content {
                    loadedContent(content)
                }
            }
        }
        .navigationTitle("Kullanıcı Detayı")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .confirmationDialog(
            activeConfirmationTitle,
            isPresented: $viewModel.showsActiveConfirmation,
            titleVisibility: .visible
        ) {
            Button(activeConfirmationActionTitle, role: .destructive) {
                Task { await viewModel.confirmToggleActive() }
            }
            Button("İptal", role: .cancel) {}
        } message: {
            Text("Bu işlem kullanıcının giriş ve yetki durumunu etkiler.")
        }
        .confirmationDialog(
            "Rolü değiştir",
            isPresented: $viewModel.showsRoleConfirmation,
            titleVisibility: .visible
        ) {
            Button("Onayla", role: .destructive) {
                Task { await viewModel.confirmRoleChange() }
            }
            Button("İptal", role: .cancel) {
                viewModel.pendingRole = nil
            }
        } message: {
            if let role = viewModel.pendingRole {
                Text("Yeni rol: \(role.displayName)")
            }
        }
    }

    private var activeConfirmationTitle: String {
        guard let user = viewModel.content?.user else { return "Durumu değiştir" }
        return user.isActive ? "Kullanıcıyı pasifleştir?" : "Kullanıcıyı aktifleştir?"
    }

    private var activeConfirmationActionTitle: String {
        guard let user = viewModel.content?.user else { return "Onayla" }
        return user.isActive ? "Pasifleştir" : "Aktifleştir"
    }

    @ViewBuilder
    private func loadedContent(_ content: AdminUserDetailContent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                profileHeader(content.user)

                profileCard(title: "Kişisel Bilgiler") {
                    InfoRow(title: "Ad Soyad", value: content.user.fullName, systemImage: "person")
                    InfoRow(title: "E-posta", value: content.user.email, systemImage: "envelope")
                    if let phone = content.user.phoneNumber?.rawValue, !phone.isEmpty {
                        InfoRow(title: "Telefon", value: phone, systemImage: "phone")
                    }
                    InfoRow(title: "Rol", value: content.user.role.displayName, systemImage: "shield")
                    InfoRow(
                        title: "Durum",
                        value: content.user.isActive ? "Aktif" : "Pasif",
                        systemImage: "circle.fill"
                    )
                }

                profileCard(title: "Rol Değiştir") {
                    ForEach(UserRole.allCases, id: \.self) { role in
                        Button {
                            viewModel.requestRoleChange(role)
                        } label: {
                            HStack {
                                Text(role.displayName)
                                    .font(AppFont.body)
                                    .foregroundStyle(AppColor.primaryText)
                                Spacer()
                                if content.user.role == role {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppColor.success)
                                }
                            }
                            .frame(minHeight: AppSpacing.minimumTouchTarget)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isUpdating || content.user.role == role || viewModel.isViewingSelf)
                    }
                    if viewModel.isViewingSelf {
                        Text("Kendi rolünüzü değiştiremezsiniz.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }

                profileCard(title: "Yetkiler (Salt Okunur)") {
                    ForEach(content.permissions, id: \.self) { action in
                        permissionRow(action.adminDisplayName, granted: true)
                    }
                    let denied = RoleAccessPolicyAdminUI.allActions.filter { !content.permissions.contains($0) }
                    ForEach(denied, id: \.self) { action in
                        permissionRow(action.adminDisplayName, granted: false)
                    }
                }

                profileCard(title: "Güvenlik") {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        HStack {
                            Image(systemName: "key")
                                .foregroundStyle(AppColor.secondaryText)
                                .frame(width: 24)
                            Text("Şifre Sıfırla")
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.secondaryText)
                            Spacer()
                        }
                        Text(viewModel.passwordResetUnsupportedMessage)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    .frame(minHeight: AppSpacing.minimumTouchTarget)
                    .accessibilityLabel("Şifre Sıfırla, \(AdminUnsupportedAction.message)")
                }

                if let message = viewModel.actionMessage {
                    Text(message)
                        .font(AppFont.caption)
                        .foregroundStyle(
                            message == AdminUnsupportedAction.message
                                ? AppColor.secondaryText
                                : AppColor.secondaryText
                        )
                }

                DestructiveButton(
                    title: content.user.isActive ? "Pasifleştir" : "Aktifleştir",
                    systemImage: content.user.isActive ? "person.crop.circle.badge.xmark" : "person.crop.circle.badge.checkmark",
                    isEnabled: !viewModel.isUpdating && !viewModel.isViewingSelf
                ) {
                    viewModel.requestToggleActive()
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
    }

    private func profileHeader(_ user: User) -> some View {
        HStack(spacing: AppSpacing.m) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.brandPrimary)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(user.fullName)
                    .font(AppFont.title)
                Text(user.role.displayName)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
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

    private func permissionRow(_ title: String, granted: Bool) -> some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? AppColor.success : AppColor.secondaryText)
            Text(title)
                .font(AppFont.body)
                .foregroundStyle(granted ? AppColor.primaryText : AppColor.secondaryText)
            Spacer()
        }
        .frame(minHeight: AppSpacing.minimumTouchTarget)
        .accessibilityLabel("\(title), \(granted ? "izinli" : "izinsiz")")
    }
}

#if DEBUG
#Preview("User Detail") {
    NavigationStack {
        AdminUserDetailView(viewModel: .previewLoaded())
    }
}
#endif
