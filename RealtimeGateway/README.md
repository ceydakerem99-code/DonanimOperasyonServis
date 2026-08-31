# RealtimeGateway (FAZ 1 — shadow / isolated)

Isolated C# WebSocket gateway implementing the FAZ 0 Operation/Event contract.

**This does not replace the iOS SyncQueue / `LocalToRemoteSyncManager` path.**
**FAZ 1 performs no Firestore mutations and does not touch Firebase customer/workOrder data.**

## Spec sources

- [`Docs/Architecture/OperationEventGateway-Faz0.md`](../Docs/Architecture/OperationEventGateway-Faz0.md)
- [`Docs/Architecture/OperationEventGateway-MessageExamples.md`](../Docs/Architecture/OperationEventGateway-MessageExamples.md)

## Solution layout

| Project | Role |
|---------|------|
| `RealtimeGateway.Contracts` | Envelope, Operation, ACK, Event models |
| `RealtimeGateway.Core` | Auth, ConnectionManager, idempotency (in-memory), OperationProcessor |
| `RealtimeGateway.Host` | ASP.NET Core host + `/ws` WebSocket endpoint |
| `RealtimeGateway.Tests` | Protocol + unit tests |

## Run

```bash
cd RealtimeGateway
dotnet restore
dotnet build
dotnet run --project RealtimeGateway.Host
```

Default URL: `http://127.0.0.1:5088`

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Liveness (`firestoreMutations: false`) |
| `WS /ws` | Gateway protocol (hello → op.submit → op.ack) |

### Firebase Auth (production host)

Set a service-account credential so Firebase Admin can verify **real** ID tokens:

```bash
# Option A — local Development file (gitignored):
cp /path/to/serviceAccount.json RealtimeGateway.Host/secrets/firebase-service-account.json

# Option B — environment variable:
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
```

Resolution order: `FirebaseAuth:CredentialPath` → `GOOGLE_APPLICATION_CREDENTIALS` → Application Default Credentials.

Development defaults (`appsettings.Development.json`):

- `ProjectId`: `donanimoperasyonservis`
- `CredentialPath`: `secrets/firebase-service-account.json` (relative to host content root)
- `DevelopmentRoleFallback`: `operator` (smoke only; empty in production)

Check configuration without exposing secrets:

```bash
curl -s http://127.0.0.1:5088/health
```

Expect `firebase.configured: true` and `firebase.projectId: donanimoperasyonservis` before iOS smoke.

### Tests

```bash
dotnet test
```

Tests inject a RSA-signed JWT verifier (test project only). Production DI always registers `FirebaseIdTokenVerifier`.

## ACK statuses (FAZ 1)

`accepted` | `duplicate` | `forbidden` | `conflict` | `invalid` | `error`

Shadow accepts write into **in-memory** idempotency + version stores only.

## iOS DEBUG smoke (FAZ 2)

See [`Docs/Architecture/OperationEventGateway-Faz2-Smoke.md`](../Docs/Architecture/OperationEventGateway-Faz2-Smoke.md).

Development host may apply `FirebaseAuth:DevelopmentRoleFallback` when the ID token has no `role` claim. Production `appsettings.json` leaves this empty.

## iOS

No production SyncQueue cutover. Shadow client: FAZ 2.
