import { readFileSync, writeFileSync } from "node:fs";
import { makeAbout } from "../src/lib/aboutPage";

// intro.html から、課金へのリンクを取り除いた about.html を作る。intro.html を変えたら、これを実行する。
const intro = readFileSync(new URL("../public/intro.html", import.meta.url), "utf8");
writeFileSync(new URL("../public/about.html", import.meta.url), makeAbout(intro));
console.log("public/about.html を作りました");
