import Foundation

/// One-time chicken-and-egg unlock for the first Firebase Auth admin.
///
/// Matches by Auth UID **or** known admin email so Console UID typos
/// do not block the first login. After `users/{uid}` exists, remove the
/// temporary bootstrap `allow create` in `FirebaseRules/firestore.rules`.
enum FirstAdminBootstrap {
    /// Primary Firebase Auth UID (Console Authentication).
    static let uid = "idpKED07DNXjcsiuJ1pTC8bk9EuJv2"

    /// Extra Auth UIDs still allowed to self-seed (earlier test user).
    static let additionalBootstrapUIDs: Set<String> = [
        "4vioyXm2XqcsWBW7NUD0Bbxii2z1",
        "TOVxT7vCd3PVAQtnloO6J0Jg0FH2",
    ]

    /// Emails that may self-create an `admin` Firestore profile once.
    static let adminEmails: Set<String> = [
        "adminpanel@dops.com",
    ]

    static func matches(uid: String, email: String?) -> Bool {
        if uid == self.uid || additionalBootstrapUIDs.contains(uid) {
            return true
        }
        guard let email else { return false }
        return adminEmails.contains(email.lowercased())
    }
}
