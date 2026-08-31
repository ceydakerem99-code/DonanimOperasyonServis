using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using RealtimeGateway.Contracts;
using RealtimeGateway.Core.Auth;
using RealtimeGateway.Core.Connections;
using RealtimeGateway.Core.Logging;
using RealtimeGateway.Core.Pipeline;

namespace RealtimeGateway.Host.WebSockets;

public sealed class GatewayWebSocketHandler
{
    private readonly IConnectionManager _connections;
    private readonly IFirebaseTokenVerifier _tokenVerifier;
    private readonly OperationProcessor _processor;
    private readonly ILogger<GatewayWebSocketHandler> _logger;

    public GatewayWebSocketHandler(
        IConnectionManager connections,
        IFirebaseTokenVerifier tokenVerifier,
        OperationProcessor processor,
        ILogger<GatewayWebSocketHandler> logger)
    {
        _connections = connections;
        _tokenVerifier = tokenVerifier;
        _processor = processor;
        _logger = logger;
    }

    public async Task HandleAsync(HttpContext context, CancellationToken cancellationToken)
    {
        if (!context.WebSockets.IsWebSocketRequest)
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            await context.Response.WriteAsync("Expected WebSocket upgrade", cancellationToken);
            return;
        }

        using var socket = await context.WebSockets.AcceptWebSocketAsync();
        var connectionId = Guid.NewGuid().ToString("N");
        var connection = new GatewayConnection
        {
            ConnectionId = connectionId,
            DeviceId = "unknown"
        };
        _connections.Register(connection);
        GatewayLog.Connect(_logger, connectionId);

        try
        {
            await ReceiveLoopAsync(socket, connection, cancellationToken);
        }
        finally
        {
            GatewayLog.Disconnected(_logger, connectionId, connection.UserId);
            _connections.Unregister(connectionId);
            if (socket.State is WebSocketState.Open or WebSocketState.CloseReceived)
            {
                try
                {
                    await socket.CloseAsync(
                        WebSocketCloseStatus.NormalClosure,
                        "bye",
                        CancellationToken.None);
                }
                catch
                {
                    // ignore close races
                }
            }
        }
    }

    private async Task ReceiveLoopAsync(
        WebSocket socket,
        GatewayConnection connection,
        CancellationToken cancellationToken)
    {
        var buffer = new byte[64 * 1024];
        while (socket.State == WebSocketState.Open && !cancellationToken.IsCancellationRequested)
        {
            WebSocketReceiveResult result;
            using var message = new MemoryStream();
            do
            {
                result = await socket.ReceiveAsync(buffer, cancellationToken);
                if (result.MessageType == WebSocketMessageType.Close)
                {
                    return;
                }

                if (result.MessageType != WebSocketMessageType.Text)
                {
                    await SendErrorAsync(
                        socket,
                        null,
                        "protocolError",
                        "Only text JSON frames are supported",
                        retryable: false,
                        cancellationToken);
                    await socket.CloseAsync(
                        WebSocketCloseStatus.InvalidMessageType,
                        "binary not supported",
                        cancellationToken);
                    return;
                }

                message.Write(buffer, 0, result.Count);
            } while (!result.EndOfMessage);

            _connections.Touch(connection.ConnectionId);
            var json = Encoding.UTF8.GetString(message.ToArray());
            await HandleFrameAsync(socket, connection, json, cancellationToken);
        }
    }

    private async Task HandleFrameAsync(
        WebSocket socket,
        GatewayConnection connection,
        string json,
        CancellationToken cancellationToken)
    {
        GatewayEnvelope? envelope;
        try
        {
            envelope = GatewayJson.Deserialize<GatewayEnvelope>(json);
        }
        catch (JsonException)
        {
            await SendErrorAsync(
                socket,
                null,
                "protocolError",
                "Malformed JSON envelope",
                retryable: false,
                cancellationToken);
            return;
        }

        if (envelope is null || string.IsNullOrWhiteSpace(envelope.Type))
        {
            await SendErrorAsync(
                socket,
                null,
                "protocolError",
                "Missing message type",
                retryable: false,
                cancellationToken);
            return;
        }

        if (envelope.V != ProtocolVersion.Current)
        {
            await SendErrorAsync(
                socket,
                envelope.RequestId,
                "protocolError",
                $"Unsupported protocol version {envelope.V}",
                retryable: false,
                cancellationToken);
            return;
        }

        switch (envelope.Type)
        {
            case MessageTypes.Hello:
                await HandleHelloAsync(socket, connection, envelope, cancellationToken);
                break;
            case MessageTypes.Ping:
                await HandlePingAsync(socket, envelope, cancellationToken);
                break;
            case MessageTypes.OpSubmit:
                await HandleOpSubmitAsync(socket, connection, envelope, cancellationToken);
                break;
            default:
                await SendErrorAsync(
                    socket,
                    envelope.RequestId,
                    "protocolError",
                    $"Unsupported message type '{envelope.Type}'",
                    retryable: false,
                    cancellationToken);
                break;
        }
    }

    private async Task HandleHelloAsync(
        WebSocket socket,
        GatewayConnection connection,
        GatewayEnvelope envelope,
        CancellationToken cancellationToken)
    {
        var hello = GatewayJson.DeserializePayload<HelloPayload>(envelope.Payload);
        if (hello is null || string.IsNullOrWhiteSpace(hello.IdToken))
        {
            GatewayLog.AuthFailed(_logger, connection.ConnectionId, "missing idToken");
            await SendErrorAsync(
                socket,
                envelope.RequestId,
                "unauthorized",
                "hello.idToken is required",
                retryable: false,
                cancellationToken);
            await socket.CloseAsync(
                (WebSocketCloseStatus)4401,
                "unauthorized",
                cancellationToken);
            return;
        }

        var identity = await _tokenVerifier.VerifyAsync(hello.IdToken, cancellationToken);
        if (identity is null)
        {
            GatewayLog.AuthFailed(_logger, connection.ConnectionId, "token verification failed");
            await SendErrorAsync(
                socket,
                envelope.RequestId,
                "unauthorized",
                "Firebase ID token verification failed",
                retryable: false,
                cancellationToken);
            await socket.CloseAsync(
                (WebSocketCloseStatus)4401,
                "unauthorized",
                cancellationToken);
            return;
        }

        if (!identity.IsActive)
        {
            GatewayLog.AuthFailed(_logger, connection.ConnectionId, "inactive user");
            await SendErrorAsync(
                socket,
                envelope.RequestId,
                "forbidden",
                "User is inactive",
                retryable: false,
                cancellationToken);
            await socket.CloseAsync(
                (WebSocketCloseStatus)4403,
                "forbidden",
                cancellationToken);
            return;
        }

        connection.DeviceId = string.IsNullOrWhiteSpace(hello.DeviceId) ? connection.DeviceId : hello.DeviceId;
        connection.EntitySubscriptions = hello.EntitySubscriptions.Count == 0
            ? new HashSet<string>(EntityTypes.Faz1Supported, StringComparer.Ordinal)
            : new HashSet<string>(hello.EntitySubscriptions, StringComparer.Ordinal);

        _connections.MarkAuthenticated(
            connection.ConnectionId,
            identity.Uid,
            identity.Role,
            identity.IsActive);

        GatewayLog.Authenticated(_logger, connection.ConnectionId, identity.Uid, identity.Role);

        var ok = new GatewayEnvelope
        {
            V = ProtocolVersion.Current,
            Type = MessageTypes.HelloOk,
            RequestId = envelope.RequestId,
            Payload = JsonSerializer.SerializeToElement(new HelloOkPayload
            {
                UserId = identity.Uid,
                Role = identity.Role,
                ServerTime = DateTimeOffset.UtcNow.UtcDateTime.ToString("o"),
                ResumeToken = connection.ResumeToken
            }, GatewayJson.Options)
        };
        await SendAsync(socket, ok, cancellationToken);
    }

    private async Task HandlePingAsync(
        WebSocket socket,
        GatewayEnvelope envelope,
        CancellationToken cancellationToken)
    {
        var ping = GatewayJson.DeserializePayload<PingPongPayload>(envelope.Payload)
                   ?? new PingPongPayload { T = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() };
        var pong = new GatewayEnvelope
        {
            V = ProtocolVersion.Current,
            Type = MessageTypes.Pong,
            RequestId = envelope.RequestId,
            Payload = JsonSerializer.SerializeToElement(ping, GatewayJson.Options)
        };
        await SendAsync(socket, pong, cancellationToken);
    }

    private async Task HandleOpSubmitAsync(
        WebSocket socket,
        GatewayConnection connection,
        GatewayEnvelope envelope,
        CancellationToken cancellationToken)
    {
        if (!connection.IsAuthenticated)
        {
            await SendErrorAsync(
                socket,
                envelope.RequestId,
                "unauthorized",
                "hello handshake required before op.submit",
                retryable: false,
                cancellationToken);
            return;
        }

        var operation = GatewayJson.DeserializePayload<OperationSubmitPayload>(envelope.Payload);
        if (operation is null)
        {
            await SendErrorAsync(
                socket,
                envelope.RequestId,
                "invalidPayload",
                "op.submit payload is invalid",
                retryable: false,
                cancellationToken);
            return;
        }

        GatewayLog.EventReceived(
            _logger,
            connection.ConnectionId,
            operation.OperationId,
            operation.IdempotencyKey,
            operation.EntityType,
            operation.EntityId);

        var result = await _processor.ProcessAsync(connection, operation, cancellationToken);

        switch (result.Kind)
        {
            case OperationProcessKind.Duplicate:
                GatewayLog.Duplicate(
                    _logger,
                    connection.ConnectionId,
                    operation.IdempotencyKey,
                    result.Ack.EventId ?? "-");
                break;
            case OperationProcessKind.Forbidden:
                GatewayLog.Forbidden(
                    _logger,
                    connection.ConnectionId,
                    connection.UserId ?? "-",
                    result.Ack.Error?.Message ?? "forbidden");
                break;
        }

        var ackEnvelope = new GatewayEnvelope
        {
            V = ProtocolVersion.Current,
            Type = MessageTypes.OpAck,
            RequestId = envelope.RequestId,
            Payload = JsonSerializer.SerializeToElement(result.Ack, GatewayJson.Options)
        };
        await SendAsync(socket, ackEnvelope, cancellationToken);
        GatewayLog.AckSent(_logger, connection.ConnectionId, operation.OperationId, result.Ack.Status);

        if (result.Event is not null)
        {
            var eventEnvelope = new GatewayEnvelope
            {
                V = ProtocolVersion.Current,
                Type = MessageTypes.EventApply,
                RequestId = null,
                Payload = JsonSerializer.SerializeToElement(result.Event, GatewayJson.Options)
            };
            await SendAsync(socket, eventEnvelope, cancellationToken);
        }
    }

    private static async Task SendErrorAsync(
        WebSocket socket,
        string? requestId,
        string code,
        string message,
        bool retryable,
        CancellationToken cancellationToken)
    {
        var envelope = new GatewayEnvelope
        {
            V = ProtocolVersion.Current,
            Type = MessageTypes.Error,
            RequestId = requestId,
            Payload = JsonSerializer.SerializeToElement(new GatewayErrorPayload
            {
                Code = code,
                Message = message,
                Retryable = retryable
            }, GatewayJson.Options)
        };
        await SendAsync(socket, envelope, cancellationToken);
    }

    private static async Task SendAsync(
        WebSocket socket,
        GatewayEnvelope envelope,
        CancellationToken cancellationToken)
    {
        var bytes = Encoding.UTF8.GetBytes(GatewayJson.Serialize(envelope));
        await socket.SendAsync(bytes, WebSocketMessageType.Text, endOfMessage: true, cancellationToken);
    }
}
