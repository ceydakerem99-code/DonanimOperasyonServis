export const DEFAULT_SURVEY_TOKEN_SECRET = "dops-survey-dev-secret";

function base64UrlToBytes(value: string): Uint8Array | null {
  try {
    const padded = value.replace(/-/g, "+").replace(/_/g, "/");
    const pad = padded.length % 4 === 0 ? "" : "=".repeat(4 - (padded.length % 4));
    const binary = atob(padded + pad);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  } catch {
    return null;
  }
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function hmacSha256Base64Url(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message),
  );
  return bytesToBase64Url(new Uint8Array(signature));
}

function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) {
    diff |= a[i] ^ b[i];
  }
  return diff === 0;
}

export async function verifySurveyToken(
  token: string,
  secret: string = DEFAULT_SURVEY_TOKEN_SECRET,
): Promise<string | null> {
  const parts = token.split(".");
  if (parts.length !== 2 || !parts[0] || !parts[1]) {
    return null;
  }

  const idBytes = base64UrlToBytes(parts[0]);
  if (!idBytes) {
    return null;
  }
  const satisfactionId = new TextDecoder().decode(idBytes);
  if (!satisfactionId) {
    return null;
  }

  const expected = await hmacSha256Base64Url(secret, satisfactionId);
  const actual = base64UrlToBytes(parts[1]);
  const expectedBytes = base64UrlToBytes(expected);
  if (!actual || !expectedBytes || !timingSafeEqual(actual, expectedBytes)) {
    return null;
  }

  return satisfactionId;
}
