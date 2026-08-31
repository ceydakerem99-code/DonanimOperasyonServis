# FAZ 2 — iOS Realtime Shadow Client

## Status

iOS connects to the FAZ 1 C# gateway in **shadow mode**:

- Firebase Auth ID token → `hello`
- Receive `hello.ok` / `op.ack` / `event.apply`
- Log + telemetry only

**Does not** mutate SwiftData, Firestore, or `SyncOperation`.
**Does not** replace SyncQueue / `LocalToRemoteSyncManager`.

## Key types

| Type | Path |
|------|------|
| `RealtimeCoordinator` | `Data/Realtime/RealtimeCoordinator.swift` |
| `RealtimeWebSocketClient` | `Data/Realtime/RealtimeWebSocketClient.swift` |
| `RealtimeGatewayConfiguration` | DEBUG → `ws://127.0.0.1:5088/ws`; Release disabled |
| Protocol codec | `Data/Realtime/RealtimeProtocolModels.swift` |

## Lifecycle

- Login / session restore → `handleAuthenticatedSession()`
- Logout → `handleSignedOut()`
- Foreground → reconnect if wanted
- Background → disconnect

## DEBUG UI

Developer Tools → **Realtime Gateway (Shadow)** status + **Smoke Sequence** / single probe.

Real gateway runbook: [OperationEventGateway-Faz2-Smoke.md](./OperationEventGateway-Faz2-Smoke.md).
