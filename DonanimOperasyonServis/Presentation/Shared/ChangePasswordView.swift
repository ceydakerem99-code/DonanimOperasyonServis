import SwiftUI

struct ChangePasswordView: View {
    @Bindable var viewModel: ChangePasswordViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                secureRow(
                    title: "Mevcut Şifre",
                    text: $viewModel.currentPassword,
                    visible: $viewModel.showCurrentPassword
                )
                secureRow(
                    title: "Yeni Şifre",
                    text: $viewModel.newPassword,
                    visible: $viewModel.showNewPassword
                )
                secureRow(
                    title: "Yeni Şifre Tekrar",
                    text: $viewModel.confirmation,
                    visible: $viewModel.showConfirmation
                )
            } footer: {
                Text("Şifre değiştirmek için internet bağlantısı gereklidir. Minimum \(PasswordPolicy.minimumLength) karakter.")
                    .font(AppFont.caption)
            }

            if case .error(let message) = viewModel.phase {
                Section {
                    Text(message)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.danger)
                }
            }

            if case .success = viewModel.phase {
                Section {
                    Text("Şifreniz başarıyla değiştirildi.")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.success)
                }
            }

            Section {
                PrimaryButton(
                    title: "Şifreyi Değiştir",
                    systemImage: "lock.rotation",
                    isLoading: viewModel.phase == .submitting,
                    isEnabled: viewModel.canSubmit
                ) {
                    Task { await viewModel.submit() }
                }
            }
        }
        .navigationTitle("Şifre Değiştir")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.phase) { _, phase in
            if case .success = phase {
                Task {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    dismiss()
                }
            }
        }
    }

    private func secureRow(
        title: String,
        text: Binding<String>,
        visible: Binding<Bool>
    ) -> some View {
        HStack {
            if visible.wrappedValue {
                TextField(title, text: text)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } else {
                SecureField(title, text: text)
                    .textContentType(.password)
            }
            Button {
                visible.wrappedValue.toggle()
            } label: {
                Image(systemName: visible.wrappedValue ? "eye.slash" : "eye")
                    .foregroundStyle(AppColor.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(visible.wrappedValue ? "Şifreyi gizle" : "Şifreyi göster")
        }
    }
}
