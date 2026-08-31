# FAZ 1 — iOS client notes (not wired)

**Status:** documentation only. Do **not** connect production UI / SyncQueue / `LocalToRemoteSyncManager` to this gateway yet.

## Why this exists

FAZ 1 delivers an isolated C# WebSocket gateway (`RealtimeGateway/`) that:

- accepts `hello` + Firebase ID token
- accepts `op.submit` for `customer` / `workOrder`
- returns `op.ack` (+ `event.apply` on accept)
- **does not** mutate Firestore
- **does not** replace SyncQueue

## Future client surface (FAZ 2+)

| Piece | Intent |
|-------|--------|
| `WebSocketGatewayClient` | Connect to `ws://…/ws`, hello, ping, submit |
| `OperationOutbox` | SwiftData outbox **separate** from `SyncOperation` |
| Feature flag `useOperationGateway` | Default **off**; SyncQueue remains primary |

### Hello (from iOS later)

1. `Auth.auth().currentUser.getIDToken()`
2. Send FAZ 0 `hello` envelope with `idToken`, `deviceId`, `entitySubscriptions: ["customer","workOrder"]`
3. Expect `hello.ok` with `userId` / `role`

### Submit

Use FAZ 0 Operation fields. `actorUserId` **must** equal the authenticated Firebase UID (gateway rejects spoofing).

### ACK handling

| status | Client action (future) |
|--------|------------------------|
| `accepted` / `duplicate` | Mark outbox success (idempotent) |
| `forbidden` / `invalid` / `conflict` | Permanent fail (no silent delete) |
| `error` with `retryable: true` | Backoff + resubmit same `idempotencyKey` |

## Explicit non-goals for FAZ 1

- No changes under `DonanimOperasyonServis/` app sync code
- No enqueue path changes in Operator/Technician services
- No badge / SyncProgressStore coupling to gateway
