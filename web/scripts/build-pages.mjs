import { cp, mkdir, readFile, writeFile } from "node:fs/promises";

const source = new URL("../public/", import.meta.url);
const destination = new URL("../../_site/", import.meta.url);
const pagesBase = "https://ryouy.github.io/Futo";
const vercelBase = "https://futo-share.vercel.app";

await mkdir(destination, { recursive: true });
await cp(source, destination, { recursive: true });

const documents = [
  ["intro.html", "index.html", "/"],
  ["about.html", "about.html", "/about"],
  ["privacy.html", "privacy.html", "/privacy"],
  ["help.html", "help.html", "/help"],
];

for (const [sourceName, outputName, canonicalPath] of documents) {
  let html = await readFile(new URL(sourceName, source), "utf8");
  // Keep dynamic invite/share/API links on Vercel; this deployment is static only.
  html = html.replace(/(href|src)=(["'])\/(?!\/)([^"']*)\2/g, (full, attribute, quote, path) => {
    if (path === "support" || path.startsWith("support?")) {
      return `${attribute}=${quote}${vercelBase}/${path}${quote}`;
    }
    const match = path.match(/^(privacy|help|about)(\?.*)?$/);
    const target = match ? `${match[1]}.html${match[2] ?? ""}` : path;
    return `${attribute}=${quote}/Futo/${target}${quote}`;
  });
  const canonical = `${pagesBase}${canonicalPath === "/" ? "/" : canonicalPath + ".html"}`;
  html = html.replace(
    /(<link\s+rel=["']canonical["']\s+href=["'])[^"']+(["'])/i,
    `$1${canonical}$2`,
  );
  // The legacy Vercel domain remains valid for invitation and API endpoints.
  await writeFile(new URL(outputName, destination), html);
}

await writeFile(new URL(".nojekyll", destination), "");
console.log("Static Futo introduction prepared for GitHub Pages");
