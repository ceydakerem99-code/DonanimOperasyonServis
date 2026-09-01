using RealtimeGateway.Contracts;
using RealtimeGateway.Core.Auth;
using RealtimeGateway.Core.Connections;
using RealtimeGateway.Core.Firestore;
using RealtimeGateway.Core.Idempotency;

namespace RealtimeGateway.Core.Pipeline;

public sealed class OperationProcessor
{
    private readonly IIdempotencyStore _idempotency;
    private readonly IShadowVersionStore _versions;
    private readonly ICustomerCreateWriter _customerCreateWriter;

    public OperationProcessor(
        IIdempotencyStore idempotency,
        IShadowVersionStore versions,
        ICustomerCreateWriter customerCreateWriter)
    {
        _idempotency = idempotency;
        _versions = versions;
        _customerCreateWriter = customerCreateWriter;
    }

    public async Task<OperationProcessResult> ProcessAsync(
        GatewayConnection connection,
        OperationSubmitPayload operation,
        CancellationToken cancellationToken = default)
    {
        var now = DateTimeOffset.UtcNow;
        var serverTs = now.UtcDateTime.ToString("o");

        if (!connection.IsAuthenticated || string.IsNullOrWhiteSpace(connection.UserId))
        {
            return Reject(
                operation,
                AckStatuses.Forbidden,
                "unauthorized",
                "Connection is not authenticated",
                retryable: false,
                serverTs);
        }

        if (!connection.IsActive)
        {
            return Reject(
                operation,
                AckStatuses.Forbidden,
                "forbidden",
                "User profile is inactive",
                retryable: false,
                serverTs);
        }

        var validationError = ValidateShape(operation);
        if (validationError is not null)
        {
            return Reject(
                operation,
                AckStatuses.Invalid,
                "invalidPayload",
                validationError,
                retryable: false,
                serverTs);
        }

        // Authoritative actor is the authenticated UID — never trust payload actorUserId alone.
        if (!string.Equals(operation.ActorUserId, connection.UserId, StringComparison.Ordinal))
        {
            return Reject(
                operation,
                AckStatuses.Forbidden,
                "unauthorized",
                "actorUserId does not match authenticated uid",
                retryable: false,
                serverTs,
                details: new Dictionary<string, object?>
                {
                    ["authenticatedUid"] = connection.UserId,
                    ["payloadActorUserId"] = operation.ActorUserId
                });
        }

        // Connectivity probes are protocol tests only — accept before role matrix
        // so technicians never need customer.create for shadow smoke/probe.
        if (IsConnectivityProbe(operation))
        {
            return AcceptConnectivityProbe(connection, operation, now, serverTs);
        }

        if (!AuthorizationPolicy.CanSubmit(connection.Role, operation.EntityType, operation.OperationType))
        {
            return Reject(
                operation,
                AckStatuses.Forbidden,
                "forbidden",
                $"role {connection.Role} cannot {operation.OperationType} {operation.EntityType}",
                retryable: false,
                serverTs,
                details: new Dictionary<string, object?>
                {
                    ["role"] = connection.Role,
                    ["entityType"] = operation.EntityType,
                    ["operationType"] = operation.OperationType
                });
        }

        if (operation.EntityType == EntityTypes.Customer && operation.OperationType == OperationTypes.Create)
        {
            return await ProcessCustomerCreateAsync(connection, operation, now, serverTs, cancellationToken)
                .ConfigureAwait(false);
        }

        if (_idempotency.TryGet(operation.IdempotencyKey, out var existing) && existing is not null)
        {
            var duplicateAck = new OpAckPayload
            {
                OperationId = operation.OperationId,
                IdempotencyKey = operation.IdempotencyKey,
                Status = AckStatuses.Duplicate,
                EventId = existing.EventId,
                RemoteVersion = existing.ShadowRemoteVersion,
                ServerTimeStamp = serverTs,
                CorrelationId = operation.CorrelationId
            };

            return new OperationProcessResult(
                duplicateAck,
                Event: null,
                Kind: OperationProcessKind.Duplicate);
        }

        if (operation.OperationType is OperationTypes.Update or OperationTypes.Delete)
        {
            var current = _versions.Get(operation.EntityType, operation.EntityId);
            if (current is null)
            {
                return Reject(
                    operation,
                    AckStatuses.Error,
                    "notFound",
                    "Entity has no shadow version yet (FAZ 1 has no Firestore)",
                    retryable: false,
                    serverTs);
            }

            if (operation.BaseRemoteVersion is null || operation.BaseRemoteVersion.Value != current.Value)
            {
                return Reject(
                    operation,
                    AckStatuses.Conflict,
                    "conflict",
                    $"baseRemoteVersion {operation.BaseRemoteVersion?.ToString() ?? "null"} != current {current.Value}",
                    retryable: false,
                    serverTs,
                    details: new Dictionary<string, object?>
                    {
                        ["currentRemoteVersion"] = current.Value,
                        ["entityType"] = operation.EntityType,
                        ["entityId"] = operation.EntityId
                    });
            }
        }

        // FAZ 1 shadow path for non-customer-create operations.
        var eventId = Guid.NewGuid().ToString("D");
        var shadowVersion = operation.OperationType == OperationTypes.Delete
            ? (_versions.Get(operation.EntityType, operation.EntityId) ?? 0)
            : _versions.PutNext(operation.EntityType, operation.EntityId);

        var receipt = new IdempotencyReceipt(
            operation.IdempotencyKey,
            operation.OperationId,
            eventId,
            shadowVersion,
            operation.EntityType,
            operation.EntityId,
            now);
        _idempotency.Put(receipt);

        return BuildAcceptedResult(connection, operation, eventId, shadowVersion, serverTs);
    }

    private static bool IsConnectivityProbe(OperationSubmitPayload operation) =>
        operation.EntityId.StartsWith("shadow-probe-", StringComparison.OrdinalIgnoreCase);

    private OperationProcessResult AcceptConnectivityProbe(
        GatewayConnection connection,
        OperationSubmitPayload operation,
        DateTimeOffset now,
        string serverTs)
    {
        var eventId = Guid.NewGuid().ToString("D");
        var shadowVersion = operation.OperationType == OperationTypes.Delete
            ? (_versions.Get(operation.EntityType, operation.EntityId) ?? 0)
            : _versions.PutNext(operation.EntityType, operation.EntityId);

        var receipt = new IdempotencyReceipt(
            operation.IdempotencyKey,
            operation.OperationId,
            eventId,
            shadowVersion,
            operation.EntityType,
            operation.EntityId,
            now);
        _idempotency.Put(receipt);

        return BuildAcceptedResult(connection, operation, eventId, shadowVersion, serverTs);
    }

    private async Task<OperationProcessResult> ProcessCustomerCreateAsync(
        GatewayConnection connection,
        OperationSubmitPayload operation,
        DateTimeOffset now,
        string serverTs,
        CancellationToken cancellationToken)
    {
        var writeResult = await _customerCreateWriter
            .ApplyAsync(operation, now, cancellationToken)
            .ConfigureAwait(false);

        return writeResult.Kind switch
        {
            CustomerCreateWriteKind.Duplicate => new OperationProcessResult(
                new OpAckPayload
                {
                    OperationId = operation.OperationId,
                    IdempotencyKey = operation.IdempotencyKey,
                    Status = AckStatuses.Duplicate,
                    EventId = writeResult.EventId,
                    RemoteVersion = writeResult.RemoteVersion,
                    ServerTimeStamp = serverTs,
                    CorrelationId = operation.CorrelationId
                },
                Event: null,
                Kind: OperationProcessKind.Duplicate),
            CustomerCreateWriteKind.Error => Reject(
                operation,
                AckStatuses.Error,
                writeResult.ErrorCode ?? "error",
                writeResult.ErrorMessage ?? "customer create failed",
                writeResult.Retryable,
                serverTs),
            CustomerCreateWriteKind.Accepted => BuildAcceptedResult(
                connection,
                operation,
                writeResult.EventId!,
                writeResult.RemoteVersion!.Value,
                serverTs),
            _ => Reject(
                operation,
                AckStatuses.Error,
                "error",
                "customer create failed",
                retryable: true,
                serverTs)
        };
    }

    private static OperationProcessResult BuildAcceptedResult(
        GatewayConnection connection,
        OperationSubmitPayload operation,
        string eventId,
        int remoteVersion,
        string serverTs)
    {
        var ack = new OpAckPayload
        {
            OperationId = operation.OperationId,
            IdempotencyKey = operation.IdempotencyKey,
            Status = AckStatuses.Accepted,
            EventId = eventId,
            RemoteVersion = remoteVersion,
            ServerTimeStamp = serverTs,
            CorrelationId = operation.CorrelationId
        };

        var evt = new EventApplyPayload
        {
            EventId = eventId,
            OperationId = operation.OperationId,
            IdempotencyKey = operation.IdempotencyKey,
            EntityType = operation.EntityType,
            EntityId = operation.EntityId,
            OperationType = operation.OperationType,
            RemoteVersion = remoteVersion,
            ActorUserId = connection.UserId!,
            ServerTimestamp = serverTs,
            Payload = operation.Payload,
            Causation = "accepted",
            CorrelationId = operation.CorrelationId
        };

        return new OperationProcessResult(ack, evt, OperationProcessKind.Accepted);
    }

    private static string? ValidateShape(OperationSubmitPayload operation)
    {
        if (string.IsNullOrWhiteSpace(operation.OperationId))
            return "operationId is required";
        if (string.IsNullOrWhiteSpace(operation.IdempotencyKey))
            return "idempotencyKey is required";
        if (string.IsNullOrWhiteSpace(operation.EntityType))
            return "entityType is required";
        if (string.IsNullOrWhiteSpace(operation.EntityId))
            return "entityId is required";
        if (string.IsNullOrWhiteSpace(operation.OperationType))
            return "operationType is required";
        if (string.IsNullOrWhiteSpace(operation.ActorUserId))
            return "actorUserId is required";
        if (!EntityTypes.Faz1Supported.Contains(operation.EntityType))
            return $"entityType '{operation.EntityType}' is not supported in FAZ 1";
        if (operation.OperationType is not (
            OperationTypes.Create or OperationTypes.Update or OperationTypes.Delete))
            return $"operationType '{operation.OperationType}' is invalid";
        if (operation.LocalVersion < 1)
            return "localVersion must be >= 1";
        return null;
    }

    private static OperationProcessResult Reject(
        OperationSubmitPayload operation,
        string status,
        string code,
        string message,
        bool retryable,
        string serverTs,
        Dictionary<string, object?>? details = null)
    {
        var ack = new OpAckPayload
        {
            OperationId = operation.OperationId,
            IdempotencyKey = operation.IdempotencyKey,
            Status = status,
            EventId = null,
            RemoteVersion = null,
            Error = new GatewayErrorPayload
            {
                Code = code,
                Message = message,
                Retryable = retryable,
                Details = details
            },
            ServerTimeStamp = serverTs,
            CorrelationId = operation.CorrelationId
        };
        return new OperationProcessResult(ack, null, MapKind(status));
    }

    private static OperationProcessKind MapKind(string status) => status switch
    {
        AckStatuses.Duplicate => OperationProcessKind.Duplicate,
        AckStatuses.Forbidden => OperationProcessKind.Forbidden,
        AckStatuses.Conflict => OperationProcessKind.Conflict,
        AckStatuses.Invalid => OperationProcessKind.Invalid,
        AckStatuses.Accepted => OperationProcessKind.Accepted,
        _ => OperationProcessKind.Error
    };
}

public enum OperationProcessKind
{
    Accepted,
    Duplicate,
    Forbidden,
    Conflict,
    Invalid,
    Error
}

public sealed record OperationProcessResult(
    OpAckPayload Ack,
    EventApplyPayload? Event,
    OperationProcessKind Kind);
