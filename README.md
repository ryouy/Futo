# ふと

**「ふと開く」から、「ふと気づく」へ。**

スマホを開く前に、少し立ち止まる。何に使いたいかを確かめて、使うかどうかを自分で選ぶ。そのための iPhone アプリです（Swift / SwiftUI）。

> 開発者本人向けの試作です。公開版ではなく、解除を防止する管理アプリでもありません。制限は、本人がいつでも外せます。

## どんなアプリ？

ふだんは、選んだアプリ・カテゴリ・ウェブサイトに **制限をかけたまま** にしておきます。使いたくなったら「ふと」を開いて、ひと呼吸おいてから、使うかどうかを選びます。

1. **ふだんは制限中**　選んだものは、ふだん使えません。
2. **ひと呼吸おいて、使う**　何に使いたいかを選び、少し待ちます（標準は3分）。
3. **自分で決める**　待ったあとで「使いたい」か「やめておく」を選びます。使うなら、使うものを選んで、しばらくだけ解除します。
4. **自動で制限に戻る**　選んだ時間（1〜30分）で、制限に戻ります。
5. **あとで、そっと振り返る**　朝と夜に、記録を短い言葉でまとめます。評価や点数はつけません。

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/01-intro.png" width="170"><br>初回の説明</td>
    <td align="center"><img src="docs/screenshots/02-home.png" width="170"><br>ホーム</td>
    <td align="center"><img src="docs/screenshots/03-purpose.png" width="170"><br>何に使いたい？</td>
    <td align="center"><img src="docs/screenshots/04-wait.png" width="170"><br>少し立ち止まる</td>
    <td align="center"><img src="docs/screenshots/05-unlocked.png" width="170"><br>解除しました</td>
  </tr>
</table>

<sub>画面は開発用ビルドのもので、待機は10秒・解除は1分に短縮しています（製品ビルドの標準は待機3分・解除5分。どちらも設定で変えられます）。</sub>

## 主な機能

- **制限**：アプリ・カテゴリ・ウェブサイトを、Screen Time（Family Controls / Managed Settings）で制限します。
- **ひと呼吸**：目的を選ぶ → 待つ → 選ぶ。待つ時間は、画面が前にあるあいだだけ進みます。
- **一時解除**：選んだものだけ、設定した時間（1〜30分）解除し、自動で制限に戻ります（Device Activity の拡張を使用）。
- **記録**：今週・今月・すべて。目的と感想は円グラフ、時間帯も見られます。
- **朝夜の振り返り**：開いたときに、やわらかいカードで表示します。
- **やさしい提案**：記録が十分にあるとき、週に1回まで、設定の小さな工夫を提案します（自動では変えません）。
- **通知（任意）**：ローカル通知のみ。初期はすべてオフで、1日4件まで、静かな時間は送りません。
- **デモモード**：Screen Time を使わず、シミュレーターでも流れを試せます（実際のアプリは制限しません）。
- **テーマカラー 4色**、ダークモード対応。

記録は端末の中だけに保存します。サーバー、解析、広告、課金、AI は使っていません。

## 動かすには

- iOS 17 以降、Xcode 15.3 以降。
- シミュレーターではデモモードが使えます。制限を実際にかけるには、実機と署名の設定が必要です。
- 手順は [docs/SETUP.md](docs/SETUP.md) を見てください（Team・Bundle ID・Family Controls・App Group の設定を含みます）。

## ドキュメント

- [docs/SETUP.md](docs/SETUP.md) — Xcode での開き方、署名、Capability、実機への実行手順、確認チェックリスト
- [docs/IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md) — 実装済み／未実装／検証済み／未検証、仕様からの変更
- [docs/Futo_Claude_MVP_Spec.md](docs/Futo_Claude_MVP_Spec.md) — 初期実装仕様
- [docs/phase3.md](docs/phase3.md) — 朝夜の振り返り・傾向・提案・通知の仕様
- [docs/SPEC.md](docs/SPEC.md) — 全体仕様
