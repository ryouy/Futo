/**
 * アプリの「設定 → その他」から開く、紹介サイトのページ（/about）。
 * トップページ（intro.html）と同じ内容で、課金のページ（/support）へのリンクだけを、取り除く
 * （アプリの中から、アプリ外の購入ページへ、誘導しないため）。
 * プライバシーポリシーからトップへ戻るリンクも、/about へ戻るようにする（?from=about）。
 */
export function makeAbout(intro: string): string {
  let html = intro;
  // フッターの「ふとを応援」と、その区切り
  html = html.replace(/<a href="\/support">[\s\S]*?<\/a>\s*・\s*/, "");
  // プライバシーポリシーは、/about に戻れる形で開く
  html = html.replace('<a href="/privacy">', '<a href="/privacy?from=about">');
  // 検索結果には、トップと重複して出さない
  html = html.replace('<meta name="theme-color"', '<meta name="robots" content="noindex">\n  <meta name="theme-color"');
  return html;
}
