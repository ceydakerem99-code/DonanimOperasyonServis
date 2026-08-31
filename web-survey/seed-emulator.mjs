/**
 * Seeds Firestore emulator with a pending CustomerSatisfaction E2E fixture.
 * Emulator only — never targets production.
 */
import admin from "../functions/node_modules/firebase-admin/lib/index.js";
import { createSurveyToken } from "../functions/lib/survey/token.js";

const projectId =
  process.env.GCLOUD_PROJECT ||
  process.env.FIREBASE_PROJECT_ID ||
  "donanimoperasyonservis";

export const E2E_SURVEY_FIXTURE = {
  satisfactionId: "cs-e2e-local",
  workOrderId: "wo-e2e-local",
  customerId: "cust-e2e-local",
  operatorUserId: "operator-e2e-local",
  technicianUserId: "tech-e2e-local",
  workOrderNumber: "WO-E2E-001",
  customerName: "E2E Müşteri",
  customerPhone: "+905551112233",
};

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
}

if (!admin.apps.length) {
  admin.initializeApp({ projectId });
}

const db = admin.firestore();
const now = admin.firestore.Timestamp.now();

async function assertEmulatorReachable() {
  const timeoutMs = 5000;
  await Promise.race([
    db.collection("customerSatisfactions").limit(1).get(),
    new Promise((_, reject) => {
      setTimeout(() => {
        reject(new Error(
          "Firestore emulator unreachable. Install JDK 21+, then run: " +
          "JAVA_HOME=$(/usr/libexec/java_home -v 21) firebase emulators:start --only firestore --project donanimoperasyonservis"
        ));
      }, timeoutMs);
    }),
  ]);
}

async function seed() {
  await assertEmulatorReachable();
  const fixture = E2E_SURVEY_FIXTURE;

  await db.collection("customers").doc(fixture.customerId).set({
    id: fixture.customerId,
    name: fixture.customerName,
    contactPersonName: fixture.customerName,
    phoneNumber: fixture.customerPhone,
    email: "e2e@example.com",
    address: "E2E Test Adresi",
    city: "İstanbul",
    notes: null,
    createdByUserId: fixture.operatorUserId,
    createdAt: now,
    updatedAt: now,
  });

  await db.collection("workOrders").doc(fixture.workOrderId).set({
    id: fixture.workOrderId,
    workOrderNumber: fixture.workOrderNumber,
    createdByUserId: fixture.operatorUserId,
    assignedTechnicianId: fixture.technicianUserId,
    customerId: fixture.customerId,
    workType: "maintenance",
    deviceCategory: "pos",
    deviceBrand: "E2E",
    deviceModel: "Model-X",
    serialNumber: "SN-E2E-001",
    issueDescription: "E2E local survey seed",
    priority: "normal",
    scheduledDate: now,
    scheduledStart: null,
    scheduledEnd: null,
    status: "completed",
    currentPauseReason: null,
    createdAt: now,
    updatedAt: now,
    completedAt: now,
  });

  await db.collection("customerSatisfactions").doc(fixture.satisfactionId).set({
    id: fixture.satisfactionId,
    workOrderId: fixture.workOrderId,
    customerId: fixture.customerId,
    status: "pending",
    rating: null,
    comment: null,
    createdAt: now,
    updatedAt: now,
    submittedAt: null,
  });

  const token = createSurveyToken(fixture.satisfactionId);
  const surveyURL = `http://127.0.0.1:5199/survey/${token}`;

  console.log("Firestore emulator seed complete.");
  console.log(`Satisfaction ID: ${fixture.satisfactionId}`);
  console.log(`Survey token: ${token}`);
  console.log(`Survey URL: ${surveyURL}`);
  console.log(`API: http://127.0.0.1:5199/api/survey/${token}`);
}

seed().catch((error) => {
  console.error("Seed failed:", error);
  process.exit(1);
});
