# WebUI 后续优化清单（OPT）

来源：自动化验收与后端审计中发现、但不挡本轮门禁的事项。每项均有证据链，
实施前由用户定优先级；本文件为唯一记录位置，不散记。

| 编号 | 等级 | 事项 | 证据 | 状态 |
|---|---|---|---|---|
| OPT-1 | P0 | 弹窗截图后复断言仍可见（门禁证据有效性） | 门禁 `shot-1440-light-选择域名.png` 缺弹窗但判 PASS；探针复现弹窗正常（bbox 720×380 可见，零控制台错误），属证据链缺口 | DONE（`accept.py#shot_dialog_ok`；复跑截图已含弹窗，门禁过） |
| OPT-2 | P1 | `jobs.py:88,93,106,167` 静默吞异常：日志补救写失败不可见 | `webui/backend/jobs.py:88,93,106,167` 四处 `except Exception: pass`（日志扇出守卫按设计保留，历史落盘失败转 stderr 上报） | DONE（`jobs.py:168` 打 `[history-upsert-failed]`，门禁扫描可收敛） |
| OPT-3 | P1 | `loadJob` 轮询吞错：任务跟踪页请求失败用户无感知 | `webui/frontend/src/App.jsx:283`（`catch {}`） | DONE（连续 2 次失败亮错误条＋重试） |
| OPT-4 | P2 | 后端错误转中文可操作提示：无效 Token 等情形给出“检查 API Token 权限”指引，而非仅原始 `HTTP 400 code 6003` | `shot-1440-light-submitted.png`（verdict 展示原始引擎错误串） | DONE（任务页口令失效 hint） |
| OPT-6 | P1 | 刷新按钮无上下文时静默空转（点击无请求、无反馈） | 点击横扫 v2：`刷新` DEAD（`loadRecords` 在无账号/域名时直接返回）；`App.jsx:464` | DONE（未选齐时禁用＋title 提示） |
| OPT-7 | P2 | 下一页在空列表下仍可点（翻到空页，无意义但无害） | 点击横扫 v2：`下一页` EFFECT（空翻页） | PENDING（建议：按 `total` 禁用越界翻页） |
| OPT-10 | P1 | 现网观测手段：门禁只在合成实例自证，看不见用户现网日志（用户 `no such column` 现网报障的教训） | 本轮对话：合成全绿 vs 现网 500 | DONE（`accept.py --base` 现网只读模式：无 UI 提交，服务端日志记 note；4/4 ok 验证过） |
| OPT-8 | P0 | 历史/审计按钮无 catch 死按钮＋后端 history/audit 无 502 包裹（用户报障：点击没反应、后台一堆错误） | `App.jsx:397-398,561-562`（裸 `then`）；`app.py:511-517`（裸 `db.list_*`） | DONE（`openList` 统一入口＋顶栏错误条；后端 502 包裹；路由拦截失败路径断言） |
| OPT-9 | P0 | 旧库 schema 漂移：`audit_log` 无 `kind` 列致接口 500（用户 Traceback：`no such column: kind`） | 用户 Traceback（`db.py:99 list_audit`）；复现脚本同字报错（含 `jobs_history` 缺 `accounts`） | DONE（`db.py#_ensure_columns` 轻量迁移＋`tests/test_db_migrate.py`；旧数据保留） |
| OPT-5 | P2 | 选择域名门禁截图缺弹窗根因：功能经探针证实正常，门禁截图缺失原因待查；`shot_dialog_ok` 落地后若复现即 FAIL，不再静默 | 本轮探针记录（`cf_probe_full.png` 有弹窗、`cf_accept` 门禁截图无） | PENDING（复跑即验证） |
| OPT-11 | P2 | 记录表列宽拖拽（8px 热区/键盘/持久化）：列少且固定，ROI 低，本轮不做 | admin-console-design `tables.md` 列宽节；重设计方案§6 | PENDING（待用户定优先级） |
| OPT-12 | P2 | 记录表服务端排序：排序语义归后端（分页下前端排序失真），需后端接口支持，本轮不做 | 重设计方案§6；`accept.py` 仅账号表（内存数据）有排序断言 | PENDING（本轮仅当前页客户端三态排序＋aria-sort；待用户定优先级） |
| OPT-13 | — | 悬浮批量条：不做。单页三面板共存，fixed 条与 panel-foot 打架；批量语义由 panel-foot 承担 | 重设计方案§6 | 不做（方案决策） |
| OPT-14 | P2 | verdict 文案 CLI 残留：Web 失败任务 verdict 显示“建议下次加 --failed-output …”，Web 应指引“下载失败清单”按钮 | `shot_flow.png`（job-0001 failed verdict 末行） | PENDING（`build_final_verdict` 加 `web_hint` 参数或前端改写末行） |
| OPT-15 | P2 | 失败终态结果表空态文案误导：“暂无明细（进行中或全部跳过）”在 failed 终态下仍显示“进行中” | `shot_flow.png`（failed 任务结果表） | PENDING（按终态区分空态文案） |
| OPT-15 | P2 | 总览域名总数：当前仅当前浏览域名记录数，全账号 zone 聚合需多次分页调用，本轮不做 | 重设计 T20；总览 Stat 用当前域记录数代替 | PENDING（待用户定优先级） |
| OPT-16 | P1 | 390 窄屏工具栏收纳：筛选/显示/导出/导入曾被 `@container` 隐藏规则吞掉（只剩更多＋添加），已修为自然换行常驻 | 截图目检 `shot-390-light-browse.png`（修前） | DONE（删 `toolbar .secondary` 隐藏规则；复跑门禁验证） |
| OPT-14 | — | 原生 dialog：不做。div 方案门禁深度依赖（inert/焦点断言），仅补 Toast | 重设计方案§6 | 不做（方案决策） |
