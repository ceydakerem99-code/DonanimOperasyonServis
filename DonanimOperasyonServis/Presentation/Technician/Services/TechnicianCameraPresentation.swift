import Foundation

/// Camera presentation state owned by the detail ViewModel so SwiftUI
/// sheets/fullScreenCovers do not desync from view-local `@State`.
@MainActor
enum TechnicianCameraPresentationState: Equatable {
    case idle
    case preparing
    case presenting(category: PhotoCategory)

    var isBusy: Bool {
        switch self {
        case .idle: return false
        case .preparing, .presenting: return true
        }
    }

    var isPresenting: Bool {
        if case .presenting = self { return true }
        return false
    }

    var presentingCategory: PhotoCategory? {
        if case .presenting(let category) = self { return category }
        return nil
    }
}
