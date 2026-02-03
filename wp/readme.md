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
- `csv_file`：CSV 选择
- `list_view`：`card` | `table`
- `amount_nonzero`：金额非 0 过滤（1/0）
- `pending_as_success`：待定计入成功（1/0）
- `cluster_prefix_trim2`：合并订单前缀（去除后两位）（1/0）
- `group_by_domain`：按站点分组折叠（1/0）
- `range_start` / `range_end`：多日统计（综合走势）日期区间选择 / 导出范围使用
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

- `export=orders_csv`
  - 导出：指定范围内订单 CSV
  - 处理：`/order/controller.php` -> `export_orders_csv_range()`

## 页面结构

- 顶部日期选择器与快捷跳转
- 分析模式：统计卡片 + 综合走势图 + 人员表现图 + 订单列表
- 原始模式：日志列表查看与切换

## 图表说明

- 综合走势图：支持多曲线显示与图例快速全选/全不选/反选
- 人员表现图：支持滑块切换与曲线动画
- 图表数据来自 `orders3_build_analysis_data_and_stats()` 与范围统计模块

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
```

## 维护建议

- 修改统计逻辑请优先检查 `order/parser.php` 与 `order/range.php`
- 修改图表行为请查看 `orders3.php` 中的 JS 渲染函数
- UI 样式统一在 `order/assets/orders3.css.php`
