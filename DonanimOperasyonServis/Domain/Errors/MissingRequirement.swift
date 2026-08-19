import Foundation

/// A single piece of evidence that is required to complete a work
/// order but has not yet been supplied. Returned by
/// `CompletionRequirements.check(_:)` so the caller can report each
/// gap individually (e.g. "eksik teknisyen imzası", "eksik POS
/// öncesi fotoğrafı").
enum MissingRequirement: Hashable, Sendable {
    case missingNote
    case missingPhoto(PhotoCategory)
    case missingLocation(LocationEvent)
    case missingTechnicianSignature
    case missingCustomerSignature
}

extension MissingRequirement {
    /// Stable machine-readable code for logging and analytics.
    var code: String {
        switch self {
        case .missingNote:                 return "missing_note"
        case .missingPhoto(let category):  return "missing_photo.\(category.rawValue)"
        case .missingLocation(let event):  return "missing_location.\(event.rawValue)"
        case .missingTechnicianSignature:  return "missing_technician_signature"
        case .missingCustomerSignature:    return "missing_customer_signature"
        }
    }
}
