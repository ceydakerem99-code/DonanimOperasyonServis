import Foundation
import FirebaseCore

/// Bootstraps `FirebaseApp` from a bundled `GoogleService-Info.plist`.
///
/// Missing or invalid configuration is **not** silently ignored by
/// `DIContainer.live()` — that factory throws `FirebaseError.notConfigured`
/// (fail-fast). `DIContainer.mock()` and the unit-test harness still
/// use in-memory fakes and never call this bootstrapper for wiring.
///
/// Real credentials are added in Phase 6 (Authentication) together
/// with `GoogleService-Info.plist` files for the Dev and Prod
/// environments. See `DonanimOperasyonServis/Resources/Firebase/README.md`.
enum FirebaseAppBootstrapper {

    enum Outcome: Equatable, Sendable {
        /// `FirebaseApp.configure()` was called successfully.
        case configured
        /// Already configured earlier in this process. Idempotent.
        case alreadyConfigured
        /// No `GoogleService-Info.plist` was found in the bundle;
        /// skipped without touching Firebase.
        case skippedNoConfig
        /// A plist was found but could not be parsed into
        /// `FirebaseOptions`. Firebase remains un-initialised.
        case skippedInvalidConfig
    }

    /// Configures Firebase from the bundled plist if present.
    /// Returns the outcome so the DI wiring can log / decide
    /// whether to fall back to fakes.
    @discardableResult
    static func configure(bundle: Bundle = .main) -> Outcome {
        if FirebaseApp.app() != nil {
            AppLogger.dataRemote.debug("Firebase already configured; skipping.")
            return .alreadyConfigured
        }

        guard let path = bundle.path(
            forResource: "GoogleService-Info",
            ofType: "plist"
        ) else {
            AppLogger.dataRemote.warning(
                "GoogleService-Info.plist not found in bundle; Firebase not configured (Phase 4 default)."
            )
            return .skippedNoConfig
        }

        guard let options = FirebaseOptions(contentsOfFile: path) else {
            AppLogger.dataRemote.error(
                "GoogleService-Info.plist at \(path, privacy: .public) could not be parsed."
            )
            return .skippedInvalidConfig
        }

        FirebaseApp.configure(options: options)
        AppLogger.dataRemote.info("FirebaseApp.configure() completed.")
        return .configured
    }
}
