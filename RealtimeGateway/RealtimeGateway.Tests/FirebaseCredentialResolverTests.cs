using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Logging.Abstractions;
using RealtimeGateway.Core.Auth;

namespace RealtimeGateway.Tests;

public sealed class FirebaseCredentialResolverTests
{
    [Fact]
    public void Describe_reports_missing_credential_sources()
    {
        var previous = Environment.GetEnvironmentVariable(FirebaseCredentialResolver.GoogleApplicationCredentialsEnvVar);
        Environment.SetEnvironmentVariable(FirebaseCredentialResolver.GoogleApplicationCredentialsEnvVar, null);

        try
        {
            var diagnostics = FirebaseCredentialResolver.Describe(new FirebaseAuthOptions
            {
                CredentialPath = null,
                ProjectId = "donanimoperasyonservis"
            });

            Assert.Equal("donanimoperasyonservis", diagnostics.ProjectId);
            Assert.False(diagnostics.Configured);
            Assert.Equal(FirebaseCredentialSource.None, diagnostics.CredentialSource);
            Assert.False(diagnostics.CredentialPathConfigured);
            Assert.False(diagnostics.GoogleApplicationCredentialsSet);
        }
        finally
        {
            Environment.SetEnvironmentVariable(
                FirebaseCredentialResolver.GoogleApplicationCredentialsEnvVar,
                previous);
        }
    }

    [Fact]
    public void TryResolve_uses_configured_credential_path()
    {
        var path = WriteTemporaryServiceAccount("configured-project");
        var options = new FirebaseAuthOptions
        {
            CredentialPath = path,
            ProjectId = "donanimoperasyonservis"
        };

        var resolved = FirebaseCredentialResolver.TryResolve(
            options,
            NullLogger.Instance,
            out var resolution);

        Assert.True(resolved);
        Assert.NotNull(resolution);
        Assert.Equal(FirebaseCredentialSource.CredentialPath, resolution!.Source);
        Assert.Equal("configured-project", resolution.ProjectIdFromCredential);
    }

    [Fact]
    public void TryResolve_uses_google_application_credentials_when_configured_path_missing()
    {
        var path = WriteTemporaryServiceAccount("env-project");
        var previous = Environment.GetEnvironmentVariable(FirebaseCredentialResolver.GoogleApplicationCredentialsEnvVar);

        try
        {
            Environment.SetEnvironmentVariable(FirebaseCredentialResolver.GoogleApplicationCredentialsEnvVar, path);

            var resolved = FirebaseCredentialResolver.TryResolve(
                new FirebaseAuthOptions
                {
                    CredentialPath = Path.Combine(Path.GetTempPath(), "missing-service-account.json"),
                    ProjectId = "donanimoperasyonservis"
                },
                NullLogger.Instance,
                out var resolution);

            Assert.True(resolved);
            Assert.NotNull(resolution);
            Assert.Equal(FirebaseCredentialSource.GoogleApplicationCredentials, resolution!.Source);
            Assert.Equal("env-project", resolution.ProjectIdFromCredential);
        }
        finally
        {
            Environment.SetEnvironmentVariable(
                FirebaseCredentialResolver.GoogleApplicationCredentialsEnvVar,
                previous);
        }
    }

    [Fact]
    public void TryResolve_fails_when_no_credential_source_exists()
    {
        var previous = Environment.GetEnvironmentVariable(FirebaseCredentialResolver.GoogleApplicationCredentialsEnvVar);
        Environment.SetEnvironmentVariable(FirebaseCredentialResolver.GoogleApplicationCredentialsEnvVar, null);

        try
        {
            var resolved = FirebaseCredentialResolver.TryResolve(
                new FirebaseAuthOptions
                {
                    CredentialPath = Path.Combine(Path.GetTempPath(), "missing-service-account.json"),
                    ProjectId = "donanimoperasyonservis"
                },
                NullLogger.Instance,
                out var resolution);

            Assert.False(resolved);
            Assert.Null(resolution);
        }
        finally
        {
            Environment.SetEnvironmentVariable(
                FirebaseCredentialResolver.GoogleApplicationCredentialsEnvVar,
                previous);
        }
    }

    [Fact]
    public void TryResolve_rejects_invalid_service_account_json()
    {
        var path = Path.Combine(Path.GetTempPath(), $"invalid-service-account-{Guid.NewGuid():N}.json");
        File.WriteAllText(path, "{ \"type\": \"service_account\" }");

        try
        {
            var resolved = FirebaseCredentialResolver.TryResolve(
                new FirebaseAuthOptions { CredentialPath = path, ProjectId = "donanimoperasyonservis" },
                NullLogger.Instance,
                out var resolution);

            Assert.False(resolved);
            Assert.Null(resolution);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public async Task FirebaseIdTokenVerifier_rejects_invalid_token_when_credential_is_configured()
    {
        var path = WriteTemporaryServiceAccount("donanimoperasyonservis");
        var verifier = new FirebaseIdTokenVerifier(
            Microsoft.Extensions.Options.Options.Create(new FirebaseAuthOptions
            {
                CredentialPath = path,
                ProjectId = "donanimoperasyonservis"
            }),
            NullLogger<FirebaseIdTokenVerifier>.Instance);

        var identity = await verifier.VerifyAsync("not-a-valid-firebase-id-token", CancellationToken.None);

        Assert.Null(identity);
    }

    private static string WriteTemporaryServiceAccount(string projectId)
    {
        using var rsa = RSA.Create(2048);
        var privateKey = rsa.ExportPkcs8PrivateKey();
        var pem = new StringBuilder()
            .AppendLine("-----BEGIN PRIVATE KEY-----")
            .AppendLine(Convert.ToBase64String(privateKey, Base64FormattingOptions.InsertLineBreaks))
            .AppendLine("-----END PRIVATE KEY-----")
            .ToString();

        var path = Path.Combine(Path.GetTempPath(), $"firebase-service-account-{Guid.NewGuid():N}.json");
        var json = $$"""
                     {
                       "type": "service_account",
                       "project_id": "{{projectId}}",
                       "private_key_id": "test-key-id",
                       "private_key": {{System.Text.Json.JsonSerializer.Serialize(pem)}},
                       "client_email": "gateway-test@{{projectId}}.iam.gserviceaccount.com",
                       "client_id": "1234567890",
                       "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                       "token_uri": "https://oauth2.googleapis.com/token",
                       "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
                       "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/gateway-test"
                     }
                     """;
        File.WriteAllText(path, json);
        return path;
    }
}
