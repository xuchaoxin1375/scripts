# orders3.php 说明

`orders3.php` 是支付监控中心的主入口页面，负责加载统计数据、渲染分析页面与原始日志视图，并输出图表与列表等 UI。

## 功能概览

- 权限校验与基础配置
- 日志解析与统计汇总（订单、成功率、客单价、访客数等）
- 图表渲染（综合走势、人员表现）及交互控制
- 订单列表与筛选（状态、排序、域名、金额非 0 等）
- 导出 CSV 与局部渲染（按需返回片段）

## 主要依赖

- `/order/config.php`：全局配置与版本号
- `/order/utils.php`：通用工具函数
- `/order/csv.php`：CSV 导出
- `/order/stats.php`：统计计算
- `/order/render.php`：分析页渲染
- `/order/list.php`：订单列表渲染
- `/order/parser.php`：日志解析与统计
- `/order/auth.php`：权限校验
- `/order/range.php`：日期范围统计
- `/order/export.php`：导出逻辑
- `/order/controller.php`：请求入口控制
- Chart.js：用于图表展示（CDN 引入）
- `/order/assets/orders3.css.php`：页面样式

## 常用配置位置（最常改的地方）

- **版本号（用于页面展示与 CSS 缓存参数）**
  - 文件：`/order/config.php`
  - 变量：`$APP_VERSION`
  - 用途：
    - `orders3.php` 页面标题与页头展示
    - `orders3.css.php?v=...` 用于强制刷新样式缓存

- **访问 Token（访问鉴权）**
  - 文件：`/order/config.php`
  - 变量：`$access_token`
  - 校验逻辑：`/order/auth.php` 中 `orders3_require_token()`
  - 访问方式：所有入口请求都需要携带 `?token=...`

- **页面标题**
  - 文件：`/orders3.php`
  - 位置：`<title>PP ORDERS <?= htmlspecialchars($APP_VERSION) ?></title>`

## 入口参数（GET）

- `token`：访问令牌（必填）
- `date`：日期（`YYYY-MM-DD`）
- `mode`：`analysis` | `raw`
- `status`：订单状态过滤
- `owner`：所属人过滤
- `sort`：排序方式
- `csv_file`：CSV 选择（域名归属映射源；影响人员汇总/人员曲线/多日统计的 people_usd 归属）
- `list_view`：`card` | `table`
- `amount_nonzero`：金额非 0 过滤（1/0）
- `pending_as_success`：待定计入成功（1/0）
- `cluster_prefix_trim2`：合并订单前缀（去除后两位）（1/0）
- `group_by_domain`：按站点分组折叠（1/0）
- `range_start` / `range_end`：多日统计日期区间（综合走势 + 人员业绩曲线）
- `file_key` / `raw_order` / `raw_view_type`：原始日志查看

## 局部刷新与导出（GET）

这些参数由前端 JS 自动触发，一般不需要手动调用，但排查问题时很有用：

- `partial=analysis`
  - 返回：分析页主体 HTML（用于切换日期时局部刷新）
  - 处理：`/order/controller.php` -> `render_analysis_content()`

- `partial=order_list`
  - 返回：订单列表 HTML（用于筛选/切换视图时局部刷新）
  - 处理：`/order/controller.php` -> `render_order_list_items()`

- `partial=range_revenue_json`
  - 返回：多日统计（综合走势）JSON 数据
  - 处理：`/order/controller.php` -> `compute_range_revenue_days()`
  - 说明：返回的 `data` 中每个日期对象包含 `people_usd`（人员 USD 归属汇总，依赖 `csv_file` 映射）

- `partial=range_revenue`
  - 返回：多日统计模块 HTML（图表容器 + 区间控件）
  - 处理：`/order/controller.php` -> `render_range_revenue_module()`

- `export=orders_csv`
  - 导出：指定范围内订单 CSV
  - 处理：`/order/controller.php` -> `export_orders_csv_range()`
  - 说明：导出逻辑复用页面同款解析 `orders3_build_analysis_data_and_stats()`，保证与页面订单列表一致

## 多日统计与人员业绩曲线

- 页面刷新（或首次进入分析页）会自动触发一次“重置图表中心和日期区间”，随后拉取 `partial=range_revenue_json` 刷新两张图：
  - **综合走势曲线**（revenueChart）
  - **人员业绩曲线**（peopleChart）
- 区间控件
  - 左侧：起止日期 + 滑块
  - 右侧：快捷“最近 n 天”
    - 默认 `n=7`
    - 支持点击“应用”或在输入框按回车

## 人员归属（CSV 映射）

- `csv_file` 选择的是域名归属映射 CSV 文件（例如 domain -> people/country/category/date/server）。
- 人员汇总与人员曲线依赖该映射：
  - `compute_range_revenue_days()` 会根据订单域名匹配人员，并在 `people_usd` 中按人员汇总 USD。
  - 如果映射未选择或无法匹配人员列，人员曲线可能没有可绘制数据。

## CSV 导出说明（orders_csv）

导出入口：`export=orders_csv`

- 数据来源
  - 逐天调用 `orders3_build_analysis_data_and_stats()` 解析日志，确保导出与页面解析一致。
- 常用筛选
  - 导出会应用页面同款过滤逻辑（`status`/`owner`/`amount_nonzero`/`pending_as_success`）。
- 主要字段（表头会随实现演进，但以下为当前关键字段）
  - 订单基础：`log_date`, `order_no`, `time`, `hour`, `domain`
  - 支付号：`pay_no`（从订单相关日志行中提取 `pay_no=...`）
  - 状态相关：`status`, `is_success`, `has_success_log`, `is_pending`
  - 金额：`amount`, `currency`, `usd_amount`, `usd_basis`
  - 错误：`error`, `notify_errors`
  - 归属：`people`, `server`, `country`, `category`, `site_date`, `csv_file`

## 页面结构

- 顶部日期选择器与快捷跳转
- 分析模式：统计卡片 + 综合走势图 + 人员表现图 + 订单列表
- 原始模式：日志列表查看与切换

## 图表说明

- 综合走势图：支持多曲线显示与图例快速全选/全不选/反选
- 人员表现图：人员 USD 归属曲线（依赖 `people_usd`，与 `csv_file` 映射相关）
- 图表数据来自范围统计模块（`compute_range_revenue_days()`），其内部会读取成功/通知/尝试日志，并按 `pending_as_success` 处理

## 运行与访问

确保日志文件存在后，通过浏览器访问：

```
/forpay/orders3.php?token=YOUR_TOKEN&date=YYYY-MM-DD&mode=analysis
```

常用示例：

```
# 查看今天分析页
/forpay/orders3.php?token=YOUR_TOKEN&mode=analysis

# 查看指定日期分析页
/forpay/orders3.php?token=YOUR_TOKEN&mode=analysis&date=2026-02-03

# 查看原始日志页
/forpay/orders3.php?token=YOUR_TOKEN&mode=raw&date=2026-02-03

# 多日统计指定区间（注意：区间由页面内控件/JS 驱动，手动带参数也可生效）
/forpay/orders3.php?token=YOUR_TOKEN&mode=analysis&date=2026-02-03&range_start=2026-01-25&range_end=2026-02-03

# 导出指定范围 CSV（导出范围优先用 export_start/export_end；否则回退 range_start/range_end）
/forpay/orders3.php?token=YOUR_TOKEN&mode=analysis&export=orders_csv&export_start=2026-02-01&export_end=2026-02-03
```

## 维护建议

- 修改统计逻辑请优先检查 `order/parser.php` 与 `order/range.php`
- 修改图表行为请查看 `orders3.php` 中的 JS 渲染函数
- UI 样式统一在 `order/assets/orders3.css.php`
