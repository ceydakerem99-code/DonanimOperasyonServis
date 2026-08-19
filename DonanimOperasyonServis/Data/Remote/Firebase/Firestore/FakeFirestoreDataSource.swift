import Foundation

/// In-memory `FirestoreDataSource` used by unit tests and by
/// `DIContainer.mock()`. Stores JSON-encoded DTO payloads keyed by
/// `(collection, documentId)` and applies equality / comparison
/// predicates in memory.
///
/// Dates are encoded as milliseconds since 1970 so round-trips
/// preserve Timestamp-equivalent fidelity without talking to a
/// real Firestore instance.
actor FakeFirestoreDataSource: FirestoreDataSource {

    private var documents: [DocumentKey: Data] = [:]

    struct DocumentKey: Hashable, Sendable {
        let collection: FirestoreCollection
        let id: String
    }

    init() {}

    func fetch<T: Decodable & Sendable>(
        _ type: T.Type,
        collection: FirestoreCollection,
        id: String
    ) async throws -> T? {
        guard let data = documents[DocumentKey(collection: collection, id: id)] else {
            return nil
        }
        do {
            return try FirestoreJSON.decoder.decode(T.self, from: data)
        } catch {
            throw FirebaseError.decodingFailed(reason: String(describing: error))
        }
    }

    func list<T: Decodable & Sendable>(
        _ type: T.Type,
        collection: FirestoreCollection,
        predicates: [FirestorePredicate],
        orderBy: [FirestoreSort]
    ) async throws -> [T] {
        let matching = documents.filter { $0.key.collection == collection }
        var decoded: [(id: String, json: [String: Any], value: T)] = []
        for (key, data) in matching {
            let json: [String: Any]
            let value: T
            do {
                json = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                value = try FirestoreJSON.decoder.decode(T.self, from: data)
            } catch {
                throw FirebaseError.decodingFailed(reason: String(describing: error))
            }
            if predicates.allSatisfy({ Self.matches($0, json: json) }) {
                decoded.append((key.id, json, value))
            }
        }
        if let sort = orderBy.first {
            decoded.sort { lhs, rhs in
                Self.compare(lhs.json[sort.fieldPath], rhs.json[sort.fieldPath], descending: sort.direction == .descending)
            }
        }
        return decoded.map(\.value)
    }

    func set<T: Encodable & Sendable>(
        _ value: T,
        collection: FirestoreCollection,
        id: String
    ) async throws {
        do {
            let data = try FirestoreJSON.encoder.encode(value)
            documents[DocumentKey(collection: collection, id: id)] = data
        } catch {
            throw FirebaseError.encodingFailed(reason: String(describing: error))
        }
    }

    func delete(collection: FirestoreCollection, id: String) async throws {
        documents.removeValue(forKey: DocumentKey(collection: collection, id: id))
    }

    func commit(_ writes: [FirestoreWrite]) async throws {
        for write in writes {
            switch write.kind {
            case .set(let data):
                documents[DocumentKey(collection: write.collection, id: write.id)] = data
            case .delete:
                documents.removeValue(forKey: DocumentKey(collection: write.collection, id: write.id))
            }
        }
    }

    /// Seeds a raw JSON blob so tests can inject invalid documents
    /// (unknown enum, missing fields) without going through a DTO.
    func seedRaw(collection: FirestoreCollection, id: String, json: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: json)
        documents[DocumentKey(collection: collection, id: id)] = data
    }

    // MARK: - Predicate matching

    private static func matches(_ predicate: FirestorePredicate, json: [String: Any]) -> Bool {
        let lhs = json[predicate.fieldPath]
        switch predicate.op {
        case .equalTo:            return equal(lhs, predicate.value)
        case .notEqualTo:         return !equal(lhs, predicate.value)
        case .lessThan:           return compare(lhs, predicate.value) == .orderedAscending
        case .lessThanOrEqual:    return compare(lhs, predicate.value) != .orderedDescending
        case .greaterThan:        return compare(lhs, predicate.value) == .orderedDescending
        case .greaterThanOrEqual: return compare(lhs, predicate.value) != .orderedAscending
        case .in:
            if case .stringArray(let values) = predicate.value,
               let string = lhs as? String {
                return values.contains(string)
            }
            return false
        }
    }

    private static func equal(_ lhs: Any?, _ rhs: FirestoreValue) -> Bool {
        switch rhs {
        case .null:                 return lhs == nil || lhs is NSNull
        case .string(let s):        return (lhs as? String) == s
        case .bool(let b):          return (lhs as? Bool) == b
        case .int(let i):           return int64(lhs) == i
        case .double(let d):        return double(lhs) == d
        case .date(let date):       return int64(lhs) == Int64((date.timeIntervalSince1970 * 1_000).rounded())
        case .stringArray(let ss):  return (lhs as? [String]) == ss
        }
    }

    private static func compare(_ lhs: Any?, _ rhs: FirestoreValue) -> ComparisonResult {
        switch rhs {
        case .date(let date):
            let rhsMillis = Int64((date.timeIntervalSince1970 * 1_000).rounded())
            guard let lhsMillis = int64(lhs) else { return .orderedAscending }
            if lhsMillis < rhsMillis { return .orderedAscending }
            if lhsMillis > rhsMillis { return .orderedDescending }
            return .orderedSame
        case .int(let i):
            guard let lhsInt = int64(lhs) else { return .orderedAscending }
            if lhsInt < i { return .orderedAscending }
            if lhsInt > i { return .orderedDescending }
            return .orderedSame
        case .double(let d):
            guard let lhsDouble = double(lhs) else { return .orderedAscending }
            if lhsDouble < d { return .orderedAscending }
            if lhsDouble > d { return .orderedDescending }
            return .orderedSame
        case .string(let s):
            guard let lhsString = lhs as? String else { return .orderedAscending }
            if lhsString < s { return .orderedAscending }
            if lhsString > s { return .orderedDescending }
            return .orderedSame
        default:
            return .orderedSame
        }
    }

    private static func compare(_ lhs: Any?, _ rhs: Any?, descending: Bool) -> Bool {
        let result: ComparisonResult
        if let l = lhs as? String, let r = rhs as? String {
            result = l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
        } else if let l = int64(lhs), let r = int64(rhs) {
            result = l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
        } else if let l = double(lhs), let r = double(rhs) {
            result = l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
        } else if let l = lhs as? Bool, let r = rhs as? Bool {
            result = (!l && r) ? .orderedAscending : (l && !r ? .orderedDescending : .orderedSame)
        } else {
            result = .orderedSame
        }
        return descending ? result == .orderedDescending : result == .orderedAscending
    }

    private static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let i as Int:     return Int64(i)
        case let i as Int64:   return i
        case let n as NSNumber: return n.int64Value
        case let d as Double:  return Int64(d.rounded())
        default:               return nil
        }
    }

    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let d as Double:  return d
        case let i as Int:     return Double(i)
        case let i as Int64:   return Double(i)
        case let n as NSNumber: return n.doubleValue
        default:               return nil
        }
    }
}
