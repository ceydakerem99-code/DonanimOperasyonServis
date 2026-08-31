import SwiftUI

struct LoginView: View {
    @Bindable var session: AuthSessionController

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                header
                if case .authenticationError(let error) = session.state {
                    ErrorBanner(
                        title: AuthErrorMessages.title(for: error),
                        message: AuthErrorMessages.message(for: error),
                        onRetry: { session.clearAuthenticationError() }
                    )
                }
                fields
                PrimaryButton(
                    title: "Giriş Yap",
                    systemImage: "arrow.right.circle.fill",
                    isLoading: session.isSigningIn,
                    isEnabled: canSubmit
                ) {
                    focusedField = nil
                    Task { await session.signIn(email: email, password: password) }
                }
            }
            .padding(AppSpacing.l)
        }
        .background(AppColor.neutralBackground)
    }

    private var header: some View {
        VStack(spacing: AppSpacing.m) {
            DOPSBrandMark(logoSize: 96, showsFullName: true)
            Text("Kurumsal hesabınızla giriş yapın.")
                .font(AppFont.body)
                .foregroundStyle(AppColor.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, AppSpacing.s)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("E-posta")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.secondaryText)
                TextField("ornek@sirket.com", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .padding(AppSpacing.m)
                    .background(AppColor.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Şifre")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.secondaryText)
                SecureField("••••••••", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit {
                        guard canSubmit else { return }
                        Task { await session.signIn(email: email, password: password) }
                    }
                    .padding(AppSpacing.m)
                    .background(AppColor.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            }
        }
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && !session.isSigningIn
    }
}

#if DEBUG
#Preview("LoginView") {
    LoginView(session: AuthSessionController(authRepository: FakeAuthRepository()))
}
#endif
