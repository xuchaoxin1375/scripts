# AGENTS.md — nginx_conf（OpenResty 站点配置集）agent 入口

> 全仓红线见仓库根 `AGENTS.md`；`PS/` 细则见 `PS/AGENTS.md`，与本目录无关时不读。本文件只界定本目录的工作边界与入口指引，细节以 `docs/` 为准，不在此复制。

## 作用范围

- 本目录：`com_*.conf`（`com_js_signed.conf` 等挑战/限流/日志片段）、`*_vhost*.conf`、`nginx_*.conf`、`js_challenge*.html`、`docs/`（三份说明）、`archived/`、`js_fake/`、`reverse_proxy/`（另有其 `AGENTS.md`）。
- `com_js_signed.conf` 为 `server` 块片段，不可单文件直测，须包一层最小 `harness` 再验。
- 不碰目录外文件；现有文档只读不改，除非任务明确要求。

## 红线（本目录适用）

- 换行：存量文件不动；提交前必跑 `git diff` 与 `git diff --ignore-cr-at-eol` 对照。
- 记住指令入库：用户以“记住”下达的长期约束，须同步落盘到本 `AGENTS.md` 对应条款，不只记在会话内。
- 暂存只点名本次文件，禁止 `git add -A`（工作区常有无关文件）。
- 提交信息 `feat:/fix:/chore:` 加中文简述；提交后验 `HEAD`（`--stat`、抽查关键文件、状态干净）；推送与 `PR` 须用户明确指示。
- 密钥与真实资产：`com_secret.conf` 只放占位写法，不入库真实密钥；分享 `nginx -T` 输出前先脱敏。

## 文档入口（只放指引）

| 文档 | 说明 |
| --- | --- |
| `docs/Readme@nginx_conf@Nginx配置总说明文档.md` | 本目录配置总体说明（先读） |
| `docs/README_js_challenge_signed.md` | `com_js_signed.conf` 设计说明（`$sc2_ok`、`$sc_suspected_se_bot` 语义以此为准） |
| `docs/Readme@Nginx配置修改脚本说明@Nginx分批次施加限流@为新站配置宽松限流.md` | 限流施加脚本说明 |

## 验证入口

- 本机 `nginx.exe`（如 `phpstudy` 自带 stock 版）不可用于校验：不含 `lua-nginx-module`，必对 `access_by_lua_block` 等指令误报。
- 唯一有效校验：在 `WSL ubuntu24` 内安装 `OpenResty`，用最小 `harness` 包住片段后运行 `openresty -t`。`com_js_signed.conf` 首行 `include` 的是绝对路径，须先做桩。

```sh
sudo apt update && sudo apt install -y openresty

sudo mkdir -p /www/server/nginx/conf
echo 'set $sc_secret "test-secret-1234567890abcdef-test";' | sudo tee /www/server/nginx/conf/com_secret.conf
mkdir -p /tmp/sc_test && cp /mnt/c/repos/scripts/wp/woocommerce/woo_df/sh/nginx_conf/com_js_signed.conf /tmp/sc_test/

cat > /tmp/sc_test/nginx.conf <<'EOF'
events {}
http {
    lua_shared_dict sc_token_store 10m;
    lua_shared_dict sc_bot_cache 10m;
    server {
        listen 8080;
        include /tmp/sc_test/com_js_signed.conf;
    }
}
EOF

openresty -t -p /tmp/sc_test/ -c /tmp/sc_test/nginx.conf
```

- 语义边界：`openresty -t` 只保语法与引用文件存在，不保路由、`Lua` 业务逻辑与挑战行为；`openresty -T` 可输出完整配置辅助排查。检查通过不自动授权重载线上实例。
