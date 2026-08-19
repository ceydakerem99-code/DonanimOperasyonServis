import Foundation

/// Auth-provider transitions surfaced by `AuthRepository.authStateChanges()`.
/// Domain never imports Firebase Auth types; Infrastructure maps SDK
/// callbacks onto these cases.
enum AuthSessionEvent: Equatable, Sendable {
    case signedIn(UserID)
    case signedOut
}
