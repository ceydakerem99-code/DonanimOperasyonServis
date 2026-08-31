using RealtimeGateway.Contracts;

namespace RealtimeGateway.Core.Auth;

/// <summary>
/// Role checks for FAZ 1 shadow mode. Does not trust client-supplied actorUserId;
/// the authenticated connection UID/role are authoritative.
/// </summary>
public static class AuthorizationPolicy
{
    public static bool CanSubmit(string role, string entityType, string operationType)
    {
        role = role.Trim().ToLowerInvariant();
        entityType = entityType.Trim();
        operationType = operationType.Trim().ToLowerInvariant();

        if (!EntityTypes.Faz1Supported.Contains(entityType))
        {
            return false;
        }

        return role switch
        {
            UserRoles.Admin => true,
            UserRoles.Operator => entityType is EntityTypes.Customer or EntityTypes.WorkOrder
                && operationType is OperationTypes.Create or OperationTypes.Update or OperationTypes.Delete,
            UserRoles.Technician => entityType == EntityTypes.WorkOrder
                && operationType == OperationTypes.Update,
            _ => false
        };
    }
}
