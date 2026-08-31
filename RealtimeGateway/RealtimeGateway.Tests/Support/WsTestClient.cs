using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using RealtimeGateway.Contracts;
using RealtimeGateway.Core.Auth;
using RealtimeGateway.Core.Firestore;
using RealtimeGateway.Core.Idempotency;
using RealtimeGateway.Tests.Support;

namespace RealtimeGateway.Tests;

public sealed class GatewayWebApplicationFactory : WebApplicationFactory<Program>
{
    public RSA Rsa { get; } = RSA.Create(2048);
    public TestFirebaseTokenVerifier TokenVerifier { get; }

    public GatewayWebApplicationFactory()
    {
        TokenVerifier = new TestFirebaseTokenVerifier(Rsa);
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<IFirebaseTokenVerifier>();
            services.AddSingleton<IFirebaseTokenVerifier>(TokenVerifier);
            services.RemoveAll<ICustomerCreateWriter>();
            services.AddSingleton<ICustomerCreateWriter>(sp =>
                new ParityCustomerCreateWriter(
                    sp.GetRequiredService<IIdempotencyStore>(),
                    sp.GetRequiredService<IShadowVersionStore>()));
        });
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            Rsa.Dispose();
        }

        base.Dispose(disposing);
    }
}

public static class WsTestClient
{
    public static async Task<WebSocket> ConnectAsync(GatewayWebApplicationFactory factory)
    {
        var client = factory.Server.CreateWebSocketClient();
        return await client.ConnectAsync(new Uri("ws://localhost/ws"), CancellationToken.None);
    }

    public static async Task SendAsync(WebSocket socket, GatewayEnvelope envelope)
    {
        var bytes = Encoding.UTF8.GetBytes(GatewayJson.Serialize(envelope));
        await socket.SendAsync(bytes, WebSocketMessageType.Text, true, CancellationToken.None);
    }

    public static async Task<GatewayEnvelope> ReceiveAsync(WebSocket socket, TimeSpan? timeout = null)
    {
        using var cts = new CancellationTokenSource(timeout ?? TimeSpan.FromSeconds(5));
        var buffer = new byte[64 * 1024];
        using var ms = new MemoryStream();
        WebSocketReceiveResult result;
        do
        {
            result = await socket.ReceiveAsync(buffer, cts.Token);
            if (result.MessageType == WebSocketMessageType.Close)
            {
                throw new InvalidOperationException("socket closed while waiting for message");
            }

            ms.Write(buffer, 0, result.Count);
        } while (!result.EndOfMessage);

        var json = Encoding.UTF8.GetString(ms.ToArray());
        return GatewayJson.Deserialize<GatewayEnvelope>(json)
               ?? throw new InvalidOperationException("null envelope");
    }

    public static async Task<GatewayEnvelope> HelloAsync(
        WebSocket socket,
        string idToken,
        string deviceId = "test-device")
    {
        var envelope = new GatewayEnvelope
        {
            V = ProtocolVersion.Current,
            Type = MessageTypes.Hello,
            RequestId = "req-hello",
            Payload = JsonSerializer.SerializeToElement(new HelloPayload
            {
                IdToken = idToken,
                DeviceId = deviceId,
                ProtocolVersion = ProtocolVersion.Current,
                EntitySubscriptions = [EntityTypes.Customer, EntityTypes.WorkOrder]
            }, GatewayJson.Options)
        };
        await SendAsync(socket, envelope);
        return await ReceiveAsync(socket);
    }

    public static T Payload<T>(GatewayEnvelope envelope)
    {
        return GatewayJson.DeserializePayload<T>(envelope.Payload)
               ?? throw new InvalidOperationException($"payload not {typeof(T).Name}");
    }
}
