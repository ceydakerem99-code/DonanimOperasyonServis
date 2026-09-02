import * as admin from "firebase-admin";
import {
  buildStructuredComment,
  validateSubmissionPayload,
} from "./comment";
import {surveyTokenSecret} from "./secrets";
import {verifySurveyToken} from "./token";

export type SurveyContextResponse = {
  workOrderNumber: string;
  customerName: string;
  workTypeLabel: string;
  completedAt: string | null;
  status: string;
};

function firestore() {
  return admin.firestore();
}

async function loadWorkOrderContext(workOrderId: string): Promise<{
  workOrderNumber: string;
  customerName: string;
  workTypeLabel: string;
  completedAt: string | null;
}> {
  const workOrderSnap = await firestore().collection("workOrders").doc(workOrderId).get();
  if (!workOrderSnap.exists) {
    throw new Error("not_found");
  }

  const workOrder = workOrderSnap.data() ?? {};
  const customerId = typeof workOrder.customerId === "string" ? workOrder.customerId : "";
  let customerName = "Müşteri";
  if (customerId) {
    const customerSnap = await firestore().collection("customers").doc(customerId).get();
    if (customerSnap.exists) {
      const customer = customerSnap.data() ?? {};
      if (typeof customer.name === "string" && customer.name.trim()) {
        customerName = customer.name.trim();
      }
    }
  }

  const completedAt =
    workOrder.completedAt instanceof admin.firestore.Timestamp
      ? workOrder.completedAt.toDate().toISOString()
      : null;

  return {
    workOrderNumber:
      typeof workOrder.workOrderNumber === "string" ? workOrder.workOrderNumber : "—",
    customerName,
    workTypeLabel: workTypeLabel(workOrder.workType),
    completedAt,
  };
}

function workTypeLabel(raw: unknown): string {
  switch (raw) {
  case "installation": return "Kurulum";
  case "maintenance": return "Bakım";
  case "repair": return "Arıza";
  case "delivery": return "Teslim";
  default: return typeof raw === "string" && raw ? raw : "Servis";
  }
}

export async function getSurveyContext(token: string): Promise<SurveyContextResponse> {
  const satisfactionId = verifySurveyToken(token, surveyTokenSecret());
  if (!satisfactionId) {
    throw new Error("invalid_token");
  }

  const satisfactionSnap = await firestore()
    .collection("customerSatisfactions")
    .doc(satisfactionId)
    .get();

  if (!satisfactionSnap.exists) {
    throw new Error("not_found");
  }

  const satisfaction = satisfactionSnap.data() ?? {};
  const workOrderId =
    typeof satisfaction.workOrderId === "string" ? satisfaction.workOrderId : "";
  if (!workOrderId) {
    throw new Error("not_found");
  }

  const context = await loadWorkOrderContext(workOrderId);
  return {
    ...context,
    status: typeof satisfaction.status === "string" ? satisfaction.status : "pending",
  };
}

export async function submitSurvey(token: string, body: unknown): Promise<void> {
  const satisfactionId = verifySurveyToken(token, surveyTokenSecret());
  if (!satisfactionId) {
    throw new Error("invalid_token");
  }

  const parsed = validateSubmissionPayload(body);
  if (!parsed.ok) {
    throw new Error(parsed.message);
  }

  const docRef = firestore().collection("customerSatisfactions").doc(satisfactionId);

  await firestore().runTransaction(async (transaction) => {
    const snap = await transaction.get(docRef);
    if (!snap.exists) {
      throw new Error("not_found");
    }

    const data = snap.data() ?? {};
    if (data.status !== "pending") {
      throw new Error("not_pending");
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    transaction.update(docRef, {
      status: "submitted",
      rating: parsed.value.overallRating,
      comment: buildStructuredComment(parsed.value),
      submittedAt: now,
      updatedAt: now,
    });
  });
}
