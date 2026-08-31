using RealtimeGateway.Contracts;

namespace RealtimeGateway.Core.Firestore;

public enum CustomerCreateWriteKind
{
    Accepted,
    Duplicate,
    Error
}

public sealed record CustomerCreateWriteResult(
    CustomerCreateWriteKind Kind,
    string? EventId,
    int? RemoteVersion,
    string? ErrorCode,
    string? ErrorMessage,
    bool Retryable)
{
    public static CustomerCreateWriteResult Accepted(string eventId, int remoteVersion) =>
        new(CustomerCreateWriteKind.Accepted, eventId, remoteVersion, null, null, false);

    public static CustomerCreateWriteResult Duplicate(string eventId, int remoteVersion) =>
        new(CustomerCreateWriteKind.Duplicate, eventId, remoteVersion, null, null, false);

    public static CustomerCreateWriteResult Error(string code, string message, bool retryable) =>
        new(CustomerCreateWriteKind.Error, null, null, code, message, retryable);
}

public interface ICustomerCreateWriter
{
    Task<CustomerCreateWriteResult> ApplyAsync(
        OperationSubmitPayload operation,
        DateTimeOffset now,
        CancellationToken cancellationToken = default);
}
