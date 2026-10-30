/** @type {import('next').NextConfig} */
const noStore = [
  { key: "Cache-Control", value: "private, no-store" },
  { key: "X-Robots-Tag", value: "noindex, nofollow, noarchive" },
];

const nextConfig = {
  poweredByHeader: false,
  // トップページは、アプリの紹介ページ（public/intro.html）。共有・招待リンクとは別
  async rewrites() {
    return { beforeFiles: [{ source: "/", destination: "/intro.html" }] };
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
      { source: "/api/:path*", headers: noStore },
    ];
  },
};

export default nextConfig;
