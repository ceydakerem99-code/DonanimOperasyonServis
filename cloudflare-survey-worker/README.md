# Cloudflare Survey Worker

Production survey API for Customer Satisfaction web survey.
Replaces Firebase Cloud Functions `surveyApi` on Spark (no billing required).

## Architecture

```
Firebase Hosting (SPA)  →  https://donanimoperasyonservis.web.app/survey/{token}
        ↓ config.js SURVEY_API_BASE
Cloudflare Worker       →  https://donanimoperasyonservis-survey.workers.dev/api/survey/*
        ↓ Firestore REST + service account JWT
Firebase Firestore
```

## Required Cloudflare secrets

```bash
cd cloudflare-survey-worker
npm install
npx wrangler secret put SURVEY_TOKEN_SECRET
npx wrangler secret put FIREBASE_CLIENT_EMAIL
npx wrangler secret put FIREBASE_PRIVATE_KEY
```

`SURVEY_TOKEN_SECRET` must match iOS `Config/SurveyProductionSecrets.xcconfig` (Release).

## Firebase service account (manual)

1. Google Cloud Console → IAM → Service Accounts → Create
2. Name: `dops-survey-worker`
3. Role: **Cloud Datastore User** (or Firebase Admin SDK Administrator Service Agent)
4. Create JSON key — **do not commit**
5. Use `client_email` and `private_key` as Worker secrets

## Deploy

```bash
cd cloudflare-survey-worker
npm run build
npm test
npx wrangler deploy
```

Then redeploy Firebase Hosting (updates `config.js` if changed):

```bash
firebase deploy --only hosting --project donanimoperasyonservis
```

## Local dev

Copy `.dev.vars.example` → `.dev.vars` and run:

```bash
npx wrangler dev
```

For full local stack, continue using `cd functions && npm run serve:survey` with Firestore emulator.
