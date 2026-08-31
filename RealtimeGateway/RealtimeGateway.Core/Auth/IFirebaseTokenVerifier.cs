namespace RealtimeGateway.Core.Auth;

public sealed record VerifiedIdentity(
    string Uid,
    string Role,
    bool IsActive,
    IReadOnlyDictionary<string, object> Claims);

public interface IFirebaseTokenVerifier
{
    /// <summary>
    /// Verifies a Firebase Auth ID token (or a cryptographically equivalent
    /// token in test hosts). Returns null when verification fails.
    /// </summary>
    Task<VerifiedIdentity?> VerifyAsync(string idToken, CancellationToken cancellationToken);
}
