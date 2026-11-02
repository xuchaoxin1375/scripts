## nginx 配置入口

本目录维护服务器端 nginx/openresty 配置，覆盖反向代理网关、限流与 JS 挑战。实现与参数以各文档和脚本 `--help` 为准。

| 入口 | 说明 |
|---|---|
| [Nginx 配置总说明](docs/Readme@nginx_conf@Nginx配置总说明文档.md) | 配置结构与文件分工、反代与限流方案、前提与注意事项 |
| [限流配置脚本说明](docs/Readme@Nginx配置修改脚本说明@Nginx分批次施加限流@为新站配置宽松限流.md) | 分批次施加限流、为新站配置宽松限流 |
| [OpenResty JS 挑战](docs/README_js_challenge_signed.md) | 签名 Cookie 的 JS 反爬挑战：部署与运维 |
| [反向代理网关](reverse_proxy/scripts/README.md) | 单机、多出口与多租户反代脚本、模式路由 |
| [反代脚本部署](reverse_proxy/docs/部署@反代方案脚本.md) | 仓库准备、各方案执行、验证与在线执行 |
| [反向代理细节文档](reverse_proxy/docs/) | 各模式目录结构、端口检查、清理与配置生成 |
