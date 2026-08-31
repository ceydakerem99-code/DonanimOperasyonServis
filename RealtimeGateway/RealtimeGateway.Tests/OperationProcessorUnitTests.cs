using RealtimeGateway.Contracts;
using RealtimeGateway.Core.Auth;
using RealtimeGateway.Core.Connections;
using RealtimeGateway.Core.Firestore;
using RealtimeGateway.Core.Idempotency;
using RealtimeGateway.Core.Pipeline;

namespace RealtimeGateway.Tests;

public sealed class OperationProcessorUnitTests
{
    [Fact]
    public async Task Invalid_payload_returns_invalid_status()
    {
        var processor = CreateProcessor();
        var connection = Authenticated("uid-1", UserRoles.Operator);
        var result = await processor.ProcessAsync(connection, new OperationSubmitPayload
        {
            OperationId = "op-1",
            IdempotencyKey = "",
            EntityType = EntityTypes.Customer,
            EntityId = "c1",
            OperationType = OperationTypes.Create,
            LocalVersion = 1,
            ActorUserId = "uid-1"
        });
        Assert.Equal(AckStatuses.Invalid, result.Ack.Status);
        Assert.Equal(OperationProcessKind.Invalid, result.Kind);
    }

    [Fact]
    public async Task Unauthenticated_connection_is_forbidden()
    {
        var processor = CreateProcessor();
        var connection = new GatewayConnection { ConnectionId = "c1", DeviceId = "d1" };
        var result = await processor.ProcessAsync(connection, new OperationSubmitPayload
        {
            OperationId = "op-1",
            IdempotencyKey = "k",
            EntityType = EntityTypes.Customer,
            EntityId = "c1",
            OperationType = OperationTypes.Create,
            LocalVersion = 1,
            ActorUserId = "uid-1"
        });
        Assert.Equal(AckStatuses.Forbidden, result.Ack.Status);
    }

    private static OperationProcessor CreateProcessor()
    {
        var idempotency = new InMemoryIdempotencyStore();
        var versions = new InMemoryShadowVersionStore();
        var customerWriter = new InMemoryCustomerCreateWriter(idempotency, versions);
        return new OperationProcessor(idempotency, versions, customerWriter);
    }

    private static GatewayConnection Authenticated(string uid, string role) => new()
    {
        ConnectionId = "c1",
        DeviceId = "d1",
        UserId = uid,
        Role = role,
        IsAuthenticated = true,
        IsActive = true
    };
}
