# FAZ 2 — Real gateway + iOS DEBUG smoke

**Not FAZ 3.** Shadow only: connect → hello (Firebase ID token) → customer/workOrder `op.submit` → `accepted` / `duplicate` ACK. No Firestore / SyncQueue mutation.

## Prerequisites

1. **Service account** for the same Firebase project as the iOS app (`donanimoperasyonservis`):

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/serviceAccount.json
```

2. **iOS Simulator** (localhost). Physical device needs Mac LAN IP override — not covered here.
3. **Live Firebase Auth** in the app (real login). Fake Auth / `DIContainer.mock()` cannot satisfy the gateway verifier.
4. Prefer **operator** or **admin** user. If the ID token has no `role` claim, Development host uses `FirebaseAuth:DevelopmentRoleFallback=operator` (smoke only; no Firestore write).

## Steps

### 1. Start gateway

```bash
cd RealtimeGateway
dotnet run --project RealtimeGateway.Host --environment Development
```

### 2. Health check

```bash
curl -s http://127.0.0.1:5088/health
```

Expect: `"firestoreMutations":false`, `"mode":"shadow-faz1"`.

### 3. Run iOS DEBUG

- Scheme: Debug, Simulator on the same Mac.
- Sign in with a real Firebase user.
- Developer Tools → **Realtime Gateway (Shadow)** → wait for 🟢 Connected.
- Tap **Smoke Sequence (customer + WO + duplicate)**.

### 4. Pass criteria

| Check | Expect |
|-------|--------|
| Console / UI | `REALTIME AUTHENTICATED` / `REALTIME CONNECTED` |
| Smoke summary | `OK customer=accepted workOrder=accepted duplicate=duplicate` |
| Gateway logs | hello auth + op processing; **no** Firestore client calls |
| Firebase Console | no new `customers` / `workOrders` with `shadow-smoke-*` ids |
| SyncQueue | still works independently (manual sync still available) |

### 5. Failures

| Symptom | Likely cause |
|---------|----------------|
| Connecting forever / failed | Gateway not on `5088`, or ATS (needs `NSAllowsLocalNetworking`) |
| `unauthorized` | Missing/invalid `GOOGLE_APPLICATION_CREDENTIALS`, or Fake Auth token |
| `forbidden` | Role neither operator/admin nor Development fallback |
| ACK timeout | Connected to wrong host / receive loop stopped |

## Explicit non-goals

- No SyncOperation / LocalToRemoteSyncManager changes
- No Firebase customer/workOrder delete or migration
- No Firestore rules changes
- No FAZ 3 cutover
