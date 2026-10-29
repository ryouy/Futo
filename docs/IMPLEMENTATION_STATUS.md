# 実装状況（Phase 0 / Phase 1）

最終更新：2026-10-29。仕様：[Futo_Claude_MVP_Spec.md](Futo_Claude_MVP_Spec.md)

## 実装済み

### Phase 0（デモ。Screen Timeは呼ばない）
- 初回説明、ホーム、目的選択、待機（標準180秒）、最終選択、結果、履歴、設定
- 待機：前面（`scenePhase == .active`）の区間のみ、単調増加時計の差分で進行。非アクティブ化時に残り時間を保存、再開で続きから
- 中断・再開（同じSession）、「この振り返りを終了」（中断として記録）
- SwiftData（Session）、日別件数（現地カレンダー、デモ／実機分離）、全削除（進行中は中断で閉じてから削除）
- デモ専用の架空アプリ選択、全画面上部の常時デモ表示
- Debug限定の5秒待機

### Phase 1（実機。署名・Capability設定後に利用可能）
- 個人向け認証（`AuthorizationCenter.requestAuthorization(for: .individual)`）
- `FamilyActivityPicker` によるアプリ単位の選択。カテゴリ・Webサイトを含む場合は保存せず選び直しを案内
- `ManagedSettingsStore` に本アプリ専用の名前を付け、`shield.applications` で制限の開始／終了
- 権限・保存した意図・ストアの内容を照合して状態表示（「確認不能」あり）。前面復帰時に再確認
- 権限を失った場合は進行中の振り返りを中断して案内
- 制限中・待機中は対象変更不可。実機→デモ切替前に実際の制限を終了（確認できなければ切替を保留）

## 実装していない（仕様どおり）
一時解除と自動再制限、Shield Configuration／Action・Device Activity等の拡張、App Groups、カテゴリ／Web制限、気分入力・アンケート・グラフ、アカウント・通知・課金・広告・AI・友人共有。

## 検証状況

| 項目 | 結果 |
| --- | --- |
| ロジックのユニットテスト14件（`FutoTests/SessionFlowTests.swift`） | **macOS上で合格**（Session／待機／集計を含むSwiftPMの一時パッケージ経由。シミュレーター上ではない） |
| 全ソースの型検査（iOS Simulator SDK 17.4 Debug／Release、iPhoneOS SDK 17.4） | **エラー・警告なし**（`swiftc -typecheck`） |
| `xcodebuild` によるビルド | **未実施**：この環境では iOS プラットフォームが未導入で destination が見つからない |
| `Futo.xcodeproj` をXcodeで開く | **未検証**（`xcodebuild` が構文を解釈できることのみ確認。ビルドは未実施） |
| シミュレーター上のUI操作・文字拡大・VoiceOver | **未検証** |
| `FutoTests` のXcode経由実行 | **未検証** |
| 実機：認証、アプリ選択、シールド表示、制限終了、権限取消、強制終了・再起動 | **未検証**（`SETUP.md` のチェックリスト） |

## 既知の制約・メモ
- 初版は、制限をホームから手動で終了できる設計。解除不能を目指していない。
- ホームの状態表示は権限と設定の照合結果で、OS上でシールドが出ているかを常時検知しない。
- 目的選択で「戻る」を押すと、まだ始まっていないSessionは破棄される（中断としては記録しない）。
- 待機の保存は非アクティブ化時。クラッシュ時は直前に保存した残り時間まで戻る（待機が延びる側）。
- `PRODUCT_BUNDLE_IDENTIFIER`（`com.ryouy.futo`）は仮の値。`DEVELOPMENT_TEAM` は空欄。
- 本番ビルドに待機短縮の手段は存在しない（`#if DEBUG`）。
