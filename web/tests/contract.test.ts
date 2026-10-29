import { readFileSync } from "node:fs";
import path from "node:path";
import { beforeEach, describe, expect, it } from "vitest";
import { friendSharePayload, webSharePayload } from "@/lib/schema";
import { call, newUser, resetAll } from "./helpers";

beforeEach(resetAll);

const fixture = (name: string) => JSON.parse(readFileSync(path.join(__dirname, "fixtures", name), "utf8"));

/** iOSアプリ（Swiftのテスト）が出力した固定データを、サーバーの検証で受け付けるかを確かめる。 */
describe("iOSとサーバーの取り決め", () => {
  it("iOSが作るWeb共有のデータを、サーバーが受け付ける", async () => {
    const payload = fixture("ios-web-share-payload.json");
    expect(webSharePayload.safeParse(payload).success).toBe(true);
    const owner = await newUser("はなこ");
    const response = await call("POST", "/api/shares", { token: owner.token, body: payload });
    expect(response.status).toBe(201);
    const publicView = await call("GET", `/api/public/shares/${response.body.token}`);
    expect(publicView.body.stats.counts).toEqual(payload.counts);
    expect(publicView.body.stats.purposes).toEqual(payload.purposes);
    expect(publicView.body.stats.feelings).toMatchObject(payload.feelings);
    expect(publicView.body.stats.phrase).toBeTruthy();
  });

  it("iOSが作るフレンド共有のデータを、サーバーが受け付ける", () => {
    const payload = fixture("ios-friend-share-payload.json");
    expect(friendSharePayload.safeParse(payload).success).toBe(true);
    expect(payload).not.toHaveProperty("expiresInDays");
  });

  it("サーバーは、iOSの出力にない余分な項目を受け付けない（取り決めがずれたら気づける）", () => {
    const payload = fixture("ios-web-share-payload.json");
    expect(webSharePayload.safeParse({ ...payload, ownerUid: "x" }).success).toBe(false);
  });
});
