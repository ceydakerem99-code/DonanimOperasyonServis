using System.Text.Json;
using System.Text.Json.Serialization;

namespace RealtimeGateway.Contracts;

public sealed class OperationSubmitPayload
{
    [JsonPropertyName("operationId")]
    public string OperationId { get; set; } = string.Empty;

    [JsonPropertyName("idempotencyKey")]
    public string IdempotencyKey { get; set; } = string.Empty;

    [JsonPropertyName("entityType")]
    public string EntityType { get; set; } = string.Empty;

    [JsonPropertyName("entityId")]
    public string EntityId { get; set; } = string.Empty;

    [JsonPropertyName("operationType")]
    public string OperationType { get; set; } = string.Empty;

    [JsonPropertyName("localVersion")]
    public int LocalVersion { get; set; }

    [JsonPropertyName("baseRemoteVersion")]
    public int? BaseRemoteVersion { get; set; }

    [JsonPropertyName("actorUserId")]
    public string ActorUserId { get; set; } = string.Empty;

    [JsonPropertyName("deviceId")]
    public string DeviceId { get; set; } = string.Empty;

    [JsonPropertyName("clientTimestamp")]
    public string ClientTimestamp { get; set; } = string.Empty;

    [JsonPropertyName("payload")]
    public JsonElement? Payload { get; set; }

    [JsonPropertyName("dependsOnOperationId")]
    public string? DependsOnOperationId { get; set; }

    [JsonPropertyName("correlationId")]
    public string? CorrelationId { get; set; }
}

/// <summary>
/// FAZ 1 ACK statuses (shadow mode — no Firestore mutation).
/// </summary>
public static class AckStatuses
{
    public const string Accepted = "accepted";
    public const string Duplicate = "duplicate";
    public const string Forbidden = "forbidden";
    public const string Conflict = "conflict";
    public const string Invalid = "invalid";
    public const string Error = "error";
}

public sealed class OpAckPayload
{
    [JsonPropertyName("operationId")]
    public string OperationId { get; set; } = string.Empty;

    [JsonPropertyName("idempotencyKey")]
    public string IdempotencyKey { get; set; } = string.Empty;

    [JsonPropertyName("status")]
    public string Status { get; set; } = string.Empty;

    [JsonPropertyName("eventId")]
    public string? EventId { get; set; }

    [JsonPropertyName("remoteVersion")]
    public int? RemoteVersion { get; set; }

    [JsonPropertyName("error")]
    public GatewayErrorPayload? Error { get; set; }

    [JsonPropertyName("serverTimestamp")]
    public string ServerTimeStamp { get; set; } = string.Empty;

    [JsonPropertyName("correlationId")]
    public string? CorrelationId { get; set; }
}

public sealed class GatewayErrorPayload
{
    [JsonPropertyName("code")]
    public string Code { get; set; } = string.Empty;

    [JsonPropertyName("message")]
    public string Message { get; set; } = string.Empty;

    [JsonPropertyName("retryable")]
    public bool Retryable { get; set; }

    [JsonPropertyName("details")]
    public Dictionary<string, object?>? Details { get; set; }
}

public sealed class EventApplyPayload
{
    [JsonPropertyName("eventId")]
    public string EventId { get; set; } = string.Empty;

    [JsonPropertyName("operationId")]
    public string OperationId { get; set; } = string.Empty;

    [JsonPropertyName("idempotencyKey")]
    public string IdempotencyKey { get; set; } = string.Empty;

    [JsonPropertyName("entityType")]
    public string EntityType { get; set; } = string.Empty;

    [JsonPropertyName("entityId")]
    public string EntityId { get; set; } = string.Empty;

    [JsonPropertyName("operationType")]
    public string OperationType { get; set; } = string.Empty;

    [JsonPropertyName("remoteVersion")]
    public int? RemoteVersion { get; set; }

    [JsonPropertyName("actorUserId")]
    public string ActorUserId { get; set; } = string.Empty;

    [JsonPropertyName("serverTimestamp")]
    public string ServerTimestamp { get; set; } = string.Empty;

    [JsonPropertyName("payload")]
    public JsonElement? Payload { get; set; }

    [JsonPropertyName("causation")]
    public string Causation { get; set; } = "accepted";

    [JsonPropertyName("correlationId")]
    public string? CorrelationId { get; set; }
}
