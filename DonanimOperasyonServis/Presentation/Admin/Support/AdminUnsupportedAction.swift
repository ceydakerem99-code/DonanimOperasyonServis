import Foundation

/// Explicit copy for Admin actions that have no backend/domain support.
enum AdminUnsupportedAction {
    static let message = "Bu işlem bu sürümde desteklenmiyor."
}
