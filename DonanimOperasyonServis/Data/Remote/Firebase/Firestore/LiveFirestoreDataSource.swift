import Foundation
import FirebaseFirestore

/// `FirestoreDataSource` backed by the real Firebase Firestore SDK.
///
/// Uses `Firestore.Encoder` / `Firestore.Decoder` so DTO `Date`
/// fields are stored as native Firestore `Timestamp` values (with
/// nanosecond precision), and enums-as-strings round-trip losslessly.
///
/// - Concurrency: The Firestore SDK types (`Firestore`,
///   `CollectionReference`, `Query`) are documented as thread-safe
///   but are not marked `Sendable` in Swift 6. We hold a single
///   `Firestore` reference here and treat it as safe to share across
///   concurrency domains; hence the `@unchecked Sendable` conformance.
///
/// - Errors: Every SDK error is funnelled through
///   `FirebaseError.map(_:)` so upper layers only ever see our
///   data-layer error taxonomy.
final class LiveFirestoreDataSource: FirestoreDataSource, @unchecked Sendable {

    private let firestore: Firestore

    init(firestore: Firestore = .firestore()) {
        self.firestore = firestore
    }

    // MARK: Reads

    func fetch<T: Decodable & Sendable>(
        _ type: T.Type,
        collection: FirestoreCollection,
        id: String
    ) async throws -> T? {
        let ref = firestore.collection(collection.rawValue).document(id)
        do {
            let snapshot = try await ref.getDocument()
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
            let snapshot = try await query.getDocuments()
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
            try ref.setData(from: value, merge: false)
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
                case .set(let data):
                    let payload = try JSONSerialization.jsonObject(with: data)
                    guard let dictionary = payload as? [String: Any] else {
                        throw FirebaseError.encodingFailed(reason: "batch payload is not a JSON object")
                    }
                    batch.setData(Self.timestamps(in: dictionary), forDocument: ref)
                case .delete:
                    batch.deleteDocument(ref)
                }
            }
            try await batch.commit()
        } catch {
            throw FirebaseError.map(error)
        }
    }

    /// Recursively replaces millisecond-since-1970 numbers that
    /// originated from `FirestoreJSON.encoder` with native
    /// `Timestamp` values. Heuristic: known date field names plus
    /// any nested dictionary.
    private static func timestamps(in dictionary: [String: Any]) -> [String: Any] {
        let dateKeys: Set<String> = [
            "createdAt", "updatedAt", "completedAt", "capturedAt",
            "occurredAt", "reviewedAt", "scheduledDate",
            "scheduledStart", "scheduledEnd"
        ]
        var result = dictionary
        for (key, value) in dictionary {
            if dateKeys.contains(key), let millis = value as? Double {
                result[key] = Timestamp(date: Date(timeIntervalSince1970: millis / 1_000))
            } else if dateKeys.contains(key), let millis = value as? Int64 {
                result[key] = Timestamp(date: Date(timeIntervalSince1970: Double(millis) / 1_000))
            } else if let nested = value as? [String: Any] {
                result[key] = timestamps(in: nested)
            }
        }
        return result
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

    /// Bridges our value envelope to the native Objective-C types the
    /// Firestore SDK expects for `whereField` etc. `Date` becomes a
    /// `Timestamp`; nil is `NSNull` so the SDK persists an explicit
    /// null instead of treating the field as absent.
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
