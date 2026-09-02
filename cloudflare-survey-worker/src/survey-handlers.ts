import {
  buildStructuredComment,
  validateSubmissionPayload,
} from "./comment";
import {
  getStringField,
  getTimestampIso,
  type SurveyFirestore,
} from "./firestore-rest";
import { verifySurveyToken } from "./token";

export type SurveyContextResponse = {
  workOrderNumber: string;
  customerName: string;
  workTypeLabel: string;
  completedAt: string | null;
  status: string;
};

function workTypeLabel(raw: string | undefined): string {
  switch (raw) {
  case "installation": return "Kurulum";
  case "maintenance": return "Bakım";
  case "repair": return "Arıza";
  case "delivery": return "Teslim";
  default: return raw && raw.trim() ? raw : "Servis";
  }
}

async function loadWorkOrderContext(
  store: SurveyFirestore,
  projectId: string,
  workOrderId: string,
): Promise<{
  workOrderNumber: string;
  customerName: string;
  workTypeLabel: string;
  completedAt: string | null;
}> {
  const baseUrl =
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
  const workOrder = await store.getDocument(`${baseUrl}/workOrders/${workOrderId}`);
  if (!workOrder) {
    throw new Error("not_found");
  }

  const customerId = getStringField(workOrder, "customerId") ?? "";
  let customerName = "Müşteri";
  if (customerId) {
    const customer = await store.getDocument(`${baseUrl}/customers/${customerId}`);
    const name = getStringField(customer ?? undefined, "name")?.trim();
    if (name) {
      customerName = name;
    }
  }

  return {
    workOrderNumber: getStringField(workOrder, "workOrderNumber") ?? "—",
    customerName,
    workTypeLabel: workTypeLabel(getStringField(workOrder, "workType")),
    completedAt: getTimestampIso(workOrder, "completedAt"),
  };
}

export async function getSurveyContext(
  token: string,
  tokenSecret: string,
  store: SurveyFirestore,
  projectId: string,
): Promise<SurveyContextResponse> {
  const satisfactionId = await verifySurveyToken(token, tokenSecret);
  if (!satisfactionId) {
    throw new Error("invalid_token");
  }

  const baseUrl =
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
  const satisfaction = await store.getDocument(
    `${baseUrl}/customerSatisfactions/${satisfactionId}`,
  );
  if (!satisfaction) {
    throw new Error("not_found");
  }

  const workOrderId = getStringField(satisfaction, "workOrderId") ?? "";
  if (!workOrderId) {
    throw new Error("not_found");
  }

  const context = await loadWorkOrderContext(store, projectId, workOrderId);
  return {
    ...context,
    status: getStringField(satisfaction, "status") ?? "pending",
  };
}

export async function submitSurvey(
  token: string,
  body: unknown,
  tokenSecret: string,
  store: SurveyFirestore,
): Promise<void> {
  const satisfactionId = await verifySurveyToken(token, tokenSecret);
  if (!satisfactionId) {
    throw new Error("invalid_token");
  }

  const parsed = validateSubmissionPayload(body);
  if (!parsed.ok) {
    throw new Error(parsed.message);
  }

  await store.submitPendingSurveyUpdate(satisfactionId, {
    rating: parsed.value.overallRating,
    comment: buildStructuredComment(parsed.value),
  });
}
