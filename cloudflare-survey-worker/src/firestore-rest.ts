export type FirestoreValue =
  | { stringValue: string }
  | { integerValue: string }
  | { doubleValue: number }
  | { booleanValue: boolean }
  | { timestampValue: string }
  | { nullValue: null }
  | { mapValue: { fields?: Record<string, FirestoreValue> } }
  | { arrayValue: { values?: FirestoreValue[] } };

export type FirestoreDocument = {
  name: string;
  fields?: Record<string, FirestoreValue>;
  createTime?: string;
  updateTime?: string;
};

export function getStringField(
  doc: FirestoreDocument | undefined,
  key: string,
): string | undefined {
  const value = doc?.fields?.[key];
  if (!value || !("stringValue" in value)) {
    return undefined;
  }
  return value.stringValue;
}

export function getTimestampIso(
  doc: FirestoreDocument | undefined,
  key: string,
): string | null {
  const value = doc?.fields?.[key];
  if (!value || !("timestampValue" in value)) {
    return null;
  }
  return value.timestampValue;
}

export function toFirestoreString(value: string): FirestoreValue {
  return { stringValue: value };
}

export function toFirestoreInteger(value: number): FirestoreValue {
  return { integerValue: String(value) };
}

export function toFirestoreTimestampNow(): FirestoreValue {
  return { timestampValue: new Date().toISOString() };
}

export interface SurveyFirestore {
  getDocument(path: string): Promise<FirestoreDocument | null>;
  submitPendingSurveyUpdate(
    satisfactionId: string,
    update: {
      rating: number;
      comment: string;
    },
  ): Promise<void>;
}

type ServiceAccountConfig = {
  projectId: string;
  clientEmail: string;
  privateKey: string;
};

let cachedAccessToken: { token: string; expiresAtMs: number } | null = null;

function normalizePrivateKey(privateKey: string): string {
  return privateKey.replace(/\\n/g, "\n");
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function base64UrlEncode(value: string): string {
  return bytesToBase64(new TextEncoder().encode(value))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

async function importPkcs8PrivateKey(pem: string): Promise<CryptoKey> {
  const normalized = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return crypto.subtle.importKey(
    "pkcs8",
    bytes.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function getAccessToken(config: ServiceAccountConfig): Promise<string> {
  const nowMs = Date.now();
  if (cachedAccessToken && cachedAccessToken.expiresAtMs > nowMs + 60_000) {
    return cachedAccessToken.token;
  }

  const iat = Math.floor(nowMs / 1000);
  const exp = iat + 3600;
  const header = base64UrlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64UrlEncode(JSON.stringify({
    iss: config.clientEmail,
    sub: config.clientEmail,
    aud: "https://oauth2.googleapis.com/token",
    iat,
    exp,
    scope: "https://www.googleapis.com/auth/datastore",
  }));
  const unsigned = `${header}.${payload}`;
  const key = await importPkcs8PrivateKey(normalizePrivateKey(config.privateKey));
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${bytesToBase64(new Uint8Array(signature))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "")}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!response.ok) {
    throw new Error("firestore_auth_failed");
  }
  const json = await response.json() as { access_token?: string; expires_in?: number };
  if (!json.access_token) {
    throw new Error("firestore_auth_failed");
  }
  cachedAccessToken = {
    token: json.access_token,
    expiresAtMs: nowMs + (json.expires_in ?? 3600) * 1000,
  };
  return json.access_token;
}

export class FirestoreRestSurveyStore implements SurveyFirestore {
  private readonly baseUrl: string;
  private readonly config: ServiceAccountConfig;

  constructor(config: ServiceAccountConfig) {
    this.config = config;
    this.baseUrl =
      `https://firestore.googleapis.com/v1/projects/${config.projectId}/databases/(default)/documents`;
  }

  private documentPath(collection: string, id: string): string {
    return `${this.baseUrl}/${collection}/${id}`;
  }

  private async authorizedFetch(
    input: string,
    init: RequestInit = {},
  ): Promise<Response> {
    const token = await getAccessToken(this.config);
    const headers = new Headers(init.headers);
    headers.set("Authorization", `Bearer ${token}`);
    if (!headers.has("Content-Type") && init.body) {
      headers.set("Content-Type", "application/json");
    }
    return fetch(input, { ...init, headers });
  }

  async getDocument(path: string): Promise<FirestoreDocument | null> {
    const response = await this.authorizedFetch(path);
    if (response.status === 404) {
      return null;
    }
    if (!response.ok) {
      throw new Error("firestore_read_failed");
    }
    return await response.json() as FirestoreDocument;
  }

  async submitPendingSurveyUpdate(
    satisfactionId: string,
    update: { rating: number; comment: string },
  ): Promise<void> {
    const docPath = `projects/${this.config.projectId}/databases/(default)/documents/customerSatisfactions/${satisfactionId}`;

    const beginResponse = await this.authorizedFetch(`${this.baseUrl}:beginTransaction`, {
      method: "POST",
      body: JSON.stringify({}),
    });
    if (!beginResponse.ok) {
      throw new Error("firestore_transaction_failed");
    }
    const beginJson = await beginResponse.json() as { transaction?: string };
    if (!beginJson.transaction) {
      throw new Error("firestore_transaction_failed");
    }

    const batchGetResponse = await this.authorizedFetch(`${this.baseUrl}:batchGet`, {
      method: "POST",
      body: JSON.stringify({
        documents: [docPath],
        transaction: beginJson.transaction,
      }),
    });
    if (!batchGetResponse.ok) {
      throw new Error("firestore_transaction_failed");
    }
    const batchGetJson = await batchGetResponse.json() as Array<{
      found?: FirestoreDocument;
      missing?: string;
    }>;
    const found = batchGetJson[0]?.found;
    if (!found) {
      throw new Error("not_found");
    }
    if (getStringField(found, "status") !== "pending") {
      throw new Error("not_pending");
    }

    const commitResponse = await this.authorizedFetch(`${this.baseUrl}:commit`, {
      method: "POST",
      body: JSON.stringify({
        transaction: beginJson.transaction,
        writes: [{
          update: {
            name: docPath,
            fields: {
              status: toFirestoreString("submitted"),
              rating: toFirestoreInteger(update.rating),
              comment: toFirestoreString(update.comment),
              submittedAt: toFirestoreTimestampNow(),
              updatedAt: toFirestoreTimestampNow(),
            },
          },
          updateMask: {
            fieldPaths: ["status", "rating", "comment", "submittedAt", "updatedAt"],
          },
          currentDocument: {
            updateTime: found.updateTime,
          },
        }],
      }),
    });
    if (!commitResponse.ok) {
      throw new Error("firestore_transaction_failed");
    }
  }
}

export function createFirestoreStore(env: {
  FIREBASE_PROJECT_ID: string;
  FIREBASE_CLIENT_EMAIL: string;
  FIREBASE_PRIVATE_KEY: string;
}): SurveyFirestore {
  return new FirestoreRestSurveyStore({
    projectId: env.FIREBASE_PROJECT_ID,
    clientEmail: env.FIREBASE_CLIENT_EMAIL,
    privateKey: env.FIREBASE_PRIVATE_KEY,
  });
}
