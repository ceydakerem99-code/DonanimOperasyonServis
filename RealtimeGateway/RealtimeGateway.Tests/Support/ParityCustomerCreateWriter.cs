using RealtimeGateway.Contracts;
using RealtimeGateway.Core.Firestore;
using RealtimeGateway.Core.Idempotency;

namespace RealtimeGateway.Tests.Support;

/// <summary>
/// Test-only customer create writer mirroring FAZ 4A Firestore semantics:
/// receipt/idempotency duplicate first, then entityId alreadyExists, then accept.
/// </summary>
public sealed class ParityCustomerCreateWriter : ICustomerCreateWriter
{
    private readonly IIdempotencyStore _idempotency;
    private readonly IShadowVersionStore _versions;
    private readonly HashSet<string> _createdEntityIds = new(StringComparer.Ordinal);

    public ParityCustomerCreateWriter(IIdempotencyStore idempotency, IShadowVersionStore versions)
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

        if (_createdEntityIds.Contains(operation.EntityId))
        {
            return Task.FromResult(CustomerCreateWriteResult.Error(
                "alreadyExists",
                $"customers/{operation.EntityId} already exists",
                retryable: false));
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
        _createdEntityIds.Add(operation.EntityId);

        return Task.FromResult(CustomerCreateWriteResult.Accepted(eventId, remoteVersion));
    }
}
