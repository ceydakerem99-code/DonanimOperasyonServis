using FirebaseAdmin;
using FirebaseAdmin.Auth;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using RealtimeGateway.Contracts;

namespace RealtimeGateway.Core.Auth;

public sealed class FirebaseAuthOptions
{
    /// <summary>
    /// Path to a Firebase service-account JSON. When empty, GOOGLE_APPLICATION_CREDENTIALS
    /// and Application Default Credentials are used.
    /// </summary>
    public string? CredentialPath { get; set; }

    /// <summary>Optional Firebase project id override.</summary>
    public string? ProjectId { get; set; }

    /// <summary>
    /// Smoke-only: when the ID token has no <c>role</c> custom claim, use this role
    /// (e.g. <c>operator</c>). Leave empty in production. Does not write Firestore.
    /// </summary>
    public string? DevelopmentRoleFallback { get; set; }
}

/// <summary>
/// Production verifier using Firebase Admin SDK. Does not accept unsigned/forged tokens.
/// Initialization is lazy so the host can boot before credentials are configured.
/// </summary>
public sealed class FirebaseIdTokenVerifier : IFirebaseTokenVerifier
{
    private readonly ILogger<FirebaseIdTokenVerifier> _logger;
    private readonly FirebaseAuthOptions _options;
    private readonly object _initLock = new();
    private bool _initAttempted;
    private bool _initSucceeded;

    public FirebaseIdTokenVerifier(
        IOptions<FirebaseAuthOptions> options,
        ILogger<FirebaseIdTokenVerifier> logger)
    {
        _options = options.Value;
        _logger = logger;
    }

    public async Task<VerifiedIdentity?> VerifyAsync(string idToken, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(idToken))
        {
            return null;
        }

        if (!TryEnsureFirebaseApp())
        {
            var diagnostics = FirebaseCredentialResolver.Describe(_options);
            _logger.LogError(
                "Firebase Admin is not configured. configured={Configured} source={Source} projectId={ProjectId}. Set FirebaseAuth:CredentialPath or {EnvVar}.",
                diagnostics.Configured,
                diagnostics.CredentialSource,
                diagnostics.ProjectId ?? "unset",
                FirebaseCredentialResolver.GoogleApplicationCredentialsEnvVar);
            return null;
        }

        try
        {
            var decoded = await FirebaseAuth.DefaultInstance
                .VerifyIdTokenAsync(idToken, cancellationToken)
                .ConfigureAwait(false);

#if DEBUG
            _logger.LogDebug(
                "ID token claim keys=[{ClaimKeys}] rolePresent={RolePresent}",
                string.Join(",", decoded.Claims.Keys.OrderBy(static key => key, StringComparer.Ordinal)),
                decoded.Claims.ContainsKey("role"));
#endif

            var role = FirebaseTokenClaimReader.ExtractRole(decoded.Claims);
            if (role == UserRoles.Unknown
                && !string.IsNullOrWhiteSpace(_options.DevelopmentRoleFallback))
            {
                role = _options.DevelopmentRoleFallback.Trim().ToLowerInvariant();
                _logger.LogWarning(
                    "ID token has no role claim; applying DevelopmentRoleFallback={Role} (smoke only)",
                    role);
            }

            var isActive = FirebaseTokenClaimReader.ExtractIsActive(decoded.Claims);
            return new VerifiedIdentity(decoded.Uid, role, isActive, decoded.Claims);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Firebase ID token verification failed");
            return null;
        }
    }

    private bool TryEnsureFirebaseApp()
    {
        if (FirebaseApp.DefaultInstance is not null)
        {
            _initSucceeded = true;
            return true;
        }

        lock (_initLock)
        {
            if (FirebaseApp.DefaultInstance is not null)
            {
                _initSucceeded = true;
                return true;
            }

            if (_initAttempted)
            {
                return _initSucceeded;
            }

            _initAttempted = true;
            try
            {
                if (!FirebaseCredentialResolver.TryResolve(_options, _logger, out var resolution)
                    || resolution is null)
                {
                    _initSucceeded = false;
                    return false;
                }

                var projectId = ResolveProjectId(resolution);
                var appOptions = new AppOptions
                {
                    Credential = resolution.Credential,
                    ProjectId = projectId
                };
                FirebaseApp.Create(appOptions);
                _initSucceeded = true;
                _logger.LogInformation(
                    "FirebaseApp initialized for ID token verification (source={Source}, projectId={ProjectId})",
                    resolution.Source,
                    projectId ?? "unset");
                return true;
            }
            catch (Exception ex)
            {
                _initSucceeded = false;
                _logger.LogError(ex, "Failed to initialize FirebaseApp for token verification");
                return false;
            }
        }
    }

    private string? ResolveProjectId(FirebaseCredentialResolution resolution)
    {
        if (!string.IsNullOrWhiteSpace(_options.ProjectId))
        {
            return _options.ProjectId.Trim();
        }

        return resolution.ProjectIdFromCredential;
    }
}
