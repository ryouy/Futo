import path from "node:path";
import { defineConfig } from "vitest/config";

export default defineConfig({
  esbuild: { jsx: "automatic" },
  resolve: { alias: { "@": path.resolve(__dirname, "src") } },
  test: {
    environment: "node",
    // エミュレーターは1つなので、テストファイルは順番に実行する
    fileParallelism: false,
    testTimeout: 30_000,
    hookTimeout: 30_000,
    env: { FIREBASE_PROJECT_ID: "demo-futo", PUBLIC_BASE_URL: "https://share.example.test" },
  },
});
