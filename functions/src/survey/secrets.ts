import {DEFAULT_SURVEY_TOKEN_SECRET} from "./token";

/** Local survey runtimes may use the checked-in dev secret. */
export function isLocalSurveyRuntime(): boolean {
  return Boolean(
    process.env.FIRESTORE_EMULATOR_HOST ||
    process.env.FUNCTIONS_EMULATOR === "true" ||
    process.env.SURVEY_ALLOW_DEV_SECRET === "1",
  );
}

/**
 * Production Cloud Functions must receive SURVEY_TOKEN_SECRET from
 * Firebase secret binding. Dev fallback is limited to local runtimes.
 */
export function surveyTokenSecret(): string {
  const configured = process.env.SURVEY_TOKEN_SECRET?.trim();
  if (configured) {
    return configured;
  }
  if (isLocalSurveyRuntime()) {
    return DEFAULT_SURVEY_TOKEN_SECRET;
  }
  throw new Error("missing_survey_token_secret");
}
