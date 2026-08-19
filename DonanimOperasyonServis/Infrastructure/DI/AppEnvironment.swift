import SwiftUI

/// SwiftUI environment key that exposes the shared ``DIContainer``.
private struct DIContainerKey: EnvironmentKey {
    static let defaultValue: DIContainer = .mock()
}

extension EnvironmentValues {
    /// The dependency container available to the current view hierarchy.
    ///
    /// Prefer resolving dependencies via constructor injection in
    /// ViewModels. Views should read only what they need from the
    /// container and forward specific dependencies onward.
    var diContainer: DIContainer {
        get { self[DIContainerKey.self] }
        set { self[DIContainerKey.self] = newValue }
    }
}
