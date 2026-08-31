namespace RealtimeGateway.Core.Idempotency;

public sealed record IdempotencyReceipt(
    string IdempotencyKey,
    string OperationId,
    string EventId,
    int ShadowRemoteVersion,
    string EntityType,
    string EntityId,
    DateTimeOffset CreatedAt);

public interface IIdempotencyStore
{
    bool TryGet(string idempotencyKey, out IdempotencyReceipt? receipt);
    void Put(IdempotencyReceipt receipt);
}

/// <summary>
/// Process-local duplicate detection. FAZ 1 intentionally does not persist to Firestore.
/// </summary>
public sealed class InMemoryIdempotencyStore : IIdempotencyStore
{
    private readonly object _gate = new();
    private readonly Dictionary<string, IdempotencyReceipt> _receipts = new(StringComparer.Ordinal);

    public bool TryGet(string idempotencyKey, out IdempotencyReceipt? receipt)
    {
        lock (_gate)
        {
            if (_receipts.TryGetValue(idempotencyKey, out var found))
            {
                receipt = found;
                return true;
            }

            receipt = null;
            return false;
        }
    }

    public void Put(IdempotencyReceipt receipt)
    {
        lock (_gate)
        {
            _receipts[receipt.IdempotencyKey] = receipt;
        }
    }
}

public interface IShadowVersionStore
{
    int? Get(string entityType, string entityId);
    int PutNext(string entityType, string entityId);
}

/// <summary>
/// In-memory optimistic concurrency helper for shadow mode (no Firestore).
/// </summary>
public sealed class InMemoryShadowVersionStore : IShadowVersionStore
{
    private readonly object _gate = new();
    private readonly Dictionary<string, int> _versions = new(StringComparer.Ordinal);

    private static string Key(string entityType, string entityId) => $"{entityType}:{entityId}";

    public int? Get(string entityType, string entityId)
    {
        lock (_gate)
        {
            return _versions.TryGetValue(Key(entityType, entityId), out var v) ? v : null;
        }
    }

    public int PutNext(string entityType, string entityId)
    {
        lock (_gate)
        {
            var key = Key(entityType, entityId);
            var next = _versions.TryGetValue(key, out var current) ? current + 1 : 1;
            _versions[key] = next;
            return next;
        }
    }
}
