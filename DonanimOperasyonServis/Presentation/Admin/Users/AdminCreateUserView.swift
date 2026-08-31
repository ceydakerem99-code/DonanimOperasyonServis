import SwiftUI

struct AdminCreateUserView: View {
    @Bindable var viewModel: AdminCreateUserViewModel
    var onCreated: (UserID) -> Void

    @State private var showsPassword = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                if case .error(let message) = viewModel.phase {
                    ErrorBanner(
                        title: "Kullanıcı oluşturulamadı",
                        message: message,
                        onRetry: { viewModel.clearError() }
                    )
                }

                field(title: "Ad Soyad") {
                    TextField("Ad Soyad", text: $viewModel.fullName)
                        // Avoid signup AutoFill heuristics that steal focus to Password.
                        .textContentType(.none)
                        .autocorrectionDisabled()
                }

                field(title: "E-posta") {
                    TextField("ornek@sirket.com", text: $viewModel.email)
                        .textContentType(.none)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                field(title: "Şifre") {
                    HStack(spacing: AppSpacing.s) {
                        Group {
                            if showsPassword {
                                TextField("En az 6 karakter", text: $viewModel.password)
                            } else {
                                SecureField("En az 6 karakter", text: $viewModel.password)
                            }
                        }
                        // Do not use `.newPassword` — iOS AutoFill / strong-password
                        // sheet blocks manual entry on this admin provisioning form.
                        .textContentType(.none)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            showsPassword.toggle()
                        } label: {
                            Image(systemName: showsPassword ? "eye.slash" : "eye")
                                .foregroundStyle(AppColor.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showsPassword ? "Şifreyi gizle" : "Şifreyi göster")
                    }
                }

                field(title: "Telefon *") {
                    TextField("+90…", text: $viewModel.phoneNumber)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }

                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    Text("Rol")
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.secondaryText)
                    ForEach(UserRole.allCases, id: \.self) { role in
                        Button {
                            viewModel.role = role
                        } label: {
                            HStack {
                                Text(role.displayName)
                                    .font(AppFont.body)
                                    .foregroundStyle(AppColor.primaryText)
                                Spacer()
                                if viewModel.role == role {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppColor.success)
                                }
                            }
                            .frame(minHeight: AppSpacing.minimumTouchTarget)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(AppSpacing.m)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                        .fill(AppColor.elevatedSurface)
                )

                PrimaryButton(
                    title: "Kullanıcı Oluştur",
                    systemImage: "person.badge.plus",
                    isLoading: viewModel.phase == .saving,
                    isEnabled: viewModel.canSubmit
                ) {
                    Task { await viewModel.create() }
                }
            }
            .padding(AppSpacing.l)
        }
        .background(AppColor.neutralBackground)
        .navigationTitle("Yeni Kullanıcı")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.phase) { _, newPhase in
            if case .created(let id) = newPhase {
                onCreated(id)
            }
        }
    }

    @ViewBuilder
    private func field(
        title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppFont.label)
                .foregroundStyle(AppColor.secondaryText)
            content()
                .font(AppFont.body)
                .padding(AppSpacing.m)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                        .fill(AppColor.elevatedSurface)
                )
        }
    }
}
