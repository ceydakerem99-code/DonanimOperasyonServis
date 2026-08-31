using RealtimeGateway.Contracts;
using RealtimeGateway.Core.Idempotency;

namespace RealtimeGateway.Core.Firestore;

/// <summary>
/// Shadow/in-memory customer create for tests and environments without Firestore credentials.
/// </summary>
public sealed class InMemoryCustomerCreateWriter : ICustomerCreateWriter
{
    private readonly IIdempotencyStore _idempotency;
    private readonly IShadowVersionStore _versions;

    public InMemoryCustomerCreateWriter(IIdempotencyStore idempotency, IShadowVersionStore versions)
    {
        _idempotency = idempotency;
        _versions = versions;
    }

    public Task<CustomerCreateWriteResult> ApplyAsync(
        OperationSubmitPayload operation,
        DateTimeOffset now,
        CancellationToken cancellationToken = default)
    {
        if (_idempotency.TryGet(operation.IdempotencyKey, out var existing) && existing is not null)
        {
            return Task.FromResult(
                CustomerCreateWriteResult.Duplicate(existing.EventId, existing.ShadowRemoteVersion));
        }

        var eventId = Guid.NewGuid().ToString("D");
        var remoteVersion = _versions.PutNext(EntityTypes.Customer, operation.EntityId);
        var receipt = new IdempotencyReceipt(
            operation.IdempotencyKey,
            operation.OperationId,
            eventId,
            remoteVersion,
            operation.EntityType,
            operation.EntityId,
            now);
        _idempotency.Put(receipt);

        return Task.FromResult(CustomerCreateWriteResult.Accepted(eventId, remoteVersion));
    }
}
