/**
 * DOPS Cloud Functions
 *
 * - Static survey hosting: Firebase Hosting (Spark-compatible).
 * - surveyApi HTTP function: requires Blaze + SURVEY_TOKEN_SECRET secret.
 * - Local demo: `npm run serve:survey` in functions/ or Firebase emulators.
 */

import * as admin from "firebase-admin";
import {defineSecret} from "firebase-functions/params";
import {onRequest} from "firebase-functions/v2/https";
import {getSurveyContext, submitSurvey} from "./survey/handlers";

const surveyTokenSecret = defineSecret("SURVEY_TOKEN_SECRET");

if (!admin.apps.length) {
  admin.initializeApp();
}

function sendJson(res: { status: (code: number) => { json: (body: unknown) => void } }, status: number, body: unknown) {
  res.status(status).json(body);
}

function extractTokenFromPath(path: string): string | null {
  const match = path.match(/\/api\/survey\/([^/]+)(?:\/submit)?$/);
  return match?.[1] ?? null;
}

export const surveyApi = onRequest({
  cors: true,
  region: "europe-west1",
  secrets: [surveyTokenSecret],
}, async (req, res) => {
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  const token = extractTokenFromPath(req.path);
  if (!token) {
    sendJson(res, 404, {error: "not_found"});
    return;
  }

  try {
    if (req.method === "GET") {
      const context = await getSurveyContext(token);
      sendJson(res, 200, context);
      return;
    }

    if (req.method === "POST" && req.path.endsWith("/submit")) {
      await submitSurvey(token, req.body);
      sendJson(res, 200, {ok: true});
      return;
    }

    sendJson(res, 405, {error: "method_not_allowed"});
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown_error";
    switch (message) {
    case "invalid_token":
      sendJson(res, 403, {error: "invalid_token", message: "Geçersiz anket bağlantısı."});
      return;
    case "not_found":
      sendJson(res, 404, {error: "not_found", message: "Değerlendirme kaydı bulunamadı."});
      return;
    case "not_pending":
      sendJson(res, 409, {
        error: "not_pending",
        message: "Bu değerlendirme zaten yanıtlanmış veya artık geçerli değil.",
      });
      return;
    case "missing_survey_token_secret":
      sendJson(res, 500, {error: "internal_error", message: "Değerlendirme gönderilemedi."});
      return;
    default:
      if (message.startsWith("Tüm puanlar") || message === "Geçersiz istek gövdesi.") {
        sendJson(res, 400, {error: "invalid_payload", message});
        return;
      }
      sendJson(res, 500, {error: "internal_error", message: "Değerlendirme gönderilemedi."});
    }
  }
});
