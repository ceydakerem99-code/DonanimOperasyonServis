import Foundation
import FirebaseCore

/// Bootstraps `FirebaseApp` from a bundled `GoogleService-Info.plist`.
///
/// **v4 default:** No real Firebase credentials are checked in yet.
/// The bootstrapper is deliberately tolerant of a missing plist —
/// when it can't find one it logs a warning and returns
/// `.skippedNoConfig`, leaving `FirebaseApp` un-initialised. This
/// keeps the app launchable in local development and CI while
/// still leaving the entire Firebase remote data layer wired up
/// behind interfaces (repositories, data sources) that we exercise
/// exclusively through fakes in tests.
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
