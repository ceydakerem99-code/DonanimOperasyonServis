import Foundation
import FirebaseFirestore

/// `FirestoreDataSource` backed by the real Firebase Firestore SDK.
///
/// Uses `Firestore.Encoder` so DTO `Date` fields are stored as native
/// Firestore `Timestamp` values. The same encoder is used for both
/// single-document `set` and batch `commit`.
///
/// Persistence: disk cache is disabled (`MemoryCacheSettings`).
/// Reads use `FirestoreSource.server` so an offline device fails
/// with a network error instead of serving a second local store.
/// SwiftData remains the only local source of truth.
///
/// - Concurrency: The Firestore SDK types are documented as
///   thread-safe but are not marked `Sendable` in Swift 6, hence
///   `@unchecked Sendable`.
final class LiveFirestoreDataSource: FirestoreDataSource, @unchecked Sendable {

    private let firestore: Firestore

    init(firestore: Firestore? = nil) {
        if let firestore {
            self.firestore = firestore
        } else {
            let db = Firestore.firestore()
            db.settings = LiveFirestoreConfiguration.makeSettings()
            self.firestore = db
        }
    }

    // MARK: Reads

    func fetch<T: Decodable & Sendable>(
        _ type: T.Type,
        collection: FirestoreCollection,
        id: String
    ) async throws -> T? {
        let ref = firestore.collection(collection.rawValue).document(id)
        do {
            let snapshot = try await ref.getDocument(source: LiveFirestoreConfiguration.readSource)


            guard snapshot.exists else { return nil }
            return try snapshot.data(as: T.self)
        } catch {
            throw FirebaseError.map(error)
        }
    }

    func list<T: Decodable & Sendable>(
        _ type: T.Type,
        collection: FirestoreCollection,
        predicates: [FirestorePredicate],
        orderBy: [FirestoreSort]
    ) async throws -> [T] {
        var query: Query = firestore.collection(collection.rawValue)
        for predicate in predicates {
            query = apply(predicate, to: query)
        }
        for sort in orderBy {
            query = query.order(by: sort.fieldPath, descending: sort.direction == .descending)
        }
        do {
            let snapshot = try await query.getDocuments(source: LiveFirestoreConfiguration.readSource)
            for document in snapshot.documents {
            }
            return try snapshot.documents.map { try $0.data(as: T.self) }
        } catch {
            throw FirebaseError.map(error)
        }
    }

    // MARK: Writes

    func set<T: Encodable & Sendable>(
        _ value: T,
        collection: FirestoreCollection,
        id: String
    ) async throws {
        let ref = firestore.collection(collection.rawValue).document(id)
        do {
            let payload = try LiveFirestoreConfiguration.encode(value)
            try await ref.setData(payload)
        } catch {
            throw FirebaseError.map(error)
        }
    }

    func updateFields<T: Encodable & Sendable>(
        _ value: T,
        collection: FirestoreCollection,
        id: String
    ) async throws {
        let ref = firestore.collection(collection.rawValue).document(id)
        do {
            let payload = try LiveFirestoreConfiguration.encode(value)
            try await ref.updateData(payload)
        } catch {
            throw FirebaseError.map(error)
        }
    }

    func delete(
        collection: FirestoreCollection,
        id: String
    ) async throws {
        let ref = firestore.collection(collection.rawValue).document(id)
        do {
            try await ref.delete()
        } catch {
            throw FirebaseError.map(error)
        }
    }

    func commit(_ writes: [FirestoreWrite]) async throws {
        let batch = firestore.batch()
        do {
            for write in writes {
                let ref = firestore.collection(write.collection.rawValue).document(write.id)
                switch write.kind {
                case .set(let box):
                    let payload = try LiveFirestoreConfiguration.encode(box)
                    batch.setData(payload, forDocument: ref)
                case .delete:
                    batch.deleteDocument(ref)
                }
            }
            try await batch.commit()
        } catch {
            throw FirebaseError.map(error)
        }
    }

    // MARK: - Query translation

    private func apply(_ predicate: FirestorePredicate, to query: Query) -> Query {
        let value = predicate.value.firestoreObject
        switch predicate.op {
        case .equalTo:
            return query.whereField(predicate.fieldPath, isEqualTo: value)
        case .notEqualTo:
            return query.whereField(predicate.fieldPath, isNotEqualTo: value)
        case .lessThan:
            return query.whereField(predicate.fieldPath, isLessThan: value)
        case .lessThanOrEqual:
            return query.whereField(predicate.fieldPath, isLessThanOrEqualTo: value)
        case .greaterThan:
            return query.whereField(predicate.fieldPath, isGreaterThan: value)
        case .greaterThanOrEqual:
            return query.whereField(predicate.fieldPath, isGreaterThanOrEqualTo: value)
        case .in:
            if case .stringArray(let values) = predicate.value {
                return query.whereField(predicate.fieldPath, in: values)
            } else {
                return query.whereField(predicate.fieldPath, in: [value])
            }
        }
    }
}

// MARK: - FirestoreValue → SDK value

private extension FirestoreValue {

    var firestoreObject: Any {
        switch self {
        case .string(let s):        return s
        case .bool(let b):          return b
        case .int(let i):           return NSNumber(value: i)
        case .double(let d):        return d
        case .date(let date):       return Timestamp(date: date)
        case .stringArray(let ss):  return ss
        case .null:                 return NSNull()
        }
    }
}
