#if DEBUG
import Foundation

/// Seeds deterministic mock credentials when the app runs on
/// `FakeAuthRepository` (no Firebase config / DEBUG bootstrap).
///
/// Passwords live in memory only — never persisted to SwiftData.
enum DemoAccountSeeder {

    struct DemoAccount: Sendable {
        let email: String
        let password: String
        let user: User
    }

    /// Fixed DEBUG-only credentials for manual role testing.
    static let accounts: [DemoAccount] = [
        DemoAccount(
            email: "admin@dops.test",
            password: "DopsTest123!",
            user: User(
                id: UserID("demo-admin"),
                email: "admin@dops.test",
                fullName: "Admin Demo",
                role: .admin,
                phoneNumber: PhoneNumber("+905551110001"),
                isActive: true,
                createdAt: referenceDate,
                updatedAt: referenceDate
            )
        ),
        DemoAccount(
            email: "operator@dops.test",
            password: "DopsTest123!",
            user: User(
                id: UserID("demo-operator"),
                email: "operator@dops.test",
                fullName: "Mehmet Kaya",
                role: .operator,
                phoneNumber: PhoneNumber("+905551110002"),
                isActive: true,
                createdAt: referenceDate,
                updatedAt: referenceDate
            )
        ),
        DemoAccount(
            email: "technician@dops.test",
            password: "DopsTest123!",
            user: User(
                id: UserID("demo-technician"),
                email: "technician@dops.test",
                fullName: "Ahmet Yılmaz",
                role: .technician,
                phoneNumber: PhoneNumber("+905551110003"),
                isActive: true,
                createdAt: referenceDate,
                updatedAt: referenceDate
            )
        )
    ]

    private static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func seedIfNeeded(container: DIContainer) async {
        guard let auth = container.authRepository as? FakeAuthRepository else { return }

        for account in accounts {
            do {
                try await container.userRepository.save(account.user)
            } catch {
                AppLogger.app.warning("Demo account save failed for \(account.email): \(error)")
            }
            auth.seed(user: account.user, password: account.password)
        }

        AppLogger.app.info("DEBUG demo accounts ready (FakeAuthRepository).")
    }
}
#endif
