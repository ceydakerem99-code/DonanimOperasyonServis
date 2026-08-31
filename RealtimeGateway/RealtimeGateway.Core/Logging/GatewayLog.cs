using Microsoft.Extensions.Logging;

namespace RealtimeGateway.Core.Logging;

public static class GatewayLog
{
    public static void Connect(ILogger logger, string connectionId) =>
        logger.LogInformation("CONNECT connectionId={ConnectionId}", connectionId);

    public static void Authenticated(ILogger logger, string connectionId, string userId, string role) =>
        logger.LogInformation(
            "AUTHENTICATED connectionId={ConnectionId} userId={UserId} role={Role}",
            connectionId,
            userId,
            role);

    public static void AuthFailed(ILogger logger, string connectionId, string reason) =>
        logger.LogWarning(
            "AUTH_FAILED connectionId={ConnectionId} reason={Reason}",
            connectionId,
            reason);

    public static void EventReceived(
        ILogger logger,
        string connectionId,
        string operationId,
        string idempotencyKey,
        string entityType,
        string entityId) =>
        logger.LogInformation(
            "EVENT_RECEIVED connectionId={ConnectionId} operationId={OperationId} idempotencyKey={IdempotencyKey} entityType={EntityType} entityId={EntityId}",
            connectionId,
            operationId,
            idempotencyKey,
            entityType,
            entityId);

    public static void AckSent(ILogger logger, string connectionId, string operationId, string status) =>
        logger.LogInformation(
            "ACK_SENT connectionId={ConnectionId} operationId={OperationId} status={Status}",
            connectionId,
            operationId,
            status);

    public static void Duplicate(ILogger logger, string connectionId, string idempotencyKey, string eventId) =>
        logger.LogInformation(
            "DUPLICATE connectionId={ConnectionId} idempotencyKey={IdempotencyKey} eventId={EventId}",
            connectionId,
            idempotencyKey,
            eventId);

    public static void Forbidden(ILogger logger, string connectionId, string userId, string reason) =>
        logger.LogWarning(
            "FORBIDDEN connectionId={ConnectionId} userId={UserId} reason={Reason}",
            connectionId,
            userId,
            reason);

    public static void Disconnected(ILogger logger, string connectionId, string? userId) =>
        logger.LogInformation(
            "DISCONNECTED connectionId={ConnectionId} userId={UserId}",
            connectionId,
            userId ?? "-");
}
