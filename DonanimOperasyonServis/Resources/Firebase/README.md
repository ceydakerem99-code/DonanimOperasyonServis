# Firebase Konfigürasyonu

Bu klasör Firebase Console'dan indirilen `GoogleService-Info.plist`
dosyalarını barındırır. Gerçek credential dosyaları **asla commit
edilmez** (`.gitignore`). `DIContainer.live()` Firebase config yoksa
veya geçersizse **fail-fast** (`FirebaseError.notConfigured`) — Fake
Firestore/Storage production/live path'te kullanılmaz. Preview ve
unit testler `DIContainer.mock()` / `Fake*DataSource` kullanır.

## Dosyalar

| Dosya | Ortam | Bundle ID | Commit |
| --- | --- | --- | --- |
| `GoogleService-Info.plist` | Aktif (bundle) | `com.donanimoperasyonservis.app` | Hayır |
| `GoogleService-Info-Dev.plist` | Development | `com.donanimoperasyonservis.app.dev` | Hayır |
| `GoogleService-Info-Prod.plist` | Production | `com.donanimoperasyonservis.app` | Hayır |
| `GoogleService-Info-Dev.plist.example` | Şablon | — | Evet |
| `GoogleService-Info-Prod.plist.example` | Şablon | — | Evet |

## Faz 4 davranışı

`FirebaseAppBootstrapper.configure()` bundle'da
`GoogleService-Info.plist` arar:

- **Bulunursa** `FirebaseApp.configure(options:)` çağrılır ve
  `DIContainer.live()` gerçek `LiveFirestoreDataSource` /
  `LiveFirebaseStorageDataSource` bağlar.
- **Bulunmazsa veya parse edilemezse** `DIContainer.live()` throw
  eder (`FirebaseError.notConfigured`). Fake data source **yalnızca**
  `DIContainer.mock()` ve unit-test harness'te kullanılır.

Gerçek Auth, session ve role fetch **Faz 6**'dadır. Bu fazda
Firebase Authentication, FCM veya Offline Sync yoktur.

## Security Rules

Kurallar `FirebaseRules/` altındadır (`firestore.rules`,
`storage.rules`). v1 iskeleti **deny-all** + Faz 6 için TODO'lardır.
Collection adları `FirestoreCollection` enum'u ile, Storage path'leri
`FirebaseStoragePath` ile birebir örtüşür.

## Kurulum (Faz 6'da)

1. Firebase Console'da Dev / Prod projeleri oluştur.
2. Her proje için iOS uygulaması ekle ve doğru bundle ID'yi kullan.
3. İndirilen `GoogleService-Info.plist`'i bu klasöre uygun adla kopyala.
4. Aktif şema için dosyayı `GoogleService-Info.plist` olarak bundle'a
   dahil et.
5. `FirebaseRules/` içeriğini Firebase Console'a (veya `firebase deploy
   --only firestore:rules,storage`) deploy et — Auth açıldıktan sonra
   TODO'ları gerçek `request.auth` kontrollerine çevir.
