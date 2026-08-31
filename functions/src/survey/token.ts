import * as crypto from "crypto";

export const DEFAULT_SURVEY_TOKEN_SECRET = "dops-survey-dev-secret";

export function createSurveyToken(
  satisfactionId: string,
  secret: string = DEFAULT_SURVEY_TOKEN_SECRET,
): string {
  const idPart = Buffer.from(satisfactionId, "utf8").toString("base64url");
  const signature = crypto
    .createHmac("sha256", secret)
    .update(satisfactionId, "utf8")
    .digest("base64url");
  return `${idPart}.${signature}`;
}

export function verifySurveyToken(
  token: string,
  secret: string = DEFAULT_SURVEY_TOKEN_SECRET,
): string | null {
  const parts = token.split(".");
  if (parts.length !== 2 || !parts[0] || !parts[1]) {
    return null;
  }

  let satisfactionId: string;
  try {
    satisfactionId = Buffer.from(parts[0], "base64url").toString("utf8");
  } catch {
    return null;
  }

  if (!satisfactionId) {
    return null;
  }

  const expected = crypto
    .createHmac("sha256", secret)
    .update(satisfactionId, "utf8")
    .digest("base64url");

  const actual = Buffer.from(parts[1]);
  const expectedBuffer = Buffer.from(expected);
  if (
    actual.length !== expectedBuffer.length ||
    !crypto.timingSafeEqual(actual, expectedBuffer)
  ) {
    return null;
  }

  return satisfactionId;
}
