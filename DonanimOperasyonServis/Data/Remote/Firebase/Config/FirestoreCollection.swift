import Foundation

/// Central catalog of Firestore collection names used by the app.
///
/// Every remote read/write must go through one of these cases —
/// repositories are forbidden from typing collection paths as raw
/// strings at call sites. That guarantees:
///
/// - a single source of truth if a collection is ever renamed;
/// - future migration tooling (backup, export, security-rule
///   generation) has a definitive list of collections to iterate;
/// - `firestore.rules` mirrors this exact set of names.
///
/// Phase 4 uses a **flat** layout — no nested subcollections. Child
/// records (notes, photos, locations, status history, signatures,
/// edit requests) live in their own top-level collections and carry
/// a `workOrderId` field for scoping. This mirrors how the
/// SwiftData layer already stores them and keeps queries simple.
enum FirestoreCollection: String, CaseIterable, Sendable {
    case users
    case customers
    case workOrders
    case workOrderNotes
    case workOrderStatusHistory
    case workOrderPhotos
    case workOrderLocations
    case signatures
    case editRequests
    case notifications
}
