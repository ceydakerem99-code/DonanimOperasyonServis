import { createFirestoreStore } from "./firestore-rest";
import { getSurveyContext, submitSurvey } from "./survey-handlers";

export interface Env {
  FIREBASE_PROJECT_ID: string;
  FIREBASE_CLIENT_EMAIL: string;
  FIREBASE_PRIVATE_KEY: string;
  SURVEY_TOKEN_SECRET: string;
}

const ALLOWED_ORIGINS = new Set([
  "https://donanimoperasyonservis.web.app",
  "https://donanimoperasyonservis.firebaseapp.com",
  "https://dopsanketsistemi.netlify.app",
]);

export function extractTokenFromPath(pathname: string): string | null {
  const match = pathname.match(/\/api\/survey\/([^/]+)(?:\/submit)?$/);
  return match?.[1] ? decodeURIComponent(match[1]) : null;
}

function corsHeaders(origin: string | null): HeadersInit {
  const allowedOrigin = origin && ALLOWED_ORIGINS.has(origin) ? origin : ALLOWED_ORIGINS.values().next().value;
  return {
    "Access-Control-Allow-Origin": allowedOrigin ?? "https://donanimoperasyonservis.web.app",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  };
}

function jsonResponse(
  status: number,
  body: unknown,
  origin: string | null,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...corsHeaders(origin),
    },
  });
}

export function mapSurveyError(error: unknown): { status: number; body: Record<string, string> } {
  const message = error instanceof Error ? error.message : "unknown_error";
  switch (message) {
  case "invalid_token":
    return { status: 403, body: { error: "invalid_token", message: "Geçersiz anket bağlantısı." } };
  case "not_found":
    return { status: 404, body: { error: "not_found", message: "Değerlendirme kaydı bulunamadı." } };
  case "not_pending":
    return {
      status: 409,
      body: {
        error: "not_pending",
        message: "Bu değerlendirme zaten yanıtlanmış veya artık geçerli değil.",
      },
    };
  default:
    if (message.startsWith("Tüm puanlar") || message === "Geçersiz istek gövdesi.") {
      return { status: 400, body: { error: "invalid_payload", message } };
    }
    return { status: 500, body: { error: "internal_error", message: "Değerlendirme gönderilemedi." } };
  }
}

function requireEnv(env: Env): string {
  const secret = env.SURVEY_TOKEN_SECRET?.trim();
  if (!secret) {
    throw new Error("missing_survey_token_secret");
  }
  if (!env.FIREBASE_CLIENT_EMAIL?.trim() || !env.FIREBASE_PRIVATE_KEY?.trim()) {
    throw new Error("missing_firestore_credentials");
  }
  return secret;
}

export async function handleSurveyRequest(
  request: Request,
  env: Env,
): Promise<Response> {
  const origin = request.headers.get("Origin");

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }

  const url = new URL(request.url);
  const token = extractTokenFromPath(url.pathname);
  if (!token) {
    return jsonResponse(404, { error: "not_found" }, origin);
  }

  try {
    const tokenSecret = requireEnv(env);
    const store = createFirestoreStore(env);

    if (request.method === "GET") {
      const context = await getSurveyContext(
        token,
        tokenSecret,
        store,
        env.FIREBASE_PROJECT_ID,
      );
      return jsonResponse(200, context, origin);
    }

    if (request.method === "POST" && url.pathname.endsWith("/submit")) {
      const body = await request.json().catch(() => null);
      await submitSurvey(token, body, tokenSecret, store);
      return jsonResponse(200, { ok: true }, origin);
    }

    return jsonResponse(405, { error: "method_not_allowed" }, origin);
  } catch (error) {
    if (error instanceof Error && error.message === "missing_survey_token_secret") {
      return jsonResponse(500, { error: "internal_error", message: "Değerlendirme gönderilemedi." }, origin);
    }
    if (error instanceof Error && error.message === "missing_firestore_credentials") {
      return jsonResponse(500, { error: "internal_error", message: "Değerlendirme gönderilemedi." }, origin);
    }
    const mapped = mapSurveyError(error);
    return jsonResponse(mapped.status, mapped.body, origin);
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return handleSurveyRequest(request, env);
  },
};
