using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using RealtimeGateway.Contracts;
using RealtimeGateway.Tests.Support;

namespace RealtimeGateway.Tests;

public sealed class GatewayProtocolTests : IClassFixture<GatewayWebApplicationFactory>
{
    private readonly GatewayWebApplicationFactory _factory;

    public GatewayProtocolTests(GatewayWebApplicationFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Hello_handshake_succeeds_with_valid_token()
    {
        var token = _factory.TokenVerifier.IssueToken("uid-op-1", UserRoles.Operator);
        using var ws = await WsTestClient.ConnectAsync(_factory);
        var response = await WsTestClient.HelloAsync(ws, token);
        Assert.Equal(MessageTypes.HelloOk, response.Type);
        var ok = WsTestClient.Payload<HelloOkPayload>(response);
        Assert.Equal("uid-op-1", ok.UserId);
        Assert.Equal(UserRoles.Operator, ok.Role);
    }

    [Fact]
    public async Task Authentication_failure_closes_with_error()
    {
        using var ws = await WsTestClient.ConnectAsync(_factory);
        var response = await WsTestClient.HelloAsync(ws, "not-a-valid-token");
        Assert.Equal(MessageTypes.Error, response.Type);
        var err = WsTestClient.Payload<GatewayErrorPayload>(response);
        Assert.Equal("unauthorized", err.Code);

        // Server should close shortly after
        var buffer = new byte[16];
        var result = await ws.ReceiveAsync(buffer, CancellationToken.None);
        Assert.Equal(WebSocketMessageType.Close, result.MessageType);
    }

    [Fact]
    public async Task Ping_pong_works_after_connect()
    {
        using var ws = await WsTestClient.ConnectAsync(_factory);
        await WsTestClient.SendAsync(ws, new GatewayEnvelope
        {
            V = ProtocolVersion.Current,
            Type = MessageTypes.Ping,
            Payload = JsonSerializer.SerializeToElement(new PingPongPayload { T = 42 }, GatewayJson.Options)
        });
        var pong = await WsTestClient.ReceiveAsync(ws);
        Assert.Equal(MessageTypes.Pong, pong.Type);
        var payload = WsTestClient.Payload<PingPongPayload>(pong);
        Assert.Equal(42, payload.T);
    }

    [Fact]
    public async Task Malformed_message_returns_protocol_error()
    {
        using var ws = await WsTestClient.ConnectAsync(_factory);
        var bytes = Encoding.UTF8.GetBytes("{not-json");
        await ws.SendAsync(bytes, WebSocketMessageType.Text, true, CancellationToken.None);
        var response = await WsTestClient.ReceiveAsync(ws);
        Assert.Equal(MessageTypes.Error, response.Type);
        var err = WsTestClient.Payload<GatewayErrorPayload>(response);
        Assert.Equal("protocolError", err.Code);
    }

    [Fact]
    public async Task Accepted_operation_returns_ack_and_event()
    {
        var token = _factory.TokenVerifier.IssueToken("uid-op-1", UserRoles.Operator);
        using var ws = await WsTestClient.ConnectAsync(_factory);
        Assert.Equal(MessageTypes.HelloOk, (await WsTestClient.HelloAsync(ws, token)).Type);

        var op = MakeCreateCustomer("uid-op-1", "cust-1");
        await WsTestClient.SendAsync(ws, OpEnvelope(op));
        var ackEnv = await WsTestClient.ReceiveAsync(ws);
        Assert.Equal(MessageTypes.OpAck, ackEnv.Type);
        var ack = WsTestClient.Payload<OpAckPayload>(ackEnv);
        Assert.Equal(AckStatuses.Accepted, ack.Status);
        Assert.False(string.IsNullOrWhiteSpace(ack.EventId));
        Assert.Equal(1, ack.RemoteVersion);

        var eventEnv = await WsTestClient.ReceiveAsync(ws);
        Assert.Equal(MessageTypes.EventApply, eventEnv.Type);
        var evt = WsTestClient.Payload<EventApplyPayload>(eventEnv);
        Assert.Equal(ack.EventId, evt.EventId);
        Assert.Equal("cust-1", evt.EntityId);
    }

    [Fact]
    public async Task Duplicate_idempotency_key_does_not_reapply()
    {
        var token = _factory.TokenVerifier.IssueToken("uid-op-1", UserRoles.Operator);
        using var ws = await WsTestClient.ConnectAsync(_factory);
        await WsTestClient.HelloAsync(ws, token);

        var op = MakeCreateCustomer("uid-op-1", "cust-dup");
        await WsTestClient.SendAsync(ws, OpEnvelope(op));
        var firstAck = WsTestClient.Payload<OpAckPayload>(await WsTestClient.ReceiveAsync(ws));
        Assert.Equal(AckStatuses.Accepted, firstAck.Status);
        _ = await WsTestClient.ReceiveAsync(ws); // event.apply

        var retry = MakeCreateCustomer("uid-op-1", "cust-dup");
        retry.OperationId = Guid.NewGuid().ToString("D");
        retry.IdempotencyKey = op.IdempotencyKey;
        await WsTestClient.SendAsync(ws, OpEnvelope(retry));
        var secondAck = WsTestClient.Payload<OpAckPayload>(await WsTestClient.ReceiveAsync(ws));
        Assert.Equal(AckStatuses.Duplicate, secondAck.Status);
        Assert.Equal(firstAck.EventId, secondAck.EventId);
        Assert.Equal(firstAck.RemoteVersion, secondAck.RemoteVersion);
    }

    [Fact]
    public async Task Existing_customer_with_different_idempotency_key_returns_already_exists()
    {
        var token = _factory.TokenVerifier.IssueToken("uid-op-1", UserRoles.Operator);
        using var ws = await WsTestClient.ConnectAsync(_factory);
        await WsTestClient.HelloAsync(ws, token);

        const string customerId = "cust-already-exists";
        var first = MakeCreateCustomer("uid-op-1", customerId);
        await WsTestClient.SendAsync(ws, OpEnvelope(first));
        var firstAck = WsTestClient.Payload<OpAckPayload>(await WsTestClient.ReceiveAsync(ws));
        Assert.Equal(AckStatuses.Accepted, firstAck.Status);
        Assert.False(string.IsNullOrWhiteSpace(firstAck.EventId));
        Assert.Equal(1, firstAck.RemoteVersion);

        var firstEvent = await WsTestClient.ReceiveAsync(ws);
        Assert.Equal(MessageTypes.EventApply, firstEvent.Type);

        var retry = MakeCreateCustomer("uid-op-1", customerId);
        retry.OperationId = Guid.NewGuid().ToString("D");
        retry.IdempotencyKey = "uid-op-1:customer:cust-already-exists:create:2";
        await WsTestClient.SendAsync(ws, OpEnvelope(retry));
        var secondAck = WsTestClient.Payload<OpAckPayload>(
            await WsTestClient.ReceiveAsync(ws, TimeSpan.FromSeconds(2)));
        Assert.Equal(AckStatuses.Error, secondAck.Status);
        Assert.Null(secondAck.EventId);
        Assert.Null(secondAck.RemoteVersion);
        Assert.NotNull(secondAck.Error);
        Assert.Equal("alreadyExists", secondAck.Error!.Code);
        Assert.False(secondAck.Error.Retryable);

        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
            await WsTestClient.ReceiveAsync(ws, TimeSpan.FromMilliseconds(300)));
    }

    [Fact]
    public async Task Forbidden_when_technician_creates_customer()
    {
        var token = _factory.TokenVerifier.IssueToken("uid-tech-1", UserRoles.Technician);
        using var ws = await WsTestClient.ConnectAsync(_factory);
        await WsTestClient.HelloAsync(ws, token);

        var op = MakeCreateCustomer("uid-tech-1", "cust-forbidden");
        await WsTestClient.SendAsync(ws, OpEnvelope(op));
        var ack = WsTestClient.Payload<OpAckPayload>(await WsTestClient.ReceiveAsync(ws));
        Assert.Equal(AckStatuses.Forbidden, ack.Status);
        Assert.Equal("forbidden", ack.Error?.Code);
    }

    [Fact]
    public async Task Forbidden_when_actorUserId_spoofed()
    {
        var token = _factory.TokenVerifier.IssueToken("uid-op-1", UserRoles.Operator);
        using var ws = await WsTestClient.ConnectAsync(_factory);
        await WsTestClient.HelloAsync(ws, token);

        var op = MakeCreateCustomer("someone-else", "cust-spoof");
        await WsTestClient.SendAsync(ws, OpEnvelope(op));
        var ack = WsTestClient.Payload<OpAckPayload>(await WsTestClient.ReceiveAsync(ws));
        Assert.Equal(AckStatuses.Forbidden, ack.Status);
        Assert.Equal("unauthorized", ack.Error?.Code);
    }

    [Fact]
    public async Task Conflict_on_stale_baseRemoteVersion()
    {
        var token = _factory.TokenVerifier.IssueToken("uid-op-1", UserRoles.Operator);
        using var ws = await WsTestClient.ConnectAsync(_factory);
        await WsTestClient.HelloAsync(ws, token);

        var create = MakeCreateWorkOrder("uid-op-1", "wo-1");
        await WsTestClient.SendAsync(ws, OpEnvelope(create));
        Assert.Equal(AckStatuses.Accepted, WsTestClient.Payload<OpAckPayload>(await WsTestClient.ReceiveAsync(ws)).Status);
        _ = await WsTestClient.ReceiveAsync(ws);

        var update = new OperationSubmitPayload
        {
            OperationId = Guid.NewGuid().ToString("D"),
            IdempotencyKey = "uid-op-1:workOrder:wo-1:update:2",
            EntityType = EntityTypes.WorkOrder,
            EntityId = "wo-1",
            OperationType = OperationTypes.Update,
            LocalVersion = 2,
            BaseRemoteVersion = 99,
            ActorUserId = "uid-op-1",
            DeviceId = "test-device",
            ClientTimestamp = DateTimeOffset.UtcNow.UtcDateTime.ToString("o")
        };
        await WsTestClient.SendAsync(ws, OpEnvelope(update));
        var ack = WsTestClient.Payload<OpAckPayload>(await WsTestClient.ReceiveAsync(ws));
        Assert.Equal(AckStatuses.Conflict, ack.Status);
        Assert.Equal("conflict", ack.Error?.Code);
    }

    [Fact]
    public async Task Disconnect_and_reconnect_is_safe()
    {
        var token = _factory.TokenVerifier.IssueToken("uid-op-1", UserRoles.Operator);
        using (var ws1 = await WsTestClient.ConnectAsync(_factory))
        {
            Assert.Equal(MessageTypes.HelloOk, (await WsTestClient.HelloAsync(ws1, token)).Type);
            await ws1.CloseAsync(WebSocketCloseStatus.NormalClosure, "done", CancellationToken.None);
        }

        using var ws2 = await WsTestClient.ConnectAsync(_factory);
        var hello = await WsTestClient.HelloAsync(ws2, token);
        Assert.Equal(MessageTypes.HelloOk, hello.Type);

        var op = MakeCreateCustomer("uid-op-1", "cust-reconnect");
        await WsTestClient.SendAsync(ws2, OpEnvelope(op));
        var ack = WsTestClient.Payload<OpAckPayload>(await WsTestClient.ReceiveAsync(ws2));
        Assert.Equal(AckStatuses.Accepted, ack.Status);
    }

    private static GatewayEnvelope OpEnvelope(OperationSubmitPayload op) => new()
    {
        V = ProtocolVersion.Current,
        Type = MessageTypes.OpSubmit,
        RequestId = "req-op",
        Payload = JsonSerializer.SerializeToElement(op, GatewayJson.Options)
    };

    private static OperationSubmitPayload MakeCreateCustomer(string actorUid, string customerId) => new()
    {
        OperationId = Guid.NewGuid().ToString("D"),
        IdempotencyKey = $"{actorUid}:customer:{customerId}:create:1",
        EntityType = EntityTypes.Customer,
        EntityId = customerId,
        OperationType = OperationTypes.Create,
        LocalVersion = 1,
        BaseRemoteVersion = null,
        ActorUserId = actorUid,
        DeviceId = "test-device",
        ClientTimestamp = DateTimeOffset.UtcNow.UtcDateTime.ToString("o"),
        Payload = JsonSerializer.SerializeToElement(new { id = customerId, name = "Test" }, GatewayJson.Options)
    };

    private static OperationSubmitPayload MakeCreateWorkOrder(string actorUid, string workOrderId) => new()
    {
        OperationId = Guid.NewGuid().ToString("D"),
        IdempotencyKey = $"{actorUid}:workOrder:{workOrderId}:create:1",
        EntityType = EntityTypes.WorkOrder,
        EntityId = workOrderId,
        OperationType = OperationTypes.Create,
        LocalVersion = 1,
        ActorUserId = actorUid,
        DeviceId = "test-device",
        ClientTimestamp = DateTimeOffset.UtcNow.UtcDateTime.ToString("o"),
        Payload = JsonSerializer.SerializeToElement(new { id = workOrderId }, GatewayJson.Options)
    };
}
