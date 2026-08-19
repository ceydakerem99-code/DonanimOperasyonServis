# Firebase Rules (Phase 4)

This folder holds the **v1 skeleton** of Firestore and Storage
security rules. They are **not** deployed automatically and they
are **not** production-ready.

| File | Service | Default |
| --- | --- | --- |
| `firestore.rules` | Cloud Firestore | deny all |
| `storage.rules`   | Firebase Storage | deny all |

Authentication (Firebase Auth, session, role lookup) lands in
**Phase 6**. Until then:

- rules default-deny every client read/write;
- TODOs in each `match` block describe the intended role matrix
  (`admin` / `operator` / `technician`), which mirrors
  `RoleAccessPolicy` in the Domain layer;
- collection names match `FirestoreCollection`;
- storage paths match `FirebaseStoragePath`.

Do **not** loosen these rules to `allow read, write: if true` for
convenience. Tests never talk to a real Firebase project; they use
`FakeFirestoreDataSource` / `FakeFirebaseStorageDataSource`.
