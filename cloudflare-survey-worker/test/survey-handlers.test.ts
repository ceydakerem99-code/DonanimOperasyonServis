import { describe, expect, it, vi } from "vitest";
import { createHmac } from "node:crypto";
import type { FirestoreDocument, SurveyFirestore } from "../src/firestore-rest";
import { getSurveyContext, submitSurvey } from "../src/survey-handlers";
import { handleSurveyRequest } from "../src/index";

const SECRET = "test-survey-secret";
const PROJECT_ID = "donanimoperasyonservis";

function createToken(satisfactionId: string, secret = SECRET): string {
  const idPart = Buffer.from(satisfactionId, "utf8").toString("base64url");
  const signature = createHmac("sha256", secret).update(satisfactionId, "utf8").digest("base64url");
  return `${idPart}.${signature}`;
}

function doc(fields: Record<string, unknown>, updateTime = "2026-01-01T00:00:00.000000Z"): FirestoreDocument {
  const mapped: FirestoreDocument["fields"] = {};
  for (const [key, value] of Object.entries(fields)) {
    if (typeof value === "string") {
      mapped[key] = { stringValue: value };
    } else if (typeof value === "number") {
      mapped[key] = { integerValue: String(value) };
    }
  }
  return {
    name: "projects/test/databases/(default)/documents/mock/doc",
    fields: mapped,
    updateTime,
  };
}

function createMockStore(overrides: Partial<SurveyFirestore> = {}): SurveyFirestore {
  return {
    getDocument: vi.fn(),
    submitPendingSurveyUpdate: vi.fn(),
    ...overrides,
  };
}

describe("survey handlers", () => {
  const baseUrl =
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

  it("valid token returns survey context", async () => {
    const satisfactionId = "cs-valid-1";
    const token = createToken(satisfactionId);
    const store = createMockStore({
      getDocument: vi.fn(async (path: string) => {
        if (path.endsWith(`/customerSatisfactions/${satisfactionId}`)) {
          return doc({ status: "pending", workOrderId: "wo-1" });
        }
        if (path.endsWith("/workOrders/wo-1")) {
          return doc({
            workOrderNumber: "WO-100",
            customerId: "cust-1",
            workType: "repair",
          });
        }
        if (path.endsWith("/customers/cust-1")) {
          return doc({ name: "Ali Veli" });
        }
        return null;
      }),
    });

    const context = await getSurveyContext(token, SECRET, store, PROJECT_ID);
    expect(context.workOrderNumber).toBe("WO-100");
    expect(context.customerName).toBe("Ali Veli");
    expect(context.workTypeLabel).toBe("Arıza");
    expect(context.status).toBe("pending");
  });

  it("invalid token returns 403 invalid_token", async () => {
    const store = createMockStore();
    await expect(getSurveyContext("bad.token", SECRET, store, PROJECT_ID))
      .rejects.toThrow("invalid_token");
  });

  it("malformed token is rejected", async () => {
    const store = createMockStore();
    await expect(getSurveyContext("not-a-valid-token", SECRET, store, PROJECT_ID))
      .rejects.toThrow("invalid_token");
  });

  it("token signature mismatch is rejected", async () => {
    const token = createToken("cs-1", "other-secret");
    const store = createMockStore();
    await expect(getSurveyContext(token, SECRET, store, PROJECT_ID))
      .rejects.toThrow("invalid_token");
  });

  it("missing survey returns not_found", async () => {
    const token = createToken("missing-cs");
    const store = createMockStore({
      getDocument: vi.fn(async () => null),
    });
    await expect(getSurveyContext(token, SECRET, store, PROJECT_ID))
      .rejects.toThrow("not_found");
  });

  it("valid survey submit updates Firestore", async () => {
    const satisfactionId = "cs-submit-1";
    const token = createToken(satisfactionId);
    const submit = vi.fn(async () => undefined);
    const store = createMockStore({ submitPendingSurveyUpdate: submit });

    await submitSurvey(token, {
      overallRating: 5,
      serviceQualityRating: 5,
      staffCareRating: 4,
      resolutionSpeedRating: 5,
      experienceTags: ["Hızlı çözüldü"],
      freeformComment: "Harika",
    }, SECRET, store);

    expect(submit).toHaveBeenCalledWith(satisfactionId, {
      rating: 5,
      comment: expect.stringContaining("Harika"),
    });
  });

  it("duplicate submit preserves not_pending behavior", async () => {
    const token = createToken("cs-dup");
    const store = createMockStore({
      submitPendingSurveyUpdate: vi.fn(async () => {
        throw new Error("not_pending");
      }),
    });

    await expect(submitSurvey(token, {
      overallRating: 4,
      serviceQualityRating: 4,
      staffCareRating: 4,
      resolutionSpeedRating: 4,
    }, SECRET, store)).rejects.toThrow("not_pending");
  });

  it("unauthorized access via HTTP returns invalid_token", async () => {
    const response = await handleSurveyRequest(
      new Request("https://worker.example/api/survey/totally.invalid", { method: "GET" }),
      {
        FIREBASE_PROJECT_ID: PROJECT_ID,
        FIREBASE_CLIENT_EMAIL: "svc@test.iam.gserviceaccount.com",
        FIREBASE_PRIVATE_KEY: "-----BEGIN PRIVATE KEY-----\nMIIB...\n-----END PRIVATE KEY-----\n",
        SURVEY_TOKEN_SECRET: SECRET,
      },
    );
    expect(response.status).toBe(403);
    const body = await response.json() as { error: string };
    expect(body.error).toBe("invalid_token");
  });
});
