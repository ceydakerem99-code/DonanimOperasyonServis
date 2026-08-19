import Foundation

/// Root dependency container.
///
/// Owns factory closures for repositories, use cases, and infrastructure
/// services. Later phases (Domain, Data, Sync, Auth) will populate this
/// container with concrete implementations.
///
/// - Note: `DIContainer` is intentionally a `final class` and not
///   `@Observable`. It is created once at app launch and shared through
///   the SwiftUI environment via ``DIContainerKey``. ViewModels should
///   receive their dependencies via constructor injection; they should
///   not hold a reference to the container itself, so tests can substitute
///   individual collaborators.
final class DIContainer: Sendable {

    /// Live container used by the running application.
    ///
    /// Phase 0: no registrations yet. Subsequent phases wire concrete
    /// dependencies here.
    static func live() -> DIContainer {
        DIContainer()
    }

    /// In-memory container for previews and unit tests.
    ///
    /// Phase 0: identical to `.live()` because no dependencies exist yet.
    /// Later phases will substitute in-memory doubles here.
    static func mock() -> DIContainer {
        DIContainer()
    }

    fileprivate init() {}
}
