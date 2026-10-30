# Phase 4 セットアップ手順（ログイン・共有・フレンド）

このリポジトリの状態では、共有機能は **「未設定」** です。`Futo/Resources/Phase4Config.plist` が空のあいだ、アプリは共有タブに「まだ使えません」と表示し、個人の機能（制限・ひと呼吸・記録・通知）は今まで通り動きます。
以下は、すべて無料枠（Vercel Hobby + Firebase Spark）の範囲です。Cloud Functions・Storage・有料プランは使いません。

> 秘密の値（サービスアカウントの鍵など）は、リポジトリに入れません。Vercel の環境変数にだけ設定します。

## 1. Firebase プロジェクト（Spark）

1. <https://console.firebase.google.com> で、プロジェクトを作る（Sparkのまま。Blazeへのアップグレードはしない）。
2. **Authentication → Sign-in method → Google** を有効にする。
3. **Firestore Database** を作成する（本番モード。リージョンは近いもの）。
4. **ウェブAPIキー**を控える（プロジェクトの設定 → 全般）。これは公開してよい値で、アプリの `FirebaseAPIKey` に入れる。
5. **サービスアカウント**：プロジェクトの設定 → サービスアカウント → 「新しい秘密鍵を生成」。JSONの `project_id` / `client_email` / `private_key` を、手順3で使う。**このJSONは、リポジトリに置かない。**
6. ルールとインデックスをデプロイする：
   ```sh
   cd web
   npx firebase login
   npx firebase deploy --only firestore:rules,firestore:indexes --project <プロジェクトID>
   ```
   - ルールは「クライアントからの読み書きをすべて拒否」です（アクセスはVercelのサーバー経由だけ）。
   - 複合インデックスはエミュレーターでは検証されません。デプロイ後、実際に使ったときにインデックス不足のエラーが出たら、エラーに含まれるリンクから作成してください。

## 2. Google OAuth（iOS用クライアントID）

1. <https://console.cloud.google.com> で、手順1と同じプロジェクトを開く → **APIとサービス → 認証情報**。
2. **OAuth 同意画面**を設定する（スコープの追加は不要です。アプリは `openid profile` を要求し、Googleの名前を表示名の初期値に、アイコン画像をアプリ内の表示だけに使います（画像はサーバーに送りません）。メールは取得しません）。公開前は「テスト」状態で、テストユーザーに自分を追加する。
3. **認証情報を作成 → OAuth クライアントID → iOS**。バンドルIDは `com.ryouy.futo`。
4. 表示された**クライアントID**（`123-abc.apps.googleusercontent.com`）を控える。
   - リダイレクト用のURLスキームは、アプリがクライアントIDから自動で作ります（`com.googleusercontent.apps.123-abc`）。Info.plist への登録は不要です（ASWebAuthenticationSession を使うため）。

## 3. Vercel（Hobby）

1. <https://vercel.com> で、このGitHubリポジトリをインポートし、**Root Directory を `web`** にする。
2. **Settings → Environment Variables**（Production）に、`web/.env.example` の項目を設定する：

   | 変数 | 値 |
   |---|---|
   | `FIREBASE_PROJECT_ID` | サービスアカウントJSONの `project_id` |
   | `FIREBASE_CLIENT_EMAIL` | 同 `client_email` |
   | `FIREBASE_PRIVATE_KEY` | 同 `private_key`（改行は `\n` のまま） |
   | `PUBLIC_BASE_URL` | 本番の安定したURL（例：`https://futo-share.vercel.app`。Previewのドメインにしない） |
   | `APPLE_TEAM_ID` | Apple Developer の Team ID（手順5。不要なら未設定のまま） |
   | `IOS_BUNDLE_ID` | `com.ryouy.futo` |
   | `RATE_LIMIT_SALT` | ランダムな長い文字列（例：`openssl rand -base64 32`） |

3. デプロイする。未設定の項目があるあいだ、APIは **503 `not_configured`** を返し、成功を装いません。
4. 確認：`https://<ドメイン>/api/public/shares/xxxx` が、404（または400）を JSON で返し、`Cache-Control: private, no-store` が付いていること。

## 4. アプリ側（`Phase4Config.plist`）

`Futo/Resources/Phase4Config.plist` に、公開してよい3つの値を入れる：

- `APIBaseURL`：手順3の `PUBLIC_BASE_URL`（HTTPSのみ有効）
- `FirebaseAPIKey`：手順1-4のウェブAPIキー
- `GoogleClientID`：手順2のクライアントID

3つがそろうと、共有タブが「Googleでログイン」に変わります。

## 5. 招待リンクをアプリで開く（Universal Links・任意）

Universal Links は、**自分のドメイン**と Apple Developer の有料アカウント（Team ID）が必要です。なくても、招待は「リンクをブラウザで開いて招待ページを見る」「招待コードをアプリに入力する」で使えます。

1. 手順3で `APPLE_TEAM_ID` と `IOS_BUNDLE_ID` を設定する → `/.well-known/apple-app-site-association` が配信される（`/i/*` だけが対象。統計の共有リンク `/s/*` はアプリで開かない）。
2. Xcode の Signing & Capabilities → **Associated Domains** に `applinks:<ドメイン>` を追加する（このリポジトリには、ドメインが決まっていないため入れていません）。
3. 実機で、招待リンクをメモなどからタップして確認する（シミュレーターでは確認していません）。

## 6. 動作確認の手順（実機）

1. 共有タブ → Googleでログイン → 表示名が出る。
2. 統計をリンクで共有 → 項目を選ぶ → プレビューの数字を確認 → リンクを作る → ブラウザでリンクを開く。
3. 共有中のリンク → 共有をやめる → 同じリンクを開くと「見られません」になる。
4. 2台（または2アカウント）で、フレンド招待 → 申請 → 承認 → フレンド限定共有 → 相手の端末で見られる。
5. フレンドをやめる／ブロックすると、見られなくなる。
6. アカウントを削除 → 再ログイン確認のあと、共有・フレンド・リンクが無効になる。

## 7. 運用メモ

- 期限切れデータの整理（手動）：`cd web && npm run cleanup:dry-run`（件数だけ）、削除は `npx tsx scripts/cleanup.ts --apply`。
- ローカルで試す：`cd web && npm ci && npm test`（Java 21 が必要。Firebase Emulator を使い、本番には接続しません）。
- 無料枠を超えそうなとき、プランは自動では変わりません。上限に達すると、機能が止まります（課金は発生しません）。
