using Microsoft.Extensions.Options;
using RealtimeGateway.Core.Auth;
using RealtimeGateway.Core.Connections;
using RealtimeGateway.Core.Firestore;
using RealtimeGateway.Core.Idempotency;
using RealtimeGateway.Core.Pipeline;
using RealtimeGateway.Host.WebSockets;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<FirebaseAuthOptions>(options =>
{
    builder.Configuration.GetSection("FirebaseAuth").Bind(options);
    if (!string.IsNullOrWhiteSpace(options.CredentialPath) && !Path.IsPathRooted(options.CredentialPath))
    {
        options.CredentialPath = Path.Combine(builder.Environment.ContentRootPath, options.CredentialPath);
    }
});

builder.Services.AddSingleton<IConnectionManager, ConnectionManager>();
builder.Services.AddSingleton<IIdempotencyStore, InMemoryIdempotencyStore>();
builder.Services.AddSingleton<IShadowVersionStore, InMemoryShadowVersionStore>();
builder.Services.AddSingleton<ICustomerCreateWriter, FirestoreCustomerCreateWriter>();
builder.Services.AddSingleton<OperationProcessor>();
builder.Services.AddSingleton<GatewayWebSocketHandler>();

// Production default: real Firebase Admin ID token verification.
// Tests replace IFirebaseTokenVerifier via WebApplicationFactory.
builder.Services.AddSingleton<IFirebaseTokenVerifier, FirebaseIdTokenVerifier>();

var configuredUrls = builder.Configuration["Urls"];
var defaultUrls = builder.Environment.IsDevelopment()
    ? "http://0.0.0.0:5088"
    : "http://127.0.0.1:5088";
builder.WebHost.UseUrls(string.IsNullOrWhiteSpace(configuredUrls) ? defaultUrls : configuredUrls);

var app = builder.Build();

app.UseWebSockets(new WebSocketOptions
{
    KeepAliveInterval = TimeSpan.FromSeconds(30)
});

app.MapGet("/health", (IOptions<FirebaseAuthOptions> firebaseOptions) =>
{
    var diagnostics = FirebaseCredentialResolver.Describe(firebaseOptions.Value);
    return Results.Ok(new
    {
        status = "ok",
        mode = "faz4a-customer-create",
        firestoreMutations = true,
        customerCreate = true,
        websocket = "/ws",
        firebase = new
        {
            environment = diagnostics.Environment,
            configured = diagnostics.Configured,
            credentialSource = diagnostics.CredentialSource.ToString(),
            projectId = diagnostics.ProjectId,
            credentialPathConfigured = diagnostics.CredentialPathConfigured,
            credentialPathExists = diagnostics.CredentialPathExists,
            googleApplicationCredentialsSet = diagnostics.GoogleApplicationCredentialsSet,
            googleApplicationCredentialsExists = diagnostics.GoogleApplicationCredentialsExists
        }
    });
});

app.Map("/ws", async (HttpContext context, GatewayWebSocketHandler handler) =>
{
    await handler.HandleAsync(context, context.RequestAborted);
});

app.Run();

public partial class Program;
