using Newtonsoft.Json.Linq;
using RealtimeGateway.Contracts;
using RealtimeGateway.Core.Auth;

namespace RealtimeGateway.Tests;

public sealed class FirebaseTokenClaimReaderTests
{
    [Fact]
    public void ExtractRole_reads_string_claim()
    {
        var role = FirebaseTokenClaimReader.ExtractRole(new Dictionary<string, object>
        {
            ["role"] = "operator"
        });

        Assert.Equal(UserRoles.Operator, role);
    }

    [Fact]
    public void ExtractRole_reads_jvalue_string_claim()
    {
        var role = FirebaseTokenClaimReader.ExtractRole(new Dictionary<string, object>
        {
            ["role"] = new JValue("technician")
        });

        Assert.Equal(UserRoles.Technician, role);
    }

    [Fact]
    public void ExtractRole_reads_jtoken_string_claim()
    {
        var role = FirebaseTokenClaimReader.ExtractRole(new Dictionary<string, object>
        {
            ["role"] = JToken.FromObject("admin")
        });

        Assert.Equal(UserRoles.Admin, role);
    }

    [Fact]
    public void ExtractRole_normalizes_case_and_whitespace()
    {
        var role = FirebaseTokenClaimReader.ExtractRole(new Dictionary<string, object>
        {
            ["role"] = "  Operator  "
        });

        Assert.Equal(UserRoles.Operator, role);
    }

    [Fact]
    public void ExtractRole_returns_unknown_when_claim_missing()
    {
        var role = FirebaseTokenClaimReader.ExtractRole(new Dictionary<string, object>());
        Assert.Equal(UserRoles.Unknown, role);
    }

    [Fact]
    public void ExtractRole_returns_unknown_when_claim_null()
    {
        var role = FirebaseTokenClaimReader.ExtractRole(new Dictionary<string, object>
        {
            ["role"] = null!
        });

        Assert.Equal(UserRoles.Unknown, role);
    }

    [Fact]
    public void ExtractRole_returns_unknown_when_claim_empty()
    {
        var role = FirebaseTokenClaimReader.ExtractRole(new Dictionary<string, object>
        {
            ["role"] = string.Empty
        });

        Assert.Equal(UserRoles.Unknown, role);
    }

    [Fact]
    public void ExtractRole_returns_unknown_when_claim_whitespace()
    {
        var role = FirebaseTokenClaimReader.ExtractRole(new Dictionary<string, object>
        {
            ["role"] = "   "
        });

        Assert.Equal(UserRoles.Unknown, role);
    }

    [Fact]
    public void ExtractRole_returns_unknown_for_non_string_wrappers()
    {
        var role = FirebaseTokenClaimReader.ExtractRole(new Dictionary<string, object>
        {
            ["role"] = 42
        });

        Assert.Equal(UserRoles.Unknown, role);
    }

    [Fact]
    public void ExtractRole_preserves_unrecognized_role_string()
    {
        var role = FirebaseTokenClaimReader.ExtractRole(new Dictionary<string, object>
        {
            ["role"] = "custom-role"
        });

        Assert.Equal("custom-role", role);
    }
}
