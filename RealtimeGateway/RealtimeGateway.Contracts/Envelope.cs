using System.Text.Json;
using System.Text.Json.Serialization;

namespace RealtimeGateway.Contracts;

public sealed class GatewayEnvelope
{
    [JsonPropertyName("v")]
    public int V { get; set; } = ProtocolVersion.Current;

    [JsonPropertyName("type")]
    public string Type { get; set; } = string.Empty;

    [JsonPropertyName("requestId")]
    public string? RequestId { get; set; }

    [JsonPropertyName("payload")]
    public JsonElement? Payload { get; set; }
}

public sealed class HelloPayload
{
    [JsonPropertyName("idToken")]
    public string IdToken { get; set; } = string.Empty;

    [JsonPropertyName("deviceId")]
    public string DeviceId { get; set; } = string.Empty;

    [JsonPropertyName("protocolVersion")]
    public int ProtocolVersion { get; set; } = Contracts.ProtocolVersion.Current;

    [JsonPropertyName("entitySubscriptions")]
    public List<string> EntitySubscriptions { get; set; } = [];
}

public sealed class HelloOkPayload
{
    [JsonPropertyName("userId")]
    public string UserId { get; set; } = string.Empty;

    [JsonPropertyName("role")]
    public string Role { get; set; } = string.Empty;

    [JsonPropertyName("serverTime")]
    public string ServerTime { get; set; } = string.Empty;

    [JsonPropertyName("resumeToken")]
    public string? ResumeToken { get; set; }
}

public sealed class PingPongPayload
{
    [JsonPropertyName("t")]
    public long? T { get; set; }
}
