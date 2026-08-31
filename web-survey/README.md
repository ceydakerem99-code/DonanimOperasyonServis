# Customer Satisfaction Web Survey

Mobil web değerlendirme formu ve local demo sunucusu.

## Yerel URL yapısı

```
http://127.0.0.1:5199/survey/{token}
```

`token` = HMAC imzalı, `satisfactionId` içeren güvenli bağlantı parçasıdır.

## Local demo

1. **JDK 21+** (Firestore emulator için zorunlu — firebase-tools 15.x):

```bash
brew install --cask temurin@21
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
```

2. Firestore emulator:

```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
firebase emulators:start --only firestore --project donanimoperasyonservis
```

3. Seed (emulator çalışırken, ayrı terminal):

```bash
cd functions && npm run seed:survey
```

4. Survey dev server:

```bash
cd functions && npm run serve:survey
```

5. iOS Debug → SMS Simülasyonu → **Değerlendirmeye Git** (Safari).

Seed fixture: `cs-e2e-local` / `WO-E2E-001` / `E2E Müşteri`

## Spark plan notu

- Hosting (statik web): Spark'ta deploy edilebilir.
- Cloud Functions (`surveyApi`): Production deploy için Blaze gerekir.
- Local demo: `web-survey/dev-server.mjs` + Firestore emulator.
