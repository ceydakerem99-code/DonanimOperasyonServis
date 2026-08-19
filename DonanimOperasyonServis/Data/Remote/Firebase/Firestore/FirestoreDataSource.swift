import Foundation

/// Thin, testable abstraction over Firestore CRUD.
///
/// This is the **seam** the Data layer uses to talk to Firestore.
/// Repositories depend on `FirestoreDataSource`, never on
/// `FirebaseFirestore` types directly. Two conforming
/// implementations exist:
///
/// - `LiveFirestoreDataSource` — wraps the real Firestore SDK.
///   Encodes DTOs with `Firestore.Encoder`, which converts `Date`
///   fields to native `Timestamp` values.
/// - `FakeFirestoreDataSource` (test target) — an in-memory actor
///   that stores JSON-encoded DTOs and applies simple equality
///   predicates. Used by every Phase 4 unit test.
///
/// All methods are `async throws`. Implementations translate
/// SDK/decoding errors to `FirebaseError` via
/// `FirebaseError.map(_:)`.
protocol FirestoreDataSource: Sendable {

    // MARK: Reads

    func fetch<T: Decodable & Sendable>(
        _ type: T.Type,
        collection: FirestoreCollection,
        id: String
    ) async throws -> T?

    func list<T: Decodable & Sendable>(
        _ type: T.Type,
        collection: FirestoreCollection,
        predicates: [FirestorePredicate],
        orderBy: [FirestoreSort]
    ) async throws -> [T]

    // MARK: Writes

    func set<T: Encodable & Sendable>(
        _ value: T,
        collection: FirestoreCollection,
        id: String
    ) async throws

    func delete(
        collection: FirestoreCollection,
        id: String
    ) async throws

    /// Atomically applies a set of writes. Used for the
    /// work-order + status-history pair so those two documents
    /// cannot diverge. Domain state-machine logic stays in Domain;
    /// this is a persistence primitive only.
    func commit(_ writes: [FirestoreWrite]) async throws
}

/// A single document mutation inside a `commit` batch. The payload
/// is pre-encoded so the data source stays generic over DTO types
/// without needing an existential `Encodable`.
struct FirestoreWrite: Sendable {
    enum Kind: Sendable {
        case set(Data)
        case delete
    }

    let collection: FirestoreCollection
    let id: String
    let kind: Kind

    static func set<T: Encodable>(
        _ value: T,
        collection: FirestoreCollection,
        id: String,
        encoder: JSONEncoder = FirestoreJSON.encoder
    ) throws -> FirestoreWrite {
        do {
            let data = try encoder.encode(value)
            return FirestoreWrite(collection: collection, id: id, kind: .set(data))
        } catch {
            throw FirebaseError.encodingFailed(reason: String(describing: error))
        }
    }

    static func delete(collection: FirestoreCollection, id: String) -> FirestoreWrite {
        FirestoreWrite(collection: collection, id: id, kind: .delete)
    }
}

/// Shared JSON encoder/decoder used by the type-erased batch API
/// and by the in-memory fake. Dates are stored as milliseconds so
/// round-trips keep millisecond-level Timestamp fidelity without
/// depending on ISO-8601 string parsing.
enum FirestoreJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}

// MARK: - Query building blocks

/// Value-type description of a Firestore `where` clause. Kept
/// framework-agnostic so tests can hold and inspect predicates
/// without importing `FirebaseFirestore`.
struct FirestorePredicate: Hashable, Sendable {
    let fieldPath: String
    let op: Operator
    let value: FirestoreValue

    enum Operator: Hashable, Sendable {
        case equalTo
        case notEqualTo
        case lessThan
        case lessThanOrEqual
        case greaterThan
        case greaterThanOrEqual
        case `in`
    }

    static func equal(_ fieldPath: String, _ value: FirestoreValue) -> Self {
        .init(fieldPath: fieldPath, op: .equalTo, value: value)
    }
}

/// Sort clause. `direction` follows Firestore semantics.
struct FirestoreSort: Hashable, Sendable {
    let fieldPath: String
    let direction: Direction

    enum Direction: Hashable, Sendable {
        case ascending
        case descending
    }

    static func ascending(_ fieldPath: String) -> Self {
        .init(fieldPath: fieldPath, direction: .ascending)
    }

    static func descending(_ fieldPath: String) -> Self {
        .init(fieldPath: fieldPath, direction: .descending)
    }
}

/// Value envelope for `FirestorePredicate`. Sendable enum so
/// predicates themselves are Sendable/Hashable and can appear in
/// recorded call logs in the test fake.
enum FirestoreValue: Hashable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case date(Date)
    case stringArray([String])
    case null
}
