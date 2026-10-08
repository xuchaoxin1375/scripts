// 轻量构建：单文件前端，无依赖，直接复制 src/index.html 到 dist/index.html。
import { copyFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
mkdirSync(join(root, "dist"), { recursive: true });
copyFileSync(join(root, "src", "index.html"), join(root, "dist", "index.html"));
console.log("build ok: src/index.html -> dist/index.html");
