# DonanimOperasyonServis

Kurumsal iOS uygulaması: POS, tablet, yazıcı ve diğer donanımların kurulum, bakım, arıza ve teslim süreçlerini iş emri üzerinden yöneten saha operasyon çözümü.

## Teknoloji

- Swift 6 (strict concurrency)
- SwiftUI + Observation
- SwiftData (offline)
- Firebase (Auth, Firestore, Storage) — remote
- Clean Architecture (Presentation / Domain / Data / Infrastructure)
- MVVM + Repository + UseCase + Constructor DI
- iOS 18.0+, iPhone-only

## Roller

- Admin — sistem yönetimi
- Operasyon Yetkilisi (`operator`) — iş emri veren, atayan, düzenleme taleplerini onaylayan
- Teknisyen (`technician`) — sahada işi yürüten

## Proje Yapısı

Xcode projesi (`DonanimOperasyonServis.xcodeproj`) [XcodeGen](https://github.com/yonaskolb/XcodeGen) ile `project.yml`'den üretilir. Kaynak dosyalar `DonanimOperasyonServis/` altında, testler `DonanimOperasyonServisTests/` altındadır.

```
DonanimOperasyonServis/
├── App/                    @main + AppDelegate + AppCoordinator
├── Presentation/           DesignSystem + Auth/Admin/Operator/Technician modülleri
├── Domain/                 Entity, Enum, ValueObject, Repository (protokol), UseCase, Policy
├── Data/                   Local (SwiftData) + Remote (Firebase) + Repositories + Sync
├── Infrastructure/         DI, Location, Camera, Notifications, Logging
└── Resources/              Info.plist, tr.lproj (Localizable.strings), Assets, Firebase config
```

## Geliştirme

### Gereksinimler

- macOS + Xcode 16+ (Xcode 26 ile test edildi)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Kurulum

```bash
# Xcode projesini üret
xcodegen generate

# Xcode'da aç
open DonanimOperasyonServis.xcodeproj
```

### Firebase Konfigürasyonu (Faz 4'te aktifleşecek)

Firebase paketleri SPM ile eklidir, ancak `FirebaseApp.configure()` henüz çağrılmaz. Faz 4'te:

1. Firebase Console'da iki proje oluştur: `DonanimOperasyonServis-Dev`, `DonanimOperasyonServis-Prod`.
2. Her biri için `GoogleService-Info.plist` indir.
3. `DonanimOperasyonServis/Resources/Firebase/` altına koy:
   - `GoogleService-Info-Dev.plist`
   - `GoogleService-Info-Prod.plist`
4. Bu dosyalar `.gitignore` altındadır ve **asla commit edilmez**.

Örnek şablonlar `*.plist.example` uzantısıyla mevcuttur.

## Geliştirme Fazları

- [x] **Faz 0** — Scaffold: proje, SPM, klasör yapısı, DI + Logger iskeleti, build doğrulaması.
- [ ] **Faz 1** — Design System.
- [ ] **Faz 2** — Domain katmanı.
- [ ] **Faz 3** — SwiftData Local.
- [ ] **Faz 4** — Firebase Remote.
- [ ] **Faz 5** — Offline/Sync.
- [ ] **Faz 6** — Auth + role-based routing.
- [ ] **Faz 7** — Teknisyen ana akış.
- [ ] **Faz 8** — Teknisyen derin akışlar.
- [ ] **Faz 9** — Operasyon Yetkilisi.
- [ ] **Faz 10** — Bildirimler.
- [ ] **Faz 11** — Admin panel.
- [ ] **Faz 12** — Cila.

## Lisans

Proprietary — tüm hakları saklıdır.
