import http from "node:http";
import { createReadStream, existsSync } from "node:fs";
import { stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import admin from "../functions/node_modules/firebase-admin/lib/index.js";
import { getSurveyContext, submitSurvey } from "../functions/lib/survey/handlers.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const publicRoot = path.join(__dirname, "public");
const port = Number(process.env.SURVEY_DEV_PORT || 5199);
const projectId =
  process.env.GCLOUD_PROJECT ||
  process.env.FIREBASE_PROJECT_ID ||
  "donanimoperasyonservis";

const SURVEY_STATIC_FILES = new Set([
  "/survey/index.html",
  "/survey/styles.css",
  "/survey/app.js",
]);

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
}

if (!admin.apps.length) {
  admin.initializeApp({ projectId });
}

function sendJson(res, status, body) {
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
  });
  res.end(JSON.stringify(body));
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }
  if (chunks.length === 0) {
    return {};
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    return null;
  }
}

function contentType(filePath) {
  switch (path.extname(filePath)) {
  case ".html": return "text/html; charset=utf-8";
  case ".css": return "text/css; charset=utf-8";
  case ".js": return "application/javascript; charset=utf-8";
  default: return "application/octet-stream";
  }
}

function resolveSurveyStaticPath(pathname) {
  if (
    pathname === "/" ||
    pathname === "/survey" ||
    pathname === "/survey/"
  ) {
    return "/survey/index.html";
  }

  if (SURVEY_STATIC_FILES.has(pathname)) {
    return pathname;
  }

  if (pathname.startsWith("/survey/")) {
    return "/survey/index.html";
  }

  return pathname;
}

async function serveStatic(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const relativePath = resolveSurveyStaticPath(decodeURIComponent(url.pathname));
  const filePath = path.join(publicRoot, relativePath);

  if (!filePath.startsWith(publicRoot) || !existsSync(filePath)) {
    res.writeHead(404);
    res.end("Not found");
    return;
  }

  const fileStat = await stat(filePath);
  if (fileStat.isDirectory()) {
    res.writeHead(404);
    res.end("Not found");
    return;
  }

  res.writeHead(200, { "Content-Type": contentType(filePath) });
  createReadStream(filePath).pipe(res);
}

async function handleApi(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const match = url.pathname.match(/^\/api\/survey\/([^/]+)(?:\/submit)?$/);
  if (!match) {
    sendJson(res, 404, { error: "not_found" });
    return;
  }

  const token = decodeURIComponent(match[1]);
  try {
    if (req.method === "GET") {
      const context = await getSurveyContext(token);
      sendJson(res, 200, context);
      return;
    }

    if (req.method === "POST" && url.pathname.endsWith("/submit")) {
      const body = await readBody(req);
      if (body === null) {
        sendJson(res, 400, { error: "invalid_payload", message: "Geçersiz istek gövdesi." });
        return;
      }
      await submitSurvey(token, body);
      sendJson(res, 200, { ok: true });
      return;
    }

    sendJson(res, 405, { error: "method_not_allowed" });
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown_error";
    switch (message) {
    case "invalid_token":
      sendJson(res, 403, { error: "invalid_token", message: "Geçersiz anket bağlantısı." });
      return;
    case "not_found":
      sendJson(res, 404, { error: "not_found", message: "Değerlendirme kaydı bulunamadı." });
      return;
    case "not_pending":
      sendJson(res, 409, {
        error: "not_pending",
        message: "Bu değerlendirme zaten yanıtlanmış veya artık geçerli değil.",
      });
      return;
    default:
      if (message.startsWith("Tüm puanlar") || message === "Geçersiz istek gövdesi.") {
        sendJson(res, 400, { error: "invalid_payload", message });
        return;
      }
      sendJson(res, 500, { error: "internal_error", message: "Değerlendirme gönderilemedi." });
    }
  }
}

const server = http.createServer(async (req, res) => {
  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    });
    res.end();
    return;
  }

  if (req.url?.startsWith("/api/survey/")) {
    await handleApi(req, res);
    return;
  }

  await serveStatic(req, res);
});

server.listen(port, "0.0.0.0", () => {
  console.log(`Survey dev server listening on http://127.0.0.1:${port}`);
  console.log(`Firestore emulator: ${process.env.FIRESTORE_EMULATOR_HOST}`);
  console.log(`Project ID: ${projectId}`);
});
