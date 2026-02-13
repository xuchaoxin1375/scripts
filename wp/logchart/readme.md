# Log Analyzer Pro（单文件 PHP 日志分析器）

将 `log.php` 与待分析的 `.log` 文件放在同一目录，即可在浏览器中进行大文件日志的可视化分析。

## 背景

服务器上通常部署大量站点，容易遭受攻击或爬虫冲击。直接查看 Nginx 等 Web 服务器生成的日志不够直观，因此本项目提供一个现代化的网页分析器：

- 支持大文件（百万行 / GB 级）日志的流式分析
- 以时间轴图表展示请求趋势、状态码分布、独立 IP 数等
- 便于快速定位异常时间段与异常 IP

## 功能特性

- **自动发现日志文件**
  - 自动扫描当前目录下的 `*.log`

- **快速文件信息扫描（file_info）**
  - 获取文件大小
  - 计算时间跨度（第一条/最后一条有效时间）
  - **预估行数**：通过统计扫描范围内的换行符 `\n` 得到（误差不超过 1 行）
  - 根据时间跨度自动推荐合适的统计间隔
  - **支持按末尾百分比扫描**：当你只关心最近的日志时，可在 UI 选择仅扫描末尾 `20%/10%/5%` 等

- **日志分析（analyze）**
  - 支持按时间范围过滤（开始/结束时间可选）
  - 支持选择统计时间片（10 秒 / 30 秒 / 1 分钟 / 5 分钟等）
  - **支持仅分析末尾百分比**（大幅降低大文件耗时）
  - 汇总维度：
    - 总请求数、独立 IP 数、状态码统计
    - Top IP / Top URL / 域名统计
    - User-Agent 统计（自动识别常见爬虫）

- **图表与交互**
  - 时间线图表：总请求量 + 各状态码曲线（可开关）
  - 独立 IP 数使用右侧 Y 轴（与请求数分开）
  - 点击图表数据点：查看该时间片的 IP 详情（get_ips）
  - 状态码分布饼图
  - 暗色/亮色主题切换
  - 移动端/桌面端布局适配

## 环境要求

- PHP 7.4+（建议 8.x）
- Web Server：Nginx/Apache 均可
- PHP 需启用基础文件函数（`fopen/fseek/fread` 等）

默认已在 `log.php` 中设置：

- `memory_limit = 512M`
- `max_execution_time = 300`

如分析更大文件仍超时，可按需提升执行时间或减少扫描比例/时间范围。

## 部署方式

1. 将 `log.php` 放在一个可通过浏览器访问的目录
2. 将要分析的日志文件（`*.log`）放在同一目录
3. 确保 Web Server 对该目录有读取权限
4. 浏览器访问 `log.php`

## 使用说明

1. **选择日志文件**：下拉框选择当前目录下的 `.log`
   - 切换文件时会自动重置筛选（时间/区间/间隔）并重新计算区间信息，但**不会改变当前的区间选择模式**（百分比/日期时间）。
2. **选择解析方式**：
   - `自动识别（auto）`：根据日志首行自动判断使用哪种解析器
   - `自定义 KV（custom_kv）`：适用于形如 `status=200 bytes=123 [GET] [req = host/path] UA="..."` 的自定义格式（字段顺序可变，可增字段）
   - `Nginx Combined（nginx_combined）`：兼容常见 combined 格式（`"GET /path HTTP/1.1" 200 123 "-" "UA"`）
2. **选择“分析末尾百分比”**（可选）：
   - `100%`：全量扫描
   - `20%/10%/5%`：只分析末尾部分（通常用于“最近几小时/最近一段时间”）
   - 当所选文件较大且你仍处于默认全量区间（`0%~100%`）时，系统会根据“预估行数”自适应计算默认区间，默认分析**末尾约 50 万行**（换算为百分比区间）以提升响应速度。
3. **确认/调整时间范围**：
   - 会根据 `file_info` 的扫描结果自动填充时间范围
   - 如果你手动修改了开始/结束时间，后续切换百分比不会覆盖你的手动输入
4. 点击 **开始分析**
5. 在时间线图表中点击某个点，可打开 IP 详情弹窗查看该时间片的 IP 列表与状态码分布

## 日志格式要求

解析器支持通过 `parse_mode` 切换解析方式（参考 `parseLine()`）：

```text
custom_kv:
IP [time] status=XXX bytes=YYY [METHOD] [req = host/path] UA="..." referer="..." CF-IPCountry: US

nginx_combined:
IP - - [time] "METHOD /path HTTP/1.1" status bytes "referer" "UA"
```

示例：

```text
1.2.3.4 [10/Jan/2026:18:11:46 +0800] status=200 bytes=49464 [GET] [req = example.com/path?a=b] UA="Mozilla/5.0 ..." referer="-" CF-IPCountry: US
```

说明：

- **time**：必须在方括号内，且能被 `strtotime()` 正确解析
- **status**：必须能识别到（`status=200` 或 combined 中的 `200`）
- 其他字段（如 `bytes/UA/referer/CF-IPCountry/XFF`）为可选；缺失不会影响主流程统计

如果你的日志格式不同：

- 推荐先用 `parse_mode=custom_kv` 并在“解析示例（首行）”里确认哪些字段没被识别
- 再按需要调整 `parseLine()` 的解析逻辑

## API 参数（内部接口）

页面通过同一个 `log.php` 提供 JSON API：

- `action=list_logs`
  - 列出目录下所有 `.log`

- `action=file_info&file=xxx.log&range_start=0&range_end=100&parse_mode=auto`
  - **range_start/range_end**：百分比区间（0-100）
  - **parse_mode**：`auto/custom_kv/nginx_combined`
  - 返回：文件大小、时间跨度、预估行数（按换行符统计）、建议 interval、示例行、analysis 元数据

- `action=analyze&file=xxx.log&interval=60&start=...&end=...&range_start=80&range_end=100&parse_mode=custom_kv`
  - **interval**：时间片（秒）
  - **start/end**：可选，格式为 `Y-m-d H:i:s`
  - **range_start/range_end**：百分比区间（0-100）
  - **parse_mode**：`auto/custom_kv/nginx_combined`

- `action=get_ips&file=xxx.log&timestamp=...&interval=...&range_start=...&range_end=...&parse_mode=...`
  - 获取某个时间片的 IP 列表与明细

- `action=parse_preview&file=xxx.log&parse_mode=auto`
  - 返回：首行 raw + parseLine() 的解析结果，用于前端“解析示例（首行）”展示

## 性能建议

- **优先使用 `tail_percent`**：大文件场景建议先用 `20%/10%/5%` 快速定位异常
- **时间范围过滤**：再配合开始/结束时间进一步缩小
- **统计间隔**：跨度越大建议 interval 越大（系统会自动推荐）

## 常见问题（FAQ）

- **预估行数为什么是估算？**
  - `file_info` 为快速响应，采用换行符统计（误差不超过 1 行），适合大文件场景。

- **切换百分比后时间范围不变？**
  - 若你手动编辑过开始/结束时间，系统不会覆盖你的输入。可使用“重置筛选”恢复自动填充。

- **分析很慢/超时？**
  - 优先降低 `tail_percent`（例如 20%）
  - 增大 `interval`
  - 缩小时间范围
  - 适当提高 PHP 的 `max_execution_time`

- **前端界面更新了但看不到新控件/新样式？**
  - 浏览器可能缓存了旧版 `log.php` 输出，建议使用 `Ctrl+F5` 强制刷新

- **统计图表的边缘不准确？**
  - 若日志存在切割/截断（例如 logrotate），或你仅分析了部分百分比区间，图表最前/最后的时间片可能会缺失部分数据，属于预期现象。