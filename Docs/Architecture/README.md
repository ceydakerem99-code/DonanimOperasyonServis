# Architecture docs

This folder holds design specs that are **not** yet (or not only) reflected in production code.

## Documents

| Document | Status | Description |
|----------|--------|-------------|
| [OperationEventGateway-Faz0.md](./OperationEventGateway-Faz0.md) | FAZ 0 complete | Offline-first Operation/Event contract + C# WebSocket Gateway architecture |
| [OperationEventGateway-MessageExamples.md](./OperationEventGateway-MessageExamples.md) | FAZ 0 complete | JSON envelope examples (hello, submit, ack, conflict, duplicate) |
| [OperationEventGateway-Faz1-ClientNotes.md](./OperationEventGateway-Faz1-ClientNotes.md) | FAZ 1 notes | Future iOS client surface |
| [OperationEventGateway-Faz2-Shadow.md](./OperationEventGateway-Faz2-Shadow.md) | FAZ 2 | iOS shadow WebSocket client (no domain mutation) |
| [OperationEventGateway-Faz2-Smoke.md](./OperationEventGateway-Faz2-Smoke.md) | FAZ 2 smoke | Real gateway + iOS DEBUG smoke steps |
| [../RealtimeGateway/README.md](../../RealtimeGateway/README.md) | FAZ 1 shadow host | Isolated C# gateway; no Firestore mutations |
| [../DonanimOperasyonServis-Mimari-Ozet.pdf](../DonanimOperasyonServis-Mimari-Ozet.pdf) | Current production overview | SwiftData + SyncQueue + Firebase (Auth / Firestore / Storage) |

## Production path today (do not confuse with FAZ 0)

**SyncQueue is still the production sync path.**

- Local writes go through domain use cases → SwiftData → `SyncOperation` enqueue.
- Drain: `LocalToRemoteSyncManager` → Firebase Firestore / Storage.
- FAZ 0 does **not** change SyncManager, SyncQueue, Firestore rules, or live Firebase data.

## Coexistence (planned)

Until a later phase deprecates SyncQueue:

1. Gateway work ships behind a feature flag (default off in FAZ 1).
2. Production must use **one writer per `entityType`** (SyncQueue **or** Gateway), never both for the same type.
3. Rollback = flag off; no Firestore reset; no local store wipe.

## Next phase (not started)

**FAZ 1:** C# gateway skeleton, Firebase ID token auth, `customer` / `workOrder` apply, iOS outbox + WebSocket client behind flag **OFF**.
