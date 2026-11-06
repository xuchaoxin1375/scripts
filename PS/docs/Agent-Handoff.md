# Agent 交接（开发与维护手册）

> 给下一个接手的 agent（或人）看的：怎么做事、怎么验证、哪里埋过雷。
> 用户手册见 `Feature-Guide.md`，模块清单见 `Module-Map.md`，编码铁律见 `Module-Conventions.md`。

## 1. 标准工作流

1. `Read` 看现状（改前必读，edit 工具强制要求）。
2. 大搬迁一律写**搬迁脚本**放 `$env:TEMP\opencode\`（仓库外，不污染 repo），ail：
   行号断言 → 搬运 → 落盘。行号变了就先 abort，绝不硬搬。
3. 跑门禁（§2），不过不落盘、不提交。
4. 更新受影响的 manifest + 相关文档（本目录四份 md 分工见 §5）。
5. 提交信息沿用 `perf:/fix:/chore:` + 中文简述；默认直接提交全部改动，用户手动改动可询问是否单独成一次提交（分多次提交亦可）；推送须明确指示。

## 2. 验证门禁（按顺序跑，全绿才算完）

```powershell
# ① 全模块强制导入（目录名=模块名，CompletionPredictor 是第三方不管）
# ② Test-ModuleManifest 全过
# ③ manifest 导出对账：块注释感知的 ^function 解析 vs 各 psd1 FunctionsToExport，零误差
# ④ init 全链 + prompt + 主题切换冒烟；关键命令 Get-Command 看 Source 归属
# ⑤ 有性能声明必附前后实测数（沙盒要注明；重定向下 PSReadLine 会报两行错，真机没有）
# ⑥ 动过 Agent-Handoff 或归档 → docs/tools/Test-HandoffIndex.ps1 全绿（ID 唯一、索引↔归档一一对应、归属链接可解析）
```

历史用过的脚本名（TEMP 下，用完即走，仓库里不留）：
`verifyAll`（全导入）/`parity4`（manifest 对账）/`verify3`（init+prompt+切换冒烟）/
`timing`（`init -Timing`）/`docfacts`+`docres`（文档断言取数）/`vardump`（变量级对账）。
机器状态类脚本依赖本机安装与运行态，不适合入库；唯一入库的是 [tools/Test-HandoffIndex.ps1](tools/Test-HandoffIndex.ps1)——它只读仓库内容，结果稳定可复现。

## 3. 踩坑清单（索引；正文见归档）

> 本区只放"一句话结论 + 效力 + 位置"，细节在 `archive/agent-handoff-history.md`（ID 即锚点）。
> **编号即 ID，只增不改**——仓库内 `#N` 引用依赖它；日期只作"最后验证"的元数据，不用来分组。
> 效力：`现行` 仍须遵守；`已废止` 已被后续条目推翻（位置列给指针）；`—` 为一次性过程，只供追溯。
> 位置：`主题文档`（规则本体在那里，本行只是检索标签）/`索引`（规则本体就是这一行）/指针（见另一条）。
> **归属文档是唯一真相源**，与本区短句冲突时以归属文档为准。
>
> 新增条目的五步：
> - 查重：`rg` 关键词查本区、`docs/` 与 `archive/`，再看 `git log --oneline -S <关键词>`；命中即合并，不写第二份。
> - 归位：能落主题文档的先落（规则进 `Module-Conventions`，用户行为进 `Feature-Guide`，性能进 `Startup-Optimization`，dll 进 `Live-Versions`，部署进 `Deploy-Guide`，wp 工具进 `wp/…/README`），本区只留检索短句。
> - 取号：ID 取现有最大值 + 1，同时在 `archive/agent-handoff-history.md` 增加 `#### #<ID>` 小节，否则链接断裂。
> - 填表：补效力、位置（具体文档与主题）、最后验证日期；`已废止` 必须写指针。
> - 正文宜短：归档只写结论 + 关键验证（1–3 句），详细过程、日志与命令输出留在提交信息；不写逐日流水账，归档只作"可链接的考古"，不是第二份手册。
>
> 改动本区后跑 [tools/Test-HandoffIndex.ps1](tools/Test-HandoffIndex.ps1)（仓库根执行 `pwsh -NoProfile -File PS/docs/tools/Test-HandoffIndex.ps1`，5.1 把 `pwsh` 换成 `powershell`），全绿再提交。

### 现行结论

| ID | 结论（一句话） | 效力 | 位置（归属） | 最后验证 |
|---|---|---|---|---|
| [#1](archive/agent-handoff-history.md#1) | 变量名大小写不敏感 | 现行 | 主题文档：[Module-Conventions.md](Module-Conventions.md)「命名」 | — |
| [#2](archive/agent-handoff-history.md#2) | `@( (a,b) )` 单元素数组自动解包 | 现行 | 索引 | — |
| [#3](archive/agent-handoff-history.md#3) | `return @()`/`return $array` 解包 | 现行 | 索引 | — |
| [#4](archive/agent-handoff-history.md#4) | 管道里 `$Matches` 跨作用域失效 | 现行 | 索引 | — |
| [#5](archive/agent-handoff-history.md#5) | 换行符：LF/CRLF 默认忽略差异，仅 `.sh` 用 LF、`.cmd`/`.bat` 用 CRLF | 现行 | 主题文档：[AGENTS.md](../../AGENTS.md)「换行」 | — |
| [#6](archive/agent-handoff-history.md#6) | 成功流泄漏 | 现行 | 主题文档：[Module-Conventions.md](Module-Conventions.md)「输出流规范」 | — |
| [#7](archive/agent-handoff-history.md#7) | 日志行序不可信 | 现行 | 索引 | — |
| [#8](archive/agent-handoff-history.md#8) | bash 工具引号地狱：复杂命令写 `.ps1` 再 `-File` | 现行 | 主题文档：[AGENTS.md](../../AGENTS.md)「命令执行」 | — |
| [#9](archive/agent-handoff-history.md#9) | 模块作用域：跨模块需 `$global:` 前缀 | 现行 | 索引 | 2026-09-20 |
| [#10](archive/agent-handoff-history.md#10) | manifest 是真相源 | 现行 | 主题文档：[Module-Conventions.md](Module-Conventions.md)「manifest 再生成规则」 | — |
| [#11](archive/agent-handoff-history.md#11) | 重定向 vs 交互是两种宇宙 | 现行 | 索引 | — |
| [#12](archive/agent-handoff-history.md#12) | restricted characters 警告 = 双横线 | 现行 | 主题文档：[Module-Conventions.md](Module-Conventions.md)「命名」 | 2026-09-20 |
| [#13](archive/agent-handoff-history.md#13) | 提交看第二列 | 现行 | 主题文档：[AGENTS.md](../../AGENTS.md)「提交前检查」 | 2026-09-20 |
| [#14](archive/agent-handoff-history.md#14) | edit 工具可能整文件改写换行 | 现行 | 主题文档：[AGENTS.md](../../AGENTS.md)「换行」 | — |
| [#15](archive/agent-handoff-history.md#15) | `ipmof\|iex` 为什么要管道 | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「ipmof\|iex」 | 2026-09-20 |
| [#16](archive/agent-handoff-history.md#16) | `ipmox` 选项（新函数两步并一步） | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「命令表」 | — |
| [#17](archive/agent-handoff-history.md#17) | `Deploy-CompletionStack`（新机一键补全栈） | 现行 | 主题文档：[Deploy-Guide.md](Deploy-Guide.md)「补全栈」 | — |
| [#19](archive/agent-handoff-history.md#19) | 国内网络：gitee→github+加速 | 现行 | 主题文档：[Deploy-Guide.md](Deploy-Guide.md)「镜像」 | 2026-09-21 |
| [#21](archive/agent-handoff-history.md#21) | dll 外置决策 | 现行 | 主题文档：[Live-Versions.md](Live-Versions.md)「活件结构」 | 2026-09-21 |
| [#23](archive/agent-handoff-history.md#23) | 守护进程不加载 predictor + `-Force` | 现行 | 主题文档：[Live-Versions.md](Live-Versions.md)「故障」 | 2026-09-21 |
| [#24](archive/agent-handoff-history.md#24) | 活件同步手动化 | 现行 | 主题文档：[Deploy-Guide.md](Deploy-Guide.md)「更新流程」 | 2026-09-21 |
| [#25](archive/agent-handoff-history.md#25) | 历史瘦身 + `doctor` | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「doctor」 | 2026-09-21 |
| [#26](archive/agent-handoff-history.md#26) | 用户配置文件 | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「配置」 | 2026-09-21 |
| [#28](archive/agent-handoff-history.md#28) | `Remove-Module` 后文件仍被锁（证伪"无锁天生"） | 现行 | 主题文档：[Live-Versions.md](Live-Versions.md)「故障」 | 2026-09-21 |
| [#29](archive/agent-handoff-history.md#29) | 并排版本活件 | 现行 | 主题文档：[Live-Versions.md](Live-Versions.md)「并排版本设计专章」 | 2026-09-21 |
| [#30](archive/agent-handoff-history.md#30) | 编年条目只作留档，现行口径以主题文档为准 | 现行 | 索引（本文件） | 2026-09-21 |
| [#32](archive/agent-handoff-history.md#32) | 独立 Tab 插件 + 插件启停 | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「补全」 | 2026-09-21 |
| [#34](archive/agent-handoff-history.md#34) | 5.1 兼容 B 档 | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「5.1 兼容」 | 2026-09-21 |
| [#35](archive/agent-handoff-history.md#35) | 5.1 真机抓到的四个坑 | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「5.1 兼容」 | 2026-09-21 |
| [#37](archive/agent-handoff-history.md#37) | 5.1 prompt 全对齐 + 免手动 | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「5.1 兼容」 | 2026-09-21 |
| [#38](archive/agent-handoff-history.md#38) | 查询命令 5.1 可用化（`Get-ModuleByCxxu` 在 Basic 模块） | 现行 | 主题文档：[Module-Map.md](Module-Map.md) | 2026-09-21 |
| [#41](archive/agent-handoff-history.md#41) | 5.1 乱码归因 | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「5.1 兼容」 | 2026-09-21 |
| [#46](archive/agent-handoff-history.md#46) | psd1 中文引号坑 | 现行 | 索引 | 2026-09-22 |
| [#50](archive/agent-handoff-history.md#50) | 酌情 5.1 第一批：`PsDebug`/`PsEnv`/`Shortcut`/`PathProcess`/`Hardware`/`Proxy` 降 B 档 | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「5.1 兼容」 | 2026-09-22 |
| [#51](archive/agent-handoff-history.md#51) | 酌情 5.1 第二批：17 个解析零错误模块降 B 档 | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「5.1 兼容」 | 2026-09-22 |
| [#52](archive/agent-handoff-history.md#52) | 酌情 5.1 第三批：`Pwsh`/`Deploy`/`Link`/`openApps` 降 B 档，BOM 归一重扫先行 | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「5.1 兼容」 | 2026-09-22 |
| [#54](archive/agent-handoff-history.md#54) | 裸 `$IsWindows` 探针门禁 | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「5.1 兼容」 | 2026-09-22 |
| [#55](archive/agent-handoff-history.md#55) | 酌情 5.1 第四批 + `Json` 读写根治 | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「5.1 兼容」 | 2026-09-22 |
| [#56](archive/agent-handoff-history.md#56) | 酌情 5.1 第五批：`Git`/`Scoop`/`SSH`，B 档 47 | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「5.1 兼容」 | 2026-09-22 |
| [#57](archive/agent-handoff-history.md#57) | 酌情 5.1 第六批 + 第七批（B 档 47→62） | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「5.1 兼容」 | 2026-09-22 |
| [#58](archive/agent-handoff-history.md#58) | 跨设备编辑与 BOM | 现行 | 主题文档：[Module-Conventions.md](Module-Conventions.md)「跨设备编辑与 BOM」 | 2026-09-22 |
| [#59](archive/agent-handoff-history.md#59) | 5.1 老 conhost 下 VT 序列原文输出 | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「5.1 兼容」 | 2026-09-22 |
| [#60](archive/agent-handoff-history.md#60) | `` `e `` 是 6.0+ 转义，5.1 下退化成字母 `e` | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「5.1 兼容」 | 2026-09-22 |
| [#61](archive/agent-handoff-history.md#61) | 首屏 1~2 秒打字滞后 | 现行 | 主题文档：[Startup-Optimization.md](Startup-Optimization.md)「启动基线」 | 2026-09-22 |
| [#62](archive/agent-handoff-history.md#62) | 兼容性文档说清楚了吗/能否命令检查 | 现行 | 索引 | 2026-09-22 |
| [#63](archive/agent-handoff-history.md#63) | 分片回滚：常驻 OnIdle 订阅是回归 | 现行 | 主题文档：[Startup-Optimization.md](Startup-Optimization.md)「启动基线」 | 2026-09-22 |
| [#64](archive/agent-handoff-history.md#64) | 启动优化：手势按需（优化 3） | 现行 | 主题文档：[Startup-Optimization.md](Startup-Optimization.md)「启动基线」 | 2026-09-22 |
| [#66](archive/agent-handoff-history.md#66) | 时效性修复实录 | 现行 | 主题文档：[Deploy-Guide.md](Deploy-Guide.md)「时效性」 | 2026-09-24 |
| [#67](archive/agent-handoff-history.md#67) | 轻量部署 + 去硬编码 | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「5.1 兼容」 | 2026-09-24 |
| [#68](archive/agent-handoff-history.md#68) | 一键部署 `-Dev` 模式 | 现行 | 主题文档：[Deploy-Guide.md](Deploy-Guide.md)「开发模式」 | 2026-09-24 |
| [#71](archive/agent-handoff-history.md#71) | readiness macOS 适配 + 自编译 dll | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「非 Windows」 | 2026-09-25 |
| [#73](archive/agent-handoff-history.md#73) | 文档风格偏好入治理 | 现行 | 主题文档：[Module-Conventions.md](Module-Conventions.md)「文档语言」 | 2026-09-25 |
| [#74](archive/agent-handoff-history.md#74) | readme.md 正式改写 + 根 AGENTS.md | 现行 | 主题文档：[AGENTS.md](../../AGENTS.md)「仓库入口」 | 2026-09-25 |
| [#75](archive/agent-handoff-history.md#75) | `init -Force` 刷不动变量 conf | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「init」 | 2026-10-02 |
| [#76](archive/agent-handoff-history.md#76) | wp 域名工具：改调新 CF 工具（旧 cf_config_api.py 退役） | 现行 | 主题文档：[cf_api/ReadMe.md](../../wp/woocommerce/woo_df/pys/cf_api/ReadMe.md)「功能概览」 | 2026-10-02 |
| [#78](archive/agent-handoff-history.md#78) | wp 域名工具：DNS 记录幂等与防劈叉 | 现行 | 主题文档：[cf_api/ReadMe.md](../../wp/woocommerce/woo_df/pys/cf_api/ReadMe.md)「DNS 记录幂等与防劈叉」 | 2026-10-02 |
| [#79](archive/agent-handoff-history.md#79) | wp 域名工具：`--allow-multi-value`（接 #78） | 现行 | 主题文档：[cf_api/ReadMe.md](../../wp/woocommerce/woo_df/pys/cf_api/ReadMe.md)「DNS 记录幂等与防劈叉」 | 2026-10-02 |
| [#80](archive/agent-handoff-history.md#80) | wp 域名工具：domain_fix 对照 Deploy-WpSitesOnline | 现行 | 主题文档：[domain_fix/README.md](../../wp/woocommerce/woo_df/pys/domain_fix/README.md)「与 Deploy-WpSitesOnline 流程的对照」 | 2026-10-02 |
| [#81](archive/agent-handoff-history.md#81) | wp 域名工具：翻转激活等待与 NS 默认值 | 现行 | 主题文档：[domain_fix/README.md](../../wp/woocommerce/woo_df/pys/domain_fix/README.md)「修复步骤与开关」 | 2026-10-02 |
| [#82](archive/agent-handoff-history.md#82) | wp 域名工具：邮箱步骤加 active 门控 | 现行 | 主题文档：[domain_fix/README.md](../../wp/woocommerce/woo_df/pys/domain_fix/README.md)「转发邮箱：激活前能否设置，激活后能否生效」 | 2026-10-02 |
| [#83](archive/agent-handoff-history.md#83) | wp 域名工具：工作流程 mermaid 与邮箱时机落文档 | 现行 | 主题文档：[domain_fix/README.md](../../wp/woocommerce/woo_df/pys/domain_fix/README.md)「全流程示意」 | 2026-10-02 |
| [#85](archive/agent-handoff-history.md#85) | wp 域名工具：批量回访一次跑完 | 现行 | 主题文档：[domain_fix/README.md](../../wp/woocommerce/woo_df/pys/domain_fix/README.md)「续跑 / 补配必须用 --missing-csv 喂回」 | 2026-10-02 |
| [#86](archive/agent-handoff-history.md#86) | wp 域名工具：邮箱地址列表形态兼容 | 现行 | 主题文档：[cf_api/ReadMe.md](../../wp/woocommerce/woo_df/pys/cf_api/ReadMe.md)「域名激活、邮箱转发与设置（库能力）」 | 2026-10-02 |
| [#87](archive/agent-handoff-history.md#87) | wp 域名工具：README 第三节重排为推荐流程 | 现行 | 主题文档：[domain_fix/README.md](../../wp/woocommerce/woo_df/pys/domain_fix/README.md)「推荐运行流程」 | 2026-10-02 |
| [#88](archive/agent-handoff-history.md#88) | wp 域名工具：改 NS 先查后改、一致跳过 | 现行 | 主题文档：[domain_fix/README.md](../../wp/woocommerce/woo_df/pys/domain_fix/README.md)「修复步骤与开关」 | 2026-10-02 |
| [#89](archive/agent-handoff-history.md#89) | wp 域名工具：版本时间串与详细输出 | 现行 | 主题文档：[domain_fix/README.md](../../wp/woocommerce/woo_df/pys/domain_fix/README.md)「结果判读」 | 2026-10-02 |
| [#90](archive/agent-handoff-history.md#90) | wp 域名工具：引入 logging | 现行 | 主题文档：[cf_api/ReadMe.md](../../wp/woocommerce/woo_df/pys/cf_api/ReadMe.md)「日志与审计」 | 2026-10-02 |
| [#91](archive/agent-handoff-history.md#91) | wp 域名工具：控制台时间戳与记录形状归一 | 现行 | 主题文档：[cf_api/ReadMe.md](../../wp/woocommerce/woo_df/pys/cf_api/ReadMe.md)「日志与审计」 | 2026-10-02 |
| [#93](archive/agent-handoff-history.md#93) | wp 域名工具：`--activation` 默认开启 | 现行 | 主题文档：[domain_fix/README.md](../../wp/woocommerce/woo_df/pys/domain_fix/README.md)「修复步骤与开关」 | 2026-10-02 |
| [#94](archive/agent-handoff-history.md#94) | wp 域名工具：逐域输出行详解落文档 | 现行 | 主题文档：[domain_fix/README.md](../../wp/woocommerce/woo_df/pys/domain_fix/README.md)「控制台逐域行解读（示例）」 | 2026-10-02 |
| [#95](archive/agent-handoff-history.md#95) | wp 域名工具：并发与限流审计 | 现行 | 主题文档：[cf_api/ReadMe.md](../../wp/woocommerce/woo_df/pys/cf_api/ReadMe.md)「限流模式」 | 2026-10-02 |
| [#96](archive/agent-handoff-history.md#96) | wp 域名工具：默认 `--apply`、`--dry-run` 预览 | 现行 | 主题文档：[domain_fix/README.md](../../wp/woocommerce/woo_df/pys/domain_fix/README.md)「修复步骤与开关」 | 2026-10-02 |
| [#97](archive/agent-handoff-history.md#97) | wp 域名工具：并行日志直观化 | 现行 | 主题文档：[cf_api/ReadMe.md](../../wp/woocommerce/woo_df/pys/cf_api/ReadMe.md)「处理流程示意图」 | 2026-10-02 |
| [#98](archive/agent-handoff-history.md#98) | wp 域名工具：并发只论证了安全、没回答速度；密钥明文打印 | 现行 | 主题文档：[cf_api/ReadMe.md](../../wp/woocommerce/woo_df/pys/cf_api/ReadMe.md)「敏感信息处理」 | 2026-10-02 |
| [#99](archive/agent-handoff-history.md#99) | wp 域名工具：提速到约 3 记录/秒 + Ctrl+C 优雅退出 | 现行 | 主题文档：[cf_api/ReadMe.md](../../wp/woocommerce/woo_df/pys/cf_api/ReadMe.md)「Ctrl+C 中断多线程」 | 2026-10-02 |
| [#100](archive/agent-handoff-history.md#100) | wp 域名工具：开始行改由干活线程打印 | 现行 | 主题文档：[cf_api/ReadMe.md](../../wp/woocommerce/woo_df/pys/cf_api/ReadMe.md)「日志与审计」 | 2026-10-02 |
| [#101](archive/agent-handoff-history.md#101) | `init -Force` 真重载变量 conf | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「init」 | 2026-10-03 |
| [#102](archive/agent-handoff-history.md#102) | CxxuTab 改默认关（显式开启才启用） | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「补全」 | 2026-10-17 |
| [#103](archive/agent-handoff-history.md#103) | Deploy-CronFile：Windows 版 deploy.sh 等价物 | 现行 | 主题文档：[update-cron/README.md](../../wp/woocommerce/woo_df/sh/update-cron/README.md)「功能」 | 2026-10-28 |
| [#104](archive/agent-handoff-history.md#104) | 移除"同名脚本即重复"的阻断式预检（只提示，可覆盖） | 现行 | 主题文档：[AGENTS.md](../../AGENTS.md)「批量覆盖与下发」 | 2026-10-29 |
| [#105](archive/agent-handoff-history.md#105) | Deploy-CronFile：只读阶段并发 + `-SkipPrecheck` | 现行 | 主题文档：[update-cron/README.md](../../wp/woocommerce/woo_df/sh/update-cron/README.md)「只读预检与并发」 | 2026-10-29 |
| [#106](archive/agent-handoff-history.md#106) | `irm\|iex` 前必须裁 `U+FEFF`；落盘用 `-OutFile` | 现行 | 主题文档：[Module-Conventions.md](Module-Conventions.md)「Invoke-Expression 使用规范」 | 2026-11-06 |
| [#107](archive/agent-handoff-history.md#107) | `PwshVar/confs/*.conf` 禁三元（5.1 逐行 `iex` 报 `Unexpected token '?'`），条件赋值用 `if/else` | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「5.1 兼容」 | 2026-11-06 |
| [#108](archive/agent-handoff-history.md#108) | 5.1 重定义内置别名（`rm`/`r`/`ps`/`h`）必须带 `-Option AllScope`，否则报错且别名静默失效 | 现行 | 主题文档：[Feature-Guide.md](Feature-Guide.md)「5.1 兼容」 | 2026-11-06 |
| [#109](archive/agent-handoff-history.md#109) | 一键部署 5.1 修复：镜像克隆/失败回退、默认不装 pwsh、镜像探测并发 | 现行 | 主题文档：[Deploy-Guide.md](Deploy-Guide.md)「镜像」 | 2026-11-06 |
| [#110](archive/agent-handoff-history.md#110) | 一键部署本地沙箱：临时目录验证、不碰真实环境、可离线回归 | 现行 | 主题文档：[PS/Deploy/readme.md](../Deploy/readme.md)「本地调试（沙箱）」 | 2026-11-06 |

批次线索：模块拆分是 `#36`、`#42`–`#49` 的一串切片（一次性过程，收在下面的折叠区，其中 `#46` 是单列规则）；5.1 降档是 `#50`–`#57` 的连续批次，结论统一归到 [Feature-Guide.md](Feature-Guide.md)「5.1 兼容」，检索时按范围看即可。

### 已废止与一次性过程

<details>
<summary>展开（只供追溯，不构成现行约束）</summary>

| ID | 结论（一句话） | 效力 | 位置（归属） | 最后验证 |
|---|---|---|---|---|
| [#18](archive/agent-handoff-history.md#18) | `Close-OtherPwsh` 已退役（命令已不存在，见 #22） | 已废止 | → #22 | — |
| [#20](archive/agent-handoff-history.md#20) | （条目已移除，见 #31） | 已废止 | → #31 | — |
| [#22](archive/agent-handoff-history.md#22) | 退役记录：#21 之前的锁内 machinery（已废弃） | — | 索引 | — |
| [#27](archive/agent-handoff-history.md#27) | 自锁实测（假设已被 #29 推翻） | 已废止 | → #29 | 2026-09-21 |
| [#31](archive/agent-handoff-history.md#31) | 退役 `Update-CxxuPsModules` | — | 索引 | 2026-09-21 |
| [#33](archive/agent-handoff-history.md#33) | Tab 发版实录 | — | 索引 | 2026-09-21 |
| [#36](archive/agent-handoff-history.md#36) | 一次性搬迁：拆分 Basic/Pwsh | — | 索引 | 2026-09-21 |
| [#39](archive/agent-handoff-history.md#39) | 文档 BOM 方案推翻（结论以 #58 为准） | 已废止 | → #58 | 2026-09-21 |
| [#42](archive/agent-handoff-history.md#42) | 一次性搬迁：大模块拆分开工 | — | 索引 | 2026-09-22 |
| [#43](archive/agent-handoff-history.md#43) | 一次性搬迁：模块拆分第二刀 | — | 索引 | 2026-09-22 |
| [#44](archive/agent-handoff-history.md#44) | 一次性搬迁：模块拆分第三刀 | — | 索引 | 2026-09-22 |
| [#45](archive/agent-handoff-history.md#45) | 一次性搬迁：模块拆分第四刀 | — | 索引 | 2026-09-22 |
| [#47](archive/agent-handoff-history.md#47) | 一次性搬迁：模块拆分第五刀 | — | 索引 | 2026-09-22 |
| [#48](archive/agent-handoff-history.md#48) | 一次性搬迁：模块拆分第六刀 | — | 索引 | 2026-09-22 |
| [#49](archive/agent-handoff-history.md#49) | 一次性搬迁：模块拆分第七刀 | — | 索引 | 2026-09-22 |
| [#53](archive/agent-handoff-history.md#53) | 一次性事故：Sync-ModuleManifest 双重编码 | — | 索引 | 2026-09-22 |
| [#65](archive/agent-handoff-history.md#65) | 一次性盘点：时效性清查 | — | 索引 | 2026-09-24 |
| [#69](archive/agent-handoff-history.md#69) | 未决（2026-09-24 提出）：防泄密盘点，未再推进 | — | 索引 | 2026-09-24 |
| [#70](archive/agent-handoff-history.md#70) | 一次性补齐：仓库入口 | — | 索引 | 2026-09-24 |
| [#72](archive/agent-handoff-history.md#72) | 一次性清理：删 readme_zh.md 与 Linux 链路 | — | 索引 | 2026-09-25 |
| [#77](archive/agent-handoff-history.md#77) | wp 域名工具：淘汰 flarectl | — | 索引 | 2026-10-02 |
| [#84](archive/agent-handoff-history.md#84) | wp 域名工具：旧脚本"不等激活配邮箱"考证 | — | 索引 | 2026-10-02 |
| [#92](archive/agent-handoff-history.md#92) | wp 域名工具：调错端点实锤并修正 | — | 索引 | 2026-10-02 |

</details>

## 4. 环境事实（这台机器，2026-09 实测）

- pwsh 7.5，`$HOME=C:\Users\Administrator`，`$env:PSModulePath` 首位是
  `Documents\PowerShell\Modules`，`C:/repos/scripts/PS` 在第 5 位。
- 四级 profile：`AllUsers*` 不存在；`CurrentUserAllHosts` 只有 conda 块；
  `CurrentUserCurrentHost` 是 `init` + 注释掉的 argc/fnm。
- WT 线上配置无 pwsh7 自定义 profile；仓库 `Config/wtConf*.json` 仅供参考，
  部分 tab 用 `pwsh -noe -c p`（外层 profile 跑完 `init` 后 `p` 会 no-op，别被两层吓到）。
- 常驻进程：`Start-TimeAnnouncer`、`Update-NetConnectionInfo` 守护进程、
  用户开 tab 留下的 `pwsh -noe -c p/init` 瞬态进程——测启动耗时前先看一眼，
  别把别人的常驻进程当自己的 bug。
- `~/Data.json` 是运行态文件（IpPrompt/ConnectionName/内存缓存），别提交；
  `~/.conda_hook_cache.ps1`、`$TEMP/CxxuPwshVar_*.cache.ps1` 同理。

### WSL 直接访问本仓库（2026-09-20 与 WSL git 2.54 对测，结论：能用，但三条红线）

- **能直接用**：同一 `.git` 目录，`git -c core.quotepath=false --git-dir=/mnt/c/repos/scripts/.git
  --work-tree=/mnt/c/repos/scripts status` 与 Windows 侧已做到逐行一致（`PS/` 100%，
  含 5 个 `wp/` 真修改）。先天已有 `core.filemode=false` + `ignorecase=true`，不用动。
- **红线 1——不要动仓库本地 `core.autocrlf=false`**（`.git/config`，两侧共享，一处写两处生效；
  WSL 全局保持默认即可，千万别设 `true`）。血泪史：Windows 全局曾是 `true`，
  `git add` 把 CRLF 归一化成 LF 存进 index，而工作区字节从没变过——Windows 双向过同一滤镜
  所以显示干净，WSL 做原始比较当场现形（`A` 变 `AM`）。找这类病用 blob 哈希数学：
  `blob(raw)` vs `git rev-parse :path`，对不上就是 index 被污染。
- **红线 2——racy-git 缓存会瞎**：只改配置/属性不动文件时，mtime/size 全一样，
  `git add` 会信 stat 跳过重哈希（配置变了但 stat 没变）。强制重哈希：`touch` 文件再 `add`
 （或 `git add --renormalize`，但注意它会把真改动也顺手暂存）。修完必用 `blob()` 验 index。
- **红线 3——暂存范围只限本次任务文件**：WSL 可能比 Windows 更早看到 ` M`
  （DrvFs 的 stat 视角不同，会逼 git 重哈希说真话；Windows 的陈旧 stat 缓存过期后也会显示）。
  如那 5 个 conf/sql（用户编辑器翻成 CRLF 相对 LF 历史是真修改）：**别顺手 add**，
  更别 `--renormalize` 整个仓库——只暂存本次任务涉及的文件。
- 其余：换机器若报 `detected dubious ownership`，在 WSL 里跑
  `git config --global --add safe.directory '/mnt/c/repos/scripts'`（注意是 WSL 路径格式）；
  两侧不要同时跑 git（抢 `index.lock`）；WSL 下 push 要单独配 credential（远端是 gitee+github
  双 pushurl）；`/mnt/c` IO 慢，`status` 耗时长正常；`wsl` 偶发
  `Failed to start the systemd user session` 不影响 git 命令本身，无视。
- WSL 里新建/改文件同样守 `Module-Conventions.md §8`（EOL 默认忽略，仅 `.sh` 用 LF、
  `.cmd`/`.bat` 用 CRLF）；需要排查 index 污染时再看 `git ls-files --eol`、
  `git diff --ignore-cr-at-eol --stat` 与 blob 哈希对账。

## 5. 文档分工（改代码必看要不要同步）

| 文档 | 内容 | 什么时候更新 |
|---|---|---|
| `Agent-Handoff.md` | 交接手册 + 踩坑索引（现行结论主表 + 折叠的已废止/一次性过程），正文在 `archive/agent-handoff-history.md` | 新增踩坑、效力或位置变更、结论归位 |
| `Module-Map.md` | 67 模块画像、热路径链、数据流 | 增删模块/搬迁/热路径变化 |
| `Deploy-Guide.md` | 新机部署：checklist 命令 + 分步指南 + 多设备差异 | 新机器部署/增删部署步骤 |
| `Live-Versions.md` | 并排版本活件设计专章：结构、指针协议、流程、故障 | 动 dll/同步/加载 |
| `Feature-Guide.md` | 用户手册：入口、主题、开机、FAQ | 用户可见行为变化 |
| `Module-Conventions.md` | 编码铁律、已接受偏差清单 | 立新规矩/新例外 |
| `Startup-Optimization.md` | 性能基线、搬迁史、TODO | 每次性能改动（附实测数） |

## 6. 未决事项（2026-09-20 更新：前三项已解决）

- ~~`Mock`、`Test`（whois 名实不符）、`CommentBasedHelpDocumentExamples`：删还是留~~
  → 用户拍板：全保留做特殊用途；`Test`→`Whois`、`CommentBasedHelpDocumentExamples`→`HelpExamples`
  已改名（函数名/GUID 未动），`Mock` 不动。
- `Deprecated` 模块：用户拍板删除（转正后仍无存在必要，零调用已核实），`git rm` 整目录，
  历史可追溯，对照表见 `Startup-Optimization.md §16`（历史记录）。
- ~~`VarSet1.conf` 换行抖动~~ → 查清是 `.gitattributes` 的 `text` 归一化假 diff，
  不是用户编辑器问题；已修（见 `Startup-Optimization.md §13`），文件本身零改动。
- `Tools` 剩 1078 行：继续原子化还是维持 misc 定位，待定。
- `Deploy.psm1` 2653 行：冷路径，暂不动。
