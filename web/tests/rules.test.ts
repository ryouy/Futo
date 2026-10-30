import { readFileSync } from "node:fs";
import { assertFails, initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc } from "firebase/firestore";
import { afterAll, beforeAll, describe, it } from "vitest";

let env: RulesTestEnvironment;

beforeAll(async () => {
  const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080").split(":");
  env = await initializeTestEnvironment({
    projectId: "demo-futo",
    firestore: { rules: readFileSync("firestore.rules", "utf8"), host, port: Number(port) },
  });
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "shares/s1"), { ownerUid: "alice" });
    await setDoc(doc(context.firestore(), "friendships/a_b"), { members: ["a", "b"] });
  });
});

afterAll(async () => {
  await env.cleanup();
});

describe("Firestoreルール：クライアントからの直接アクセスは、すべて拒否", () => {
  it("ログイン済みでも、他人のドキュメントの読み書きができない", async () => {
    const alice = env.authenticatedContext("alice").firestore();
    await assertFails(getDoc(doc(alice, "shares/s1")));
    await assertFails(setDoc(doc(alice, "shares/s1"), { ownerUid: "alice", extra: true }));
    await assertFails(setDoc(doc(alice, "shares/new"), { ownerUid: "alice" }));
  });
  it("フレンド関係も、当事者でも、クライアントからは読み書きできない", async () => {
    const a = env.authenticatedContext("a").firestore();
    await assertFails(getDoc(doc(a, "friendships/a_b")));
    await assertFails(setDoc(doc(a, "friendships/a_b"), { members: ["a", "c"] }));
  });
  it("未ログインでも、読み書きできない", async () => {
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, "shares/s1")));
    await assertFails(setDoc(doc(anon, "users/x"), { displayName: "x" }));
  });
});
