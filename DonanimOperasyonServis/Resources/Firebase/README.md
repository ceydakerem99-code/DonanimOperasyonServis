# Firebase Konfigürasyonu

Bu klasör Firebase Console'dan indirilen `GoogleService-Info.plist`
dosyalarını barındırır. Faz 0'da yalnız `*.plist.example` şablonları
mevcuttur; gerçek dosyalar Faz 4'te eklenecek ve **asla commit edilmeyecek**.

## Dosyalar

| Dosya | Ortam | Bundle ID | Commit |
| --- | --- | --- | --- |
| `GoogleService-Info-Dev.plist` | Development | `com.donanimoperasyonservis.app.dev` | Hayır (.gitignore) |
| `GoogleService-Info-Prod.plist` | Production | `com.donanimoperasyonservis.app` | Hayır (.gitignore) |
| `GoogleService-Info-Dev.plist.example` | Şablon | — | Evet |
| `GoogleService-Info-Prod.plist.example` | Şablon | — | Evet |

## Faz 4 Kurulumu

1. Firebase Console'da iki proje oluştur:
   - `DonanimOperasyonServis-Dev`
   - `DonanimOperasyonServis-Prod`
2. Her proje için iOS uygulaması ekle ve doğru bundle ID'yi kullan.
3. İndirilen `GoogleService-Info.plist`'i bu klasöre uygun adla kopyala.
4. Xcode target build ayarında doğru şeması için doğru dosyayı bundle'a
   dahil et (build phase "Copy Bundle Resources" veya schema-specific
   `INFOPLIST_FILE` benzeri bir strateji).

Şu anda (Faz 0) hiçbir dosya bundle'a dahil edilmez; `FirebaseApp.configure()`
henüz çağrılmaz. Firebase SPM paketleri yalnız derleme bağımlılığı olarak
eklenmiştir.
