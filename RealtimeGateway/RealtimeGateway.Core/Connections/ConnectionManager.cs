namespace RealtimeGateway.Core.Connections;

public sealed class GatewayConnection
{
    public required string ConnectionId { get; init; }
    public required string DeviceId { get; set; }
    public string? UserId { get; set; }
    public string Role { get; set; } = "unknown";
    public bool IsAuthenticated { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTimeOffset ConnectedAt { get; init; } = DateTimeOffset.UtcNow;
    public DateTimeOffset LastSeenAt { get; set; } = DateTimeOffset.UtcNow;
    public HashSet<string> EntitySubscriptions { get; set; } = new(StringComparer.Ordinal);
    public string? ResumeToken { get; set; }
}

public interface IConnectionManager
{
    void Register(GatewayConnection connection);
    void Unregister(string connectionId);
    GatewayConnection? Get(string connectionId);
    IReadOnlyList<GatewayConnection> GetByUserId(string userId);
    void MarkAuthenticated(string connectionId, string userId, string role, bool isActive);
    void Touch(string connectionId);
    int Count { get; }
}

public sealed class ConnectionManager : IConnectionManager
{
    private readonly object _gate = new();
    private readonly Dictionary<string, GatewayConnection> _byId = new(StringComparer.Ordinal);
    private readonly Dictionary<string, HashSet<string>> _byUser = new(StringComparer.Ordinal);

    public int Count
    {
        get { lock (_gate) return _byId.Count; }
    }

    public void Register(GatewayConnection connection)
    {
        lock (_gate)
        {
            _byId[connection.ConnectionId] = connection;
        }
    }

    public void Unregister(string connectionId)
    {
        lock (_gate)
        {
            if (!_byId.Remove(connectionId, out var existing))
            {
                return;
            }

            if (!string.IsNullOrEmpty(existing.UserId)
                && _byUser.TryGetValue(existing.UserId, out var set))
            {
                set.Remove(connectionId);
                if (set.Count == 0)
                {
                    _byUser.Remove(existing.UserId);
                }
            }
        }
    }

    public GatewayConnection? Get(string connectionId)
    {
        lock (_gate)
        {
            return _byId.TryGetValue(connectionId, out var c) ? c : null;
        }
    }

    public IReadOnlyList<GatewayConnection> GetByUserId(string userId)
    {
        lock (_gate)
        {
            if (!_byUser.TryGetValue(userId, out var set))
            {
                return Array.Empty<GatewayConnection>();
            }

            return set
                .Select(id => _byId[id])
                .ToList();
        }
    }

    public void MarkAuthenticated(string connectionId, string userId, string role, bool isActive)
    {
        lock (_gate)
        {
            if (!_byId.TryGetValue(connectionId, out var connection))
            {
                return;
            }

            if (!string.IsNullOrEmpty(connection.UserId)
                && connection.UserId != userId
                && _byUser.TryGetValue(connection.UserId, out var oldSet))
            {
                oldSet.Remove(connectionId);
            }

            connection.UserId = userId;
            connection.Role = role;
            connection.IsAuthenticated = true;
            connection.IsActive = isActive;
            connection.LastSeenAt = DateTimeOffset.UtcNow;

            if (!_byUser.TryGetValue(userId, out var set))
            {
                set = new HashSet<string>(StringComparer.Ordinal);
                _byUser[userId] = set;
            }

            set.Add(connectionId);
        }
    }

    public void Touch(string connectionId)
    {
        lock (_gate)
        {
            if (_byId.TryGetValue(connectionId, out var connection))
            {
                connection.LastSeenAt = DateTimeOffset.UtcNow;
            }
        }
    }
}
