using System.Text.Json;
using Google.Apis.Auth.OAuth2;
using Microsoft.Extensions.Logging;

namespace RealtimeGateway.Core.Auth;

public enum FirebaseCredentialSource
{
    None = 0,
    CredentialPath = 1,
    GoogleApplicationCredentials = 2,
    ApplicationDefault = 3
}

public sealed class FirebaseCredentialResolution
{
    public required GoogleCredential Credential { get; init; }
    public FirebaseCredentialSource Source { get; init; }
    public string? ProjectIdFromCredential { get; init; }

    public bool IsConfigured => Source is not FirebaseCredentialSource.None;
}

/// <summary>
/// Resolves Firebase Admin / Firestore credentials in a fixed order:
/// 1. <see cref="FirebaseAuthOptions.CredentialPath"/>
/// 2. <c>GOOGLE_APPLICATION_CREDENTIALS</c>
/// 3. Application Default Credentials
/// </summary>
public static class FirebaseCredentialResolver
{
    public const string GoogleApplicationCredentialsEnvVar = "GOOGLE_APPLICATION_CREDENTIALS";

    public static bool TryResolve(
        FirebaseAuthOptions options,
        ILogger logger,
        out FirebaseCredentialResolution? resolution)
    {
        resolution = null;

        if (TryLoadFromConfiguredPath(options.CredentialPath, logger, out resolution))
        {
            return true;
        }

        var envPath = Environment.GetEnvironmentVariable(GoogleApplicationCredentialsEnvVar);
        if (TryLoadFromPath(
                envPath,
                FirebaseCredentialSource.GoogleApplicationCredentials,
                logger,
                out resolution))
        {
            return true;
        }

        try
        {
            var credential = GoogleCredential.GetApplicationDefault();
            resolution = new FirebaseCredentialResolution
            {
                Credential = credential,
                Source = FirebaseCredentialSource.ApplicationDefault,
                ProjectIdFromCredential = null
            };
            logger.LogInformation(
                "Firebase credential resolved from Application Default Credentials (Environment={Environment})",
                Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "unknown");
            return true;
        }
        catch (Exception ex)
        {
            logger.LogError(
                ex,
                "Firebase credential resolution failed. Configure FirebaseAuth:CredentialPath, set {EnvVar}, or use ADC.",
                GoogleApplicationCredentialsEnvVar);
            return false;
        }
    }

    public static FirebaseCredentialDiagnostics Describe(FirebaseAuthOptions options)
    {
        var configuredPath = NormalizePath(options.CredentialPath);
        var envPath = NormalizePath(Environment.GetEnvironmentVariable(GoogleApplicationCredentialsEnvVar));

        var source = FirebaseCredentialSource.None;
        if (configuredPath is not null && File.Exists(configuredPath))
        {
            source = FirebaseCredentialSource.CredentialPath;
        }
        else if (envPath is not null && File.Exists(envPath))
        {
            source = FirebaseCredentialSource.GoogleApplicationCredentials;
        }

        return new FirebaseCredentialDiagnostics
        {
            Environment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Production",
            Configured = source is not FirebaseCredentialSource.None,
            CredentialSource = source,
            ProjectId = string.IsNullOrWhiteSpace(options.ProjectId) ? null : options.ProjectId.Trim(),
            CredentialPathConfigured = !string.IsNullOrWhiteSpace(options.CredentialPath),
            CredentialPathExists = configuredPath is not null && File.Exists(configuredPath),
            GoogleApplicationCredentialsSet = !string.IsNullOrWhiteSpace(envPath),
            GoogleApplicationCredentialsExists = envPath is not null && File.Exists(envPath)
        };
    }

    private static bool TryLoadFromConfiguredPath(
        string? configuredPath,
        ILogger logger,
        out FirebaseCredentialResolution? resolution)
    {
        resolution = null;
        var normalized = NormalizePath(configuredPath);
        if (normalized is null)
        {
            return false;
        }

        if (!File.Exists(normalized))
        {
            logger.LogWarning(
                "FirebaseAuth:CredentialPath is configured but the file was not found (configured=true, exists=false)");
            return false;
        }

        return TryLoadFromPath(normalized, FirebaseCredentialSource.CredentialPath, logger, out resolution);
    }

    private static bool TryLoadFromPath(
        string? path,
        FirebaseCredentialSource source,
        ILogger logger,
        out FirebaseCredentialResolution? resolution)
    {
        resolution = null;
        var normalized = NormalizePath(path);
        if (normalized is null || !File.Exists(normalized))
        {
            return false;
        }

        try
        {
            var credential = GoogleCredential.FromFile(normalized);
            var projectId = TryReadProjectIdFromServiceAccountFile(normalized);
            resolution = new FirebaseCredentialResolution
            {
                Credential = credential,
                Source = source,
                ProjectIdFromCredential = projectId
            };
            logger.LogInformation(
                "Firebase credential resolved (source={Source}, projectId={ProjectId})",
                source,
                projectId ?? "unknown");
            return true;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to load Firebase credential (source={Source})", source);
            return false;
        }
    }

    private static string? NormalizePath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return null;
        }

        return Path.GetFullPath(path.Trim());
    }

    internal static string? TryReadProjectIdFromServiceAccountFile(string path)
    {
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            if (document.RootElement.TryGetProperty("project_id", out var projectId)
                && projectId.ValueKind == JsonValueKind.String)
            {
                var value = projectId.GetString();
                return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
            }
        }
        catch
        {
            // Diagnostics only; caller handles credential load failures separately.
        }

        return null;
    }
}

public sealed class FirebaseCredentialDiagnostics
{
    public required string Environment { get; init; }
    public required bool Configured { get; init; }
    public FirebaseCredentialSource CredentialSource { get; init; }
    public string? ProjectId { get; init; }
    public bool CredentialPathConfigured { get; init; }
    public bool CredentialPathExists { get; init; }
    public bool GoogleApplicationCredentialsSet { get; init; }
    public bool GoogleApplicationCredentialsExists { get; init; }
}
