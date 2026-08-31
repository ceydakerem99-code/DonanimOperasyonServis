using System.Text.Json;
using Google.Cloud.Firestore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using RealtimeGateway.Contracts;
using RealtimeGateway.Core.Auth;

namespace RealtimeGateway.Core.Firestore;

/// <summary>
/// FAZ 4A: transactional customer create at customers/{id} + operationReceipts/{idempotencyKey}.
/// </summary>
public sealed class FirestoreCustomerCreateWriter : ICustomerCreateWriter
{
    private const string CustomersCollection = "customers";
    private const string ReceiptsCollection = "operationReceipts";

    private readonly FirebaseAuthOptions _options;
    private readonly ILogger<FirestoreCustomerCreateWriter> _logger;
    private readonly object _initLock = new();
    private FirestoreDb? _db;
    private bool _initAttempted;
    private bool _initSucceeded;

    public FirestoreCustomerCreateWriter(
        IOptions<FirebaseAuthOptions> options,
        ILogger<FirestoreCustomerCreateWriter> logger)
    {
        _options = options.Value;
        _logger = logger;
    }

    public async Task<CustomerCreateWriteResult> ApplyAsync(
        OperationSubmitPayload operation,
        DateTimeOffset now,
        CancellationToken cancellationToken = default)
    {
        if (!TryEnsureFirestoreDb())
        {
            return CustomerCreateWriteResult.Error(
                "firestoreUnavailable",
                "Firestore is not configured. Set FirebaseAuth:CredentialPath or GOOGLE_APPLICATION_CREDENTIALS.",
                retryable: true);
        }

        var payloadError = CustomerCreatePayload.TryParse(operation, out var payload);
        if (payloadError is not null)
        {
            return CustomerCreateWriteResult.Error("invalidPayload", payloadError, retryable: false);
        }

        var eventId = Guid.NewGuid().ToString("D");
        CustomerCreateWriteResult? result = null;

        try
        {
            await _db!.RunTransactionAsync(async transaction =>
            {
                var receiptRef = _db.Collection(ReceiptsCollection).Document(operation.IdempotencyKey);
                var receiptSnap = await transaction.GetSnapshotAsync(receiptRef, cancellationToken)
                    .ConfigureAwait(false);
                if (receiptSnap.Exists)
                {
                    result = ReadDuplicateReceipt(receiptSnap);
                    return;
                }

                var customerRef = _db.Collection(CustomersCollection).Document(operation.EntityId);
                var customerSnap = await transaction.GetSnapshotAsync(customerRef, cancellationToken)
                    .ConfigureAwait(false);
                if (customerSnap.Exists)
                {
                    result = CustomerCreateWriteResult.Error(
                        "alreadyExists",
                        $"customers/{operation.EntityId} already exists",
                        retryable: false);
                    return;
                }

                transaction.Set(customerRef, payload!.ToFirestoreDocument(remoteVersion: 1));
                transaction.Set(receiptRef, new Dictionary<string, object?>
                {
                    ["idempotencyKey"] = operation.IdempotencyKey,
                    ["operationId"] = operation.OperationId,
                    ["eventId"] = eventId,
                    ["remoteVersion"] = 1,
                    ["status"] = AckStatuses.Accepted,
                    ["entityType"] = EntityTypes.Customer,
                    ["entityId"] = operation.EntityId,
                    ["createdAt"] = Timestamp.FromDateTime(now.UtcDateTime)
                });

                result = CustomerCreateWriteResult.Accepted(eventId, 1);
            }, cancellationToken: cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Firestore customer create failed for {EntityId}", operation.EntityId);
            return CustomerCreateWriteResult.Error(
                "firestoreWriteFailed",
                ex.Message,
                retryable: true);
        }

        return result ?? CustomerCreateWriteResult.Error(
            "firestoreWriteFailed",
            "Transaction completed without a result",
            retryable: true);
    }

    private static CustomerCreateWriteResult ReadDuplicateReceipt(DocumentSnapshot receiptSnap)
    {
        var data = receiptSnap.ToDictionary();
        var eventId = data.TryGetValue("eventId", out var eventObj) ? eventObj?.ToString() : null;
        var remoteVersion = data.TryGetValue("remoteVersion", out var versionObj) && versionObj is long lv
            ? (int)lv
            : 1;

        if (string.IsNullOrWhiteSpace(eventId))
        {
            eventId = Guid.NewGuid().ToString("D");
        }

        return CustomerCreateWriteResult.Duplicate(eventId, remoteVersion);
    }

    private bool TryEnsureFirestoreDb()
    {
        if (_db is not null && _initSucceeded)
        {
            return true;
        }

        lock (_initLock)
        {
            if (_db is not null && _initSucceeded)
            {
                return true;
            }

            if (_initAttempted && !_initSucceeded)
            {
                return false;
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

                var projectId = !string.IsNullOrWhiteSpace(_options.ProjectId)
                    ? _options.ProjectId.Trim()
                    : resolution.ProjectIdFromCredential;
                if (string.IsNullOrWhiteSpace(projectId))
                {
                    throw new InvalidOperationException(
                        "FirebaseAuth:ProjectId is required for Firestore writes when it cannot be inferred from the credential.");
                }

                var builder = new FirestoreDbBuilder
                {
                    ProjectId = projectId,
                    Credential = resolution.Credential
                };
                _db = builder.Build();
                _initSucceeded = true;
                _logger.LogInformation(
                    "FirestoreDb initialized for customer create writes (source={Source}, projectId={ProjectId})",
                    resolution.Source,
                    projectId);
                return true;
            }
            catch (Exception ex)
            {
                _initSucceeded = false;
                _logger.LogError(ex, "Failed to initialize FirestoreDb for customer create writes");
                return false;
            }
        }
    }

    private sealed class CustomerCreatePayload
    {
        public required string Id { get; init; }
        public required string Name { get; init; }
        public required string Address { get; init; }
        public required string CreatedByUserId { get; init; }
        public required DateTime CreatedAt { get; init; }
        public required DateTime UpdatedAt { get; init; }
        public string? ContactPersonName { get; init; }
        public string? PhoneNumber { get; init; }
        public string? Email { get; init; }
        public string? City { get; init; }
        public string? Notes { get; init; }

        public static string? TryParse(OperationSubmitPayload operation, out CustomerCreatePayload? payload)
        {
            payload = null;
            if (operation.Payload is null || operation.Payload.Value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
            {
                return "customer create payload is required";
            }

            var root = operation.Payload.Value;
            if (!TryGetRequiredString(root, "id", out var id))
                return "payload.id is required";
            if (!string.Equals(id, operation.EntityId, StringComparison.Ordinal))
                return "payload.id must match entityId";
            if (!TryGetRequiredString(root, "name", out var name))
                return "payload.name is required";
            if (!TryGetRequiredString(root, "address", out var address))
                return "payload.address is required";
            if (!TryGetRequiredString(root, "createdByUserId", out var createdByUserId))
                return "payload.createdByUserId is required";
            if (!TryGetRequiredTimestamp(root, "createdAt", out var createdAt))
                return "payload.createdAt is required";
            if (!TryGetRequiredTimestamp(root, "updatedAt", out var updatedAt))
                return "payload.updatedAt is required";

            payload = new CustomerCreatePayload
            {
                Id = id,
                Name = name,
                Address = address,
                CreatedByUserId = createdByUserId,
                CreatedAt = createdAt,
                UpdatedAt = updatedAt,
                ContactPersonName = TryGetOptionalString(root, "contactPersonName"),
                PhoneNumber = TryGetOptionalString(root, "phoneNumber"),
                Email = TryGetOptionalString(root, "email"),
                City = TryGetOptionalString(root, "city"),
                Notes = TryGetOptionalString(root, "notes")
            };
            return null;
        }

        public Dictionary<string, object?> ToFirestoreDocument(int remoteVersion)
        {
            var doc = new Dictionary<string, object?>
            {
                ["id"] = Id,
                ["name"] = Name,
                ["address"] = Address,
                ["createdByUserId"] = CreatedByUserId,
                ["createdAt"] = Timestamp.FromDateTime(DateTime.SpecifyKind(CreatedAt, DateTimeKind.Utc)),
                ["updatedAt"] = Timestamp.FromDateTime(DateTime.SpecifyKind(UpdatedAt, DateTimeKind.Utc)),
                ["remoteVersion"] = remoteVersion
            };

            SetOptional(doc, "contactPersonName", ContactPersonName);
            SetOptional(doc, "phoneNumber", PhoneNumber);
            SetOptional(doc, "email", Email);
            SetOptional(doc, "city", City);
            SetOptional(doc, "notes", Notes);
            return doc;
        }

        private static void SetOptional(Dictionary<string, object?> doc, string key, string? value)
        {
            if (!string.IsNullOrWhiteSpace(value))
            {
                doc[key] = value;
            }
        }

        private static bool TryGetRequiredString(JsonElement root, string name, out string value)
        {
            value = string.Empty;
            if (!root.TryGetProperty(name, out var element) || element.ValueKind != JsonValueKind.String)
            {
                return false;
            }

            value = element.GetString() ?? string.Empty;
            return !string.IsNullOrWhiteSpace(value);
        }

        private static string? TryGetOptionalString(JsonElement root, string name)
        {
            if (!root.TryGetProperty(name, out var element) || element.ValueKind != JsonValueKind.String)
            {
                return null;
            }

            var value = element.GetString();
            return string.IsNullOrWhiteSpace(value) ? null : value;
        }

        private static bool TryGetRequiredTimestamp(JsonElement root, string name, out DateTime value)
        {
            value = default;
            if (!root.TryGetProperty(name, out var element) || element.ValueKind != JsonValueKind.String)
            {
                return false;
            }

            var raw = element.GetString();
            if (string.IsNullOrWhiteSpace(raw))
            {
                return false;
            }

            if (!DateTimeOffset.TryParse(raw, out var parsed))
            {
                return false;
            }

            value = parsed.UtcDateTime;
            return true;
        }
    }
}
