import Foundation
import FirebaseAuth

/// Maps Firebase Authentication SDK errors to `DomainError` so
/// Presentation never sees raw `NSError` codes.
enum FirebaseAuthErrorMapper {

    static func map(_ error: Error) -> DomainError {
        if let domain = error as? DomainError { return domain }

        let nsError = error as NSError
        if nsError.domain == AuthErrorDomain,
           let code = AuthErrorCode(rawValue: nsError.code) {
            switch code {
            case .wrongPassword,
                 .invalidEmail,
                 .invalidCredential,
                 .userNotFound,
                 .invalidUserToken,
                 .userTokenExpired:
                return .authenticationFailed(.invalidCredentials)
            case .networkError:
                return .authenticationFailed(.networkUnavailable)
            case .tooManyRequests:
                return .authenticationFailed(.tooManyRequests)
            case .userDisabled,
                 .operationNotAllowed:
                return .authenticationFailed(.unauthorized)
            default:
                return .authenticationFailed(.unknown)
            }
        }

        let firebase = FirebaseError.map(error)
        switch firebase {
        case .networkUnavailable:
            return .authenticationFailed(.networkUnavailable)
        case .permissionDenied:
            return .authenticationFailed(.unauthorized)
        case .notFound:
            return .authenticationFailed(.userDocumentMissing)
        default:
            return .authenticationFailed(.unknown)
        }
    }
}
