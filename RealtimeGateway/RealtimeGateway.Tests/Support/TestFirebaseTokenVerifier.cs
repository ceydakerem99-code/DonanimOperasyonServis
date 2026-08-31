using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using Microsoft.IdentityModel.Tokens;
using RealtimeGateway.Contracts;
using RealtimeGateway.Core.Auth;

namespace RealtimeGateway.Tests.Support;

/// <summary>
/// Test-only verifier that validates JWTs signed with a known RSA key.
/// Production host uses <see cref="FirebaseIdTokenVerifier"/> exclusively.
/// </summary>
public sealed class TestFirebaseTokenVerifier : IFirebaseTokenVerifier
{
    public const string Issuer = "realtime-gateway-tests";
    public const string Audience = "donanim-operasyon-servis";

    private readonly RsaSecurityKey _key;
    private readonly string _signingAlgorithm = SecurityAlgorithms.RsaSha256;

    public TestFirebaseTokenVerifier(RSA rsa)
    {
        _key = new RsaSecurityKey(rsa);
    }

    public string IssueToken(string uid, string role, bool isActive = true, TimeSpan? lifetime = null)
    {
        var credentials = new SigningCredentials(_key, _signingAlgorithm);
        var claims = new List<Claim>
        {
            new("user_id", uid),
            new("sub", uid),
            new("role", role),
            new("isActive", isActive ? "true" : "false")
        };
        var token = new JwtSecurityToken(
            issuer: Issuer,
            audience: Audience,
            claims: claims,
            notBefore: DateTime.UtcNow.AddMinutes(-1),
            expires: DateTime.UtcNow.Add(lifetime ?? TimeSpan.FromHours(1)),
            signingCredentials: credentials);
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public Task<VerifiedIdentity?> VerifyAsync(string idToken, CancellationToken cancellationToken)
    {
        try
        {
            var handler = new JwtSecurityTokenHandler
            {
                MapInboundClaims = false
            };
            var principal = handler.ValidateToken(idToken, new TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidIssuer = Issuer,
                ValidateAudience = true,
                ValidAudience = Audience,
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = _key,
                ValidateLifetime = true,
                ClockSkew = TimeSpan.FromMinutes(1)
            }, out _);

            var uid = principal.FindFirst("user_id")?.Value
                      ?? principal.FindFirst("sub")?.Value;
            if (string.IsNullOrWhiteSpace(uid))
            {
                return Task.FromResult<VerifiedIdentity?>(null);
            }

            var role = principal.FindFirst("role")?.Value
                       ?? principal.FindFirst(ClaimTypes.Role)?.Value
                       ?? UserRoles.Unknown;
            var isActiveClaim = principal.FindFirst("isActive")?.Value;
            var isActive = isActiveClaim is null || bool.Parse(isActiveClaim);
            var claims = principal.Claims.ToDictionary(c => c.Type, c => (object)c.Value, StringComparer.Ordinal);
            return Task.FromResult<VerifiedIdentity?>(new VerifiedIdentity(uid, role, isActive, claims));
        }
        catch
        {
            return Task.FromResult<VerifiedIdentity?>(null);
        }
    }
}
