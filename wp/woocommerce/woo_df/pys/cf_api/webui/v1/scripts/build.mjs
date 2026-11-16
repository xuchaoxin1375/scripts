// 轻量构建：无依赖，复制单文件前端与页面图标到 dist/。
import { copyFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
mkdirSync(join(root, "dist"), { recursive: true });
for (const file of ["index.html", "favicon.svg", "favicon.ico"]) {
  copyFileSync(join(root, "src", file), join(root, "dist", file));
}
console.log("build ok: src/index.html + favicon.* -> dist/");
