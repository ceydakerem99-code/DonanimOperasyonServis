using Newtonsoft.Json.Linq;
using RealtimeGateway.Contracts;

namespace RealtimeGateway.Core.Auth;

/// <summary>
/// Reads Firebase ID token custom claims produced by <see cref="FirebaseIdTokenVerifier"/>.
/// Separated for unit testing claim coercion (string vs Newtonsoft wrappers).
/// </summary>
internal static class FirebaseTokenClaimReader
{
    public static string ExtractRole(IReadOnlyDictionary<string, object> claims)
    {
        if (!claims.TryGetValue("role", out var roleObj) || roleObj is null)
        {
            return UserRoles.Unknown;
        }

        var role = CoerceClaimString(roleObj);
        if (string.IsNullOrWhiteSpace(role))
        {
            return UserRoles.Unknown;
        }

        return role.Trim().ToLowerInvariant();
    }

    public static bool ExtractIsActive(IReadOnlyDictionary<string, object> claims)
    {
        if (!claims.TryGetValue("isActive", out var activeObj) || activeObj is null)
        {
            return true;
        }

        return activeObj switch
        {
            bool b => b,
            string s when bool.TryParse(s, out var parsed) => parsed,
            JValue jv when jv.Type == JTokenType.Boolean => jv.Value<bool>(),
            JToken jt when jt.Type == JTokenType.Boolean => jt.Value<bool>(),
            JValue jv when jv.Type == JTokenType.String
                && bool.TryParse(jv.Value<string>(), out var parsedFromJv) => parsedFromJv,
            JToken jt when jt.Type == JTokenType.String
                && bool.TryParse(jt.Value<string>(), out var parsedFromJt) => parsedFromJt,
            _ => true
        };
    }

    internal static string? CoerceClaimString(object value)
    {
        switch (value)
        {
            case string s:
                return s;
            case JValue { Type: JTokenType.String } jv:
                return jv.Value<string>();
            case JToken { Type: JTokenType.String } jt:
                return jt.Value<string>();
            default:
                return null;
        }
    }
}
