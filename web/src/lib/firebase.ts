import { cert, getApps, initializeApp, type App } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";

/** サーバー設定が足りないときに投げる。呼び出し側は「利用できません」と返し、成功を装わない。 */
export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigError";
  }
}

const usingEmulator = () => Boolean(process.env.FIRESTORE_EMULATOR_HOST);

/** Firebase が設定済みか（エミュレーターでも true）。 */
export function isConfigured(): boolean {
  if (usingEmulator()) return true;
  return Boolean(
    process.env.FIREBASE_PROJECT_ID &&
      process.env.FIREBASE_CLIENT_EMAIL &&
      process.env.FIREBASE_PRIVATE_KEY,
  );
}

export function adminApp(): App {
  const existing = getApps()[0];
  if (existing) return existing;
  const projectId = process.env.FIREBASE_PROJECT_ID;
  if (!projectId) throw new ConfigError("FIREBASE_PROJECT_ID が未設定です");
  if (usingEmulator()) return initializeApp({ projectId });
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
  const privateKey = process.env.FIREBASE_PRIVATE_KEY;
  if (!clientEmail || !privateKey) {
    throw new ConfigError("FIREBASE_CLIENT_EMAIL / FIREBASE_PRIVATE_KEY が未設定です");
  }
  // Vercelの環境変数では、改行が \n の文字として入る
  return initializeApp({
    credential: cert({ projectId, clientEmail, privateKey: privateKey.replace(/\\n/g, "\n") }),
    projectId,
  });
}

export const db = () => getFirestore(adminApp());
export const adminAuth = () => getAuth(adminApp());
