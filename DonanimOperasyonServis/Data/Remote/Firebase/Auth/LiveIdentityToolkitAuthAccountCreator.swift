import Foundation
import FirebaseCore

/// Identity Toolkit `accounts:signUp` — creates Auth users without
/// calling `Auth.auth().createUser`, so the admin session stays put.
struct LiveIdentityToolkitAuthAccountCreator: AuthAccountCreating, Sendable {

    private let apiKeyProvider: @Sendable () -> String?
    private let session: URLSession

    init(
        apiKeyProvider: @escaping @Sendable () -> String? = {
            FirebaseApp.app()?.options.apiKey
        },
        session: URLSession = .shared
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    func createAccount(email: String, password: String) async throws -> UserID {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            throw DomainError.infrastructure(underlying: "firebase.apiKeyMissing")
        }

        guard let url = URL(
            string: "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(apiKey)"
        ) else {
            throw DomainError.infrastructure(underlying: "firebase.invalidSignUpURL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "email": email,
                "password": password,
                "returnSecureToken": true,
            ]
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DomainError.infrastructure(underlying: "firebase.networkUnavailable")
        }

        guard let http = response as? HTTPURLResponse else {
            throw DomainError.infrastructure(underlying: "firebase.invalidHTTPResponse")
        }

        if http.statusCode == 200 {
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let localId = json["localId"] as? String,
                !localId.isEmpty
            else {
                throw DomainError.infrastructure(underlying: "firebase.signUpMissingLocalId")
            }
            return UserID(localId)
        }

        throw mapErrorPayload(data)
    }

    private func mapErrorPayload(_ data: Data) -> DomainError {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any],
            let message = error["message"] as? String
        else {
            return .infrastructure(underlying: "firebase.signUpFailed")
        }

        let code = message.split(separator: " ").first.map(String.init) ?? message
        switch code {
        case "EMAIL_EXISTS":
            return .invalidData(reason: "user.emailAlreadyExists")
        case "INVALID_EMAIL":
            return .invalidData(reason: "user.invalidEmail")
        case "WEAK_PASSWORD":
            return .invalidData(reason: "user.weakPassword")
        case "OPERATION_NOT_ALLOWED":
            return .infrastructure(underlying: "firebase.emailPasswordDisabled")
        case "TOO_MANY_ATTEMPTS_TRY_LATER":
            return .authenticationFailed(.tooManyRequests)
        default:
            return .infrastructure(underlying: "firebase.signUpFailed:\(code)")
        }
    }
}
