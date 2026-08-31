import Foundation

/// Creates Firebase Authentication accounts without replacing the
/// currently signed-in session (unlike `Auth.createUser`).
protocol AuthAccountCreating: Sendable {
    /// Returns the new Auth UID (`localId`).
    func createAccount(email: String, password: String) async throws -> UserID
}
