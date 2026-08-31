# Operation/Event Gateway — Message Examples (FAZ 0)

Companion to [OperationEventGateway-Faz0.md](./OperationEventGateway-Faz0.md).  
Illustrative JSON only — not production payloads.

---

## 1. Session hello

### Client → server (`hello`)

```json
{
  "v": 1,
  "type": "hello",
  "requestId": "req-hello-001",
  "payload": {
    "idToken": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
    "deviceId": "device-ios-7f3a9c2e",
    "protocolVersion": 1,
    "entitySubscriptions": ["customer", "workOrder"]
  }
}
```

### Server → client (`hello.ok`)

```json
{
  "v": 1,
  "type": "hello.ok",
  "requestId": "req-hello-001",
  "payload": {
    "userId": "firebaseUidOperator1",
    "role": "operator",
    "serverTime": "2026-08-24T10:15:00.000Z",
    "resumeToken": null
  }
}
```

---

## 2. Customer create — submit, ack accepted, event.apply

### `op.submit`

```json
{
  "v": 1,
  "type": "op.submit",
  "requestId": "req-op-cust-1",
  "payload": {
    "operationId": "11111111-1111-1111-1111-111111111111",
    "idempotencyKey": "firebaseUidOperator1:customer:cust-abc:create:1",
    "entityType": "customer",
    "entityId": "cust-abc",
    "operationType": "create",
    "localVersion": 1,
    "baseRemoteVersion": null,
    "actorUserId": "firebaseUidOperator1",
    "deviceId": "device-ios-7f3a9c2e",
    "clientTimestamp": "2026-08-24T10:16:00.000Z",
    "payload": {
      "id": "cust-abc",
      "name": "ABC Market",
      "createdByUserId": "firebaseUidOperator1",
      "isActive": true
    },
    "dependsOnOperationId": null
  }
}
```

### `op.ack` (accepted)

```json
{
  "v": 1,
  "type": "op.ack",
  "requestId": "req-op-cust-1",
  "payload": {
    "operationId": "11111111-1111-1111-1111-111111111111",
    "idempotencyKey": "firebaseUidOperator1:customer:cust-abc:create:1",
    "status": "accepted",
    "eventId": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    "remoteVersion": 1,
    "error": null,
    "serverTimestamp": "2026-08-24T10:16:00.120Z"
  }
}
```

### `event.apply`

```json
{
  "v": 1,
  "type": "event.apply",
  "requestId": null,
  "payload": {
    "eventId": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    "operationId": "11111111-1111-1111-1111-111111111111",
    "idempotencyKey": "firebaseUidOperator1:customer:cust-abc:create:1",
    "entityType": "customer",
    "entityId": "cust-abc",
    "operationType": "create",
    "remoteVersion": 1,
    "actorUserId": "firebaseUidOperator1",
    "serverTimestamp": "2026-08-24T10:16:00.120Z",
    "payload": {
      "id": "cust-abc",
      "name": "ABC Market",
      "createdByUserId": "firebaseUidOperator1",
      "isActive": true,
      "remoteVersion": 1
    },
    "causation": "accepted"
  }
}
```

---

## 3. WorkOrder create — submit and ack

### `op.submit`

```json
{
  "v": 1,
  "type": "op.submit",
  "requestId": "req-op-wo-1",
  "payload": {
    "operationId": "22222222-2222-2222-2222-222222222222",
    "idempotencyKey": "firebaseUidOperator1:workOrder:wo-100:create:1",
    "entityType": "workOrder",
    "entityId": "wo-100",
    "operationType": "create",
    "localVersion": 1,
    "baseRemoteVersion": null,
    "actorUserId": "firebaseUidOperator1",
    "deviceId": "device-ios-7f3a9c2e",
    "clientTimestamp": "2026-08-24T10:17:00.000Z",
    "payload": {
      "id": "wo-100",
      "customerId": "cust-abc",
      "createdByUserId": "firebaseUidOperator1",
      "assignedTechnicianId": "firebaseUidTech1",
      "status": "assigned",
      "workType": "maintenance"
    },
    "dependsOnOperationId": null
  }
}
```

### `op.ack` (accepted)

```json
{
  "v": 1,
  "type": "op.ack",
  "requestId": "req-op-wo-1",
  "payload": {
    "operationId": "22222222-2222-2222-2222-222222222222",
    "idempotencyKey": "firebaseUidOperator1:workOrder:wo-100:create:1",
    "status": "accepted",
    "eventId": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
    "remoteVersion": 1,
    "error": null,
    "serverTimestamp": "2026-08-24T10:17:00.200Z"
  }
}
```

---

## 4. Idempotent retry — `op.ack` duplicate

Same `idempotencyKey` resubmitted after ACK timeout / reconnect (new `operationId` allowed; key wins).

### `op.submit` (retry)

```json
{
  "v": 1,
  "type": "op.submit",
  "requestId": "req-op-cust-1-retry",
  "payload": {
    "operationId": "33333333-3333-3333-3333-333333333333",
    "idempotencyKey": "firebaseUidOperator1:customer:cust-abc:create:1",
    "entityType": "customer",
    "entityId": "cust-abc",
    "operationType": "create",
    "localVersion": 1,
    "baseRemoteVersion": null,
    "actorUserId": "firebaseUidOperator1",
    "deviceId": "device-ios-7f3a9c2e",
    "clientTimestamp": "2026-08-24T10:18:00.000Z",
    "payload": {
      "id": "cust-abc",
      "name": "ABC Market",
      "createdByUserId": "firebaseUidOperator1",
      "isActive": true
    },
    "dependsOnOperationId": null
  }
}
```

### `op.ack` (duplicate)

```json
{
  "v": 1,
  "type": "op.ack",
  "requestId": "req-op-cust-1-retry",
  "payload": {
    "operationId": "33333333-3333-3333-3333-333333333333",
    "idempotencyKey": "firebaseUidOperator1:customer:cust-abc:create:1",
    "status": "duplicate",
    "eventId": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    "remoteVersion": 1,
    "error": null,
    "serverTimestamp": "2026-08-24T10:18:00.050Z"
  }
}
```

No second Firestore entity write. Client treats this as success for the outbox row.

---

## 5. Conflict — stale `baseRemoteVersion`

### `op.submit` (update)

```json
{
  "v": 1,
  "type": "op.submit",
  "requestId": "req-op-wo-conflict",
  "payload": {
    "operationId": "44444444-4444-4444-4444-444444444444",
    "idempotencyKey": "firebaseUidOperator1:workOrder:wo-100:update:2",
    "entityType": "workOrder",
    "entityId": "wo-100",
    "operationType": "update",
    "localVersion": 2,
    "baseRemoteVersion": 1,
    "actorUserId": "firebaseUidOperator1",
    "deviceId": "device-ios-7f3a9c2e",
    "clientTimestamp": "2026-08-24T10:20:00.000Z",
    "payload": {
      "id": "wo-100",
      "assignedTechnicianId": "firebaseUidTech2",
      "status": "assigned",
      "remoteVersion": 1
    },
    "dependsOnOperationId": null
  }
}
```

### `op.ack` (rejected — conflict)

Server current `remoteVersion` is `3`.

```json
{
  "v": 1,
  "type": "op.ack",
  "requestId": "req-op-wo-conflict",
  "payload": {
    "operationId": "44444444-4444-4444-4444-444444444444",
    "idempotencyKey": "firebaseUidOperator1:workOrder:wo-100:update:2",
    "status": "rejected",
    "eventId": null,
    "remoteVersion": null,
    "error": {
      "code": "conflict",
      "message": "baseRemoteVersion 1 != current 3",
      "retryable": false,
      "details": {
        "entityType": "workOrder",
        "entityId": "wo-100",
        "currentRemoteVersion": 3
      }
    },
    "serverTimestamp": "2026-08-24T10:20:00.080Z"
  }
}
```

No Firestore write for this Operation. Client keeps a failed outbox row (not silent delete).

---

## 6. Forbidden — wrong role

Technician attempts `customer` create:

```json
{
  "v": 1,
  "type": "op.ack",
  "requestId": "req-op-cust-forbidden",
  "payload": {
    "operationId": "55555555-5555-5555-5555-555555555555",
    "idempotencyKey": "firebaseUidTech1:customer:cust-xyz:create:1",
    "status": "rejected",
    "eventId": null,
    "remoteVersion": null,
    "error": {
      "code": "forbidden",
      "message": "role technician cannot create customer",
      "retryable": false,
      "details": {
        "role": "technician",
        "entityType": "customer",
        "operationType": "create"
      }
    },
    "serverTimestamp": "2026-08-24T10:21:00.000Z"
  }
}
```

---

## 7. Keepalive

### `ping`

```json
{
  "v": 1,
  "type": "ping",
  "requestId": null,
  "payload": { "t": 1724494560000 }
}
```

### `pong`

```json
{
  "v": 1,
  "type": "pong",
  "requestId": null,
  "payload": { "t": 1724494560000 }
}
```

---

## 8. Protocol error (session)

```json
{
  "v": 1,
  "type": "error",
  "requestId": null,
  "payload": {
    "code": "unauthorized",
    "message": "idToken expired",
    "retryable": false,
    "details": {}
  }
}
```

Server then closes the WebSocket. Client refreshes Firebase ID token and reconnects with a new `hello`.
