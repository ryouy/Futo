/** @type {import('next').NextConfig} */
const noStore = [
  { key: "Cache-Control", value: "private, no-store" },
  { key: "X-Robots-Tag", value: "noindex, nofollow, noarchive" },
];

const nextConfig = {
  poweredByHeader: false,
  // GitHub Pages の公開確認後に FUTO_PAGES_REDIRECTS_ENABLED=1 で有効化する。
  // 共有・招待・API・Web課金 (/support) は引き続きこのサーバーで扱う。
  async redirects() {
    if (process.env.FUTO_PAGES_REDIRECTS_ENABLED !== "1") return [];
    const pages = "https://ryouy.github.io/Futo";
    return [
      { source: "/", destination: `${pages}/`, permanent: false },
      { source: "/intro.html", destination: `${pages}/`, permanent: false },
      { source: "/about", destination: `${pages}/about.html`, permanent: false },
      { source: "/about.html", destination: `${pages}/about.html`, permanent: false },
      { source: "/privacy", destination: `${pages}/privacy.html`, permanent: false },
      { source: "/privacy.html", destination: `${pages}/privacy.html`, permanent: false },
      { source: "/help", destination: `${pages}/help.html`, permanent: false },
      { source: "/help.html", destination: `${pages}/help.html`, permanent: false },
    ];
  },
  // トップページは、アプリの紹介ページ（public/intro.html）。共有・招待リンクとは別
  async rewrites() {
    return { beforeFiles: [{ source: "/", destination: "/intro.html" }, { source: "/privacy", destination: "/privacy.html" }, { source: "/about", destination: "/about.html" }, { source: "/help", destination: "/help.html" }] };
  },
  async headers() {
    return [
      {
        // どのページ・APIでも、トークン付きURLを外へ送らず、型の推測もさせない
        source: "/:path*",
        headers: [
          { key: "Referrer-Policy", value: "no-referrer" },
          { key: "X-Content-Type-Options", value: "nosniff" },
          {
            key: "Content-Security-Policy",
            value: "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
          },
        ],
      },
      // 共有・招待・APIは、共有CDN・ISR・静的生成に残さない
      { source: "/s/:path*", headers: noStore },
      { source: "/i/:path*", headers: noStore },
      { source: "/support", headers: noStore },
      { source: "/legal", headers: noStore },
      { source: "/api/:path*", headers: noStore },
    ];
  },
};

export default nextConfig;
