<?php
// ====== 配置与权限控制 ======
$access_token = 'cxxu';
$current_token = $_GET['token'] ?? '';
if ($current_token !== $access_token) {
    http_response_code(403);
    die('403 Forbidden');
}

date_default_timezone_set('Asia/Shanghai');
ini_set('memory_limit', '512M');

$date_param = $_GET['date'] ?? date('Y-m-d');
if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $date_param))
    $date_param = date('Y-m-d');
$log_date = $date_param;

$prev_date = date('Y-m-d', strtotime($log_date . ' -1 day'));
$next_date = date('Y-m-d', strtotime($log_date . ' +1 day'));

$view_mode = $_GET['mode'] ?? 'analysis';
$status_filter = $_GET['status'] ?? 'all';
$amount_nonzero = isset($_GET['amount_nonzero']) ? (bool)$_GET['amount_nonzero'] : false;
$group_by_domain = isset($_GET['group_by_domain']) ? (bool)$_GET['group_by_domain'] : false;
$target_file_key = $_GET['file_key'] ?? 'forpay';
$raw_order = $_GET['raw_order'] ?? 'desc';
$raw_view_type = $_GET['raw_view_type'] ?? 'plain';

$log_files = [
    'forpay_new' => "{$log_date}forpay_new.log",
    'forpay' => "{$log_date}forpay.log",
    'notify' => "{$log_date}notify.log",
    'success' => "{$log_date}success.log",
];

// ==========================================
// 核心数据处理逻辑
// ==========================================
$analysis_data = [];
$stats = [
    'total_orders' => 0,
    'total_attempts' => 0,
    'total_success' => 0,
    'total_usd_sum' => 0,
    'unique_domains' => 0,
    'domain_amount' => [],
    'hourly_attempts' => array_fill(0, 24, 0),
    'hourly_success' => array_fill(0, 24, 0),
];

if ($view_mode === 'analysis') {
    $logs = [];
    foreach ($log_files as $type => $file) {
        $lines = file_exists($file) ? file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) : [];
        // 对 success.log 去重
        if ($type === 'success' && !empty($lines)) {
            $lines = array_values(array_unique($lines));
        }
        $logs[$type] = $lines;
    }

    foreach ($logs['forpay_new'] as $line) {
        if (preg_match('/^(\d{4}-\d{2}-\d{2}\s(\d{2}):\d{2}:\d{2})\|(.*?)\|(\d+)\|/', $line, $m)) {
            $order_no = $m[4];
            $hour = (int) $m[2];
            $analysis_data[$order_no] = [
                'time' => $m[1],
                'hour' => $hour,
                'domain' => $m[3],
                'attempts' => 0,
                'is_success' => false,
                'logs' => ['forpay_new' => [$line]],
                'details' => ['amt' => 0, 'cur' => '', 'usd_amt' => 0, 'err' => '']
            ];
        }
    }

    foreach ($logs['forpay'] as $line) {
        if (preg_match('/\|(\d+)\|/', $line, $m)) {
            $no = $m[1];
            if (isset($analysis_data[$no])) {
                $analysis_data[$no]['attempts']++;
                $analysis_data[$no]['logs']['forpay'][] = $line;
                $stats['total_attempts']++;
                $stats['hourly_attempts'][$analysis_data[$no]['hour']]++;
                if ($json = strstr($line, '{')) {
                    $d = json_decode($json, true);
                    if (isset($d['result']['success']) && $d['result']['success'] === false) {
                        $analysis_data[$no]['details']['err'] = $d['result']['error_code'] ?? $d['result']['msg'] ?? $analysis_data[$no]['details']['err'];
                    }
                }
            }
        }
    }

    foreach ($logs['notify'] as $line) {
        if (preg_match('/"order_no":"(\d+)"/', $line, $m)) {
            $no = $m[1];
            if (!isset($analysis_data[$no]))
                continue;
            $analysis_data[$no]['logs']['notify'][] = $line;
            if ($json = strstr($line, '{')) {
                $d = json_decode($json, true);
                $analysis_data[$no]['details']['amt'] = $d['amount'] ?? $analysis_data[$no]['details']['amt'];
                $analysis_data[$no]['details']['cur'] = $d['currency'] ?? $analysis_data[$no]['details']['cur'];
                if (isset($d['usd_amount']) && is_numeric($d['usd_amount'])) {
                    $analysis_data[$no]['details']['usd_amt'] = floatval($d['usd_amount']);
                } else {
                    $analysis_data[$no]['details']['usd_amt'] = convert_to_usd($analysis_data[$no]['details']['amt'], $analysis_data[$no]['details']['cur']);
                }
                if (($d['failure_code'] ?? '') !== 'success') {
                    $analysis_data[$no]['details']['err'] = $d['failure_msg'] ?? $d['error_code'] ?? $d['msg'] ?? '';
                }
            }
        }
    }

    foreach ($logs['success'] as $line) {
        if (preg_match('/order_no=(\d+)/', $line, $m)) {
            $no = $m[1];
            if (isset($analysis_data[$no])) {
                $analysis_data[$no]['is_success'] = true;
                $analysis_data[$no]['logs']['success'][] = $line;
                $stats['hourly_success'][$analysis_data[$no]['hour']]++;
            }
        }
    }

    $stats['total_orders'] = count($analysis_data);
    foreach ($analysis_data as $no => $item) {
        if ($item['is_success']) {
            $stats['total_success']++;
            $stats['total_usd_sum'] += (float) $item['details']['usd_amt'];
            $cur = $item['details']['cur'] ?: 'UNK';
            $stats['domain_amount'][$item['domain']][$cur] = ($stats['domain_amount'][$item['domain']][$cur] ?? 0) + ($item['details']['amt'] ?? 0);
        }
        if ($status_filter === 'success' && !$item['is_success']) {
            unset($analysis_data[$no]);
            continue;
        }
        if ($status_filter === 'fail' && ($item['is_success'] || empty($item['details']['err']))) {
            unset($analysis_data[$no]);
            continue;
        }
        if ($amount_nonzero && (empty($item['details']['amt']) || $item['details']['amt'] == 0)) {
            unset($analysis_data[$no]);
            continue;
        }
    }
    arsort($stats['domain_amount']); // 按站点数量初步排序
    $stats['unique_domains'] = count($stats['domain_amount']);

    uasort($analysis_data, function ($a, $b) {
        if ($a['is_success'] !== $b['is_success'])
            return $b['is_success'] <=> $a['is_success'];
        return strcmp($b['time'], $a['time']);
    });
}

function format_money($amount)
{
    return number_format((float) $amount, 2, '.', ',');
}
function highlight_log($line)
{
    $line = htmlspecialchars($line);
    $line = preg_replace('/(\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2})/', '<span style="color:#ce9178;">$1</span>', $line);
    $line = preg_replace('/(&quot;\w+&quot;):/', '<span style="color:#9cdcfe;">$1</span>:', $line);
    $line = preg_replace('/(https?:\/\/[^\s\|]+)/', '<span style="color:#4fc1ff;text-decoration:underline;">$1</span>', $line);
    return $line;
}

function convert_to_usd($amount, $currency = '')
{
    // sanitize amount
    $amt = 0.0;
    if (is_numeric($amount)) {
        $amt = (float)$amount;
    } else {
        $clean = preg_replace('/[^\d\.\-]/', '', (string)$amount);
        $amt = $clean === '' ? 0.0 : floatval($clean);
    }
    $cur = strtoupper(trim((string)$currency));
    // Exchange rates: USD per 1 unit of currency
    $rates = [
        'USD' => 1.0, 'USDT' => 1.0, 'TUSD' => 1.0,
        'CNY' => 0.14, 'RMB' => 0.14,
        'EUR' => 1.08, 'GBP' => 1.25, 'JPY' => 0.0067,
        'AUD' => 0.67, 'CAD' => 0.73, 'SGD' => 0.74,
    ];
    if ($cur === '' || $cur === 'USD') return round($amt, 2);
    if (isset($rates[$cur])) return round($amt * $rates[$cur], 2);
    // Unknown currency -> return 0.0
    return 0.0;
}
?>
<!DOCTYPE html>
<html lang="zh-CN">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>高级支付日志监控 PRO</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        :root {
            --bg-main: #f1f5f9;
            --primary: #6366f1;
            --success: #10b981;
            --danger: #ef4444;
            --warning: #f59e0b;
            --dark: #0f172a;
            --card-bg: #ffffff;
        }

        body {
            font-family: 'Inter', system-ui, -apple-system, sans-serif;
            background: var(--bg-main);
            margin: 0;
            padding: 10px;
            color: #1e293b;
            line-height: 1.5;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
        }

        /* Header 优化 */
        header {
            background: var(--dark);
            padding: 15px 20px;
            border-radius: 16px;
            color: white;
            margin-bottom: 20px;
            box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
        }

        .header-top {
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 15px;
        }

        .nav-btn {
            background: #334155;
            border: none;
            padding: 10px 16px;
            border-radius: 10px;
            color: white;
            cursor: pointer;
            text-decoration: none;
            font-size: 14px;
            transition: 0.3s;
            display: inline-flex;
            align-items: center;
            gap: 6px;
        }

        .nav-btn:hover {
            background: var(--primary);
            transform: translateY(-1px);
        }

        .nav-btn.active {
            background: var(--primary);
            box-shadow: 0 4px 12px rgba(99, 102, 241, 0.4);
        }

        /* 统计卡片网格 */
        .stats-overview {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 12px;
            margin-bottom: 20px;
        }

        @media (min-width: 768px) {
            .stats-overview {
                grid-template-columns: repeat(5, 1fr);
            }
        }

        .overview-card {
            background: white;
            padding: 16px;
            border-radius: 16px;
            border: 1px solid #e2e8f0;
            position: relative;
            overflow: hidden;
        }

        .overview-card .label {
            font-size: 12px;
            color: #64748b;
            font-weight: 600;
            display: block;
            margin-bottom: 4px;
        }

        .overview-card .value {
            font-size: 20px;
            font-weight: 800;
            color: var(--dark);
        }

        /* 布局主区域 */
        .main-layout {
            display: flex;
            flex-direction: column;
            gap: 20px;
        }

        @media (min-width: 1024px) {
            .main-layout {
                flex-direction: row;
                align-items: flex-start;
            }

            .content-area {
                flex: 1;
                min-width: 0;
            }

            /* 防止内容溢出 */
            .side-panel {
                width: 350px;
                position: sticky;
                top: 20px;
            }
        }

        .chart-container {
            background: white;
            padding: 20px;
            border-radius: 16px;
            border: 1px solid #e2e8f0;
            margin-bottom: 20px;
            height: 420px;
            box-sizing: border-box;
            overflow-x: auto;
            overflow-y: visible;
        }

        /* 订单列表 */
        .order-item {
            background: white;
            border-radius: 16px;
            margin-bottom: 12px;
            border: 1px solid #e2e8f0;
            transition: all 0.2s ease;
        }

        .order-item:hover {
            border-color: var(--primary);
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05);
        }

        .order-item.is-success {
            border-left: 5px solid var(--success);
        }

        .order-item.is-fail {
            border-left: 5px solid var(--danger);
        }

        .order-main {
            padding: 16px;
            cursor: pointer;
            display: flex;
            flex-direction: column;
            gap: 10px;
        }

        @media (min-width: 640px) {
            .order-main {
                flex-direction: row;
                justify-content: space-between;
                align-items: center;
            }
        }

        .badge {
            padding: 4px 10px;
            border-radius: 8px;
            font-size: 11px;
            font-weight: 700;
            text-transform: uppercase;
        }

        .badge-attempts {
            background: #f1f5f9;
            color: #475569;
        }

        .error-msg {
            color: var(--danger);
            font-size: 12px;
            font-weight: 600;
            background: #fff1f2;
            padding: 6px 10px;
            border-radius: 8px;
            margin-top: 8px;
            display: inline-block;
            width: fit-content;
        }

        /* 日志详情区域 */
        .log-section {
            display: none;
            background: #0f172a;
            padding: 15px;
            border-bottom-left-radius: 16px;
            border-bottom-right-radius: 16px;
            overflow-x: auto;
        }

        .log-content {
            font-family: 'Fira Code', 'Consolas', monospace;
            font-size: 12px;
            color: #cbd5e1;
            white-space: pre-wrap;
            word-break: break-all;
            line-height: 1.6;
        }

        /* 源码查看器 */
        .raw-box {
            background: #f8fafc;
            border-radius: 16px;
            border: 1px solid #cbd5e1;
            overflow: hidden;
            box-shadow: 0 2px 8px 0 rgba(99,102,241,0.04);
        }

        .code-window {
            width: 100%;
            border-collapse: collapse;
            font-size: 13px;
            table-layout: fixed;
            background: #f1f5f9;
        }

        .num-col {
            width: 40px;
            text-align: center;
            color: #64748b;
            background: #e0e7ef;
            border-right: 1px solid #cbd5e1;
            font-size: 11px;
            vertical-align: top;
            padding-top: 5px;
        }

        .code-col {
            padding: 4px 12px;
            white-space: pre-wrap;
            word-break: break-all;
            font-family: 'Fira Code', monospace;
            background: #f8fafc;
            color: #22223b;
            transition: background 0.2s;
        }

        .code-col:hover {
            background: #e0e7ef;
        }

        .copy-btn {
            background: #6366f1;
            color: #fff;
            border: none;
            border-radius: 8px;
            padding: 6px 16px;
            font-size: 13px;
            font-weight: 600;
            cursor: pointer;
            margin: 10px 0 10px 10px;
            transition: background 0.2s, box-shadow 0.2s;
            box-shadow: 0 2px 8px 0 rgba(99,102,241,0.08);
        }
        .copy-btn:hover {
            background: #4f46e5;
            color: #fff;
        }
        }

        /* 优化后的侧边栏列表 */
        .ranking-list {
            list-style: none;
            padding: 0;
            margin: 0;
        }

        .ranking-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 0;
            border-bottom: 1px solid #f1f5f9;
        }

        .ranking-item:last-child {
            border-bottom: none;
        }

        .dom-name {
            font-weight: 600;
            color: #334155;
            font-size: 13px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            max-width: 180px;
        }

        .dom-val {
            color: var(--success);
            font-weight: 800;
            font-size: 14px;
        }

        /* 针对手机的小调整 */
        @media (max-width: 480px) {
            header h2 {
                font-size: 16px;
                line-height: 1.2;
                word-break: break-all;
            }

            .header-top {
                flex-direction: column;
                align-items: stretch;
                gap: 8px;
            }

            .nav-btn {
                padding: 7px 8px;
                font-size: 12px;
                min-width: 0;
            }

            .overview-card .value {
                font-size: 16px;
            }

            .container {
                padding: 0 2px;
            }

            .header-top > div {
                flex-wrap: wrap;
                gap: 4px;
            }

            #mainDatePicker {
                width: 100px !important;
                font-size: 12px;
                padding: 2px 0;
            }

            .stats-overview {
                grid-template-columns: 1fr 1fr;
                gap: 6px;
            }

            .chart-container {
                margin-bottom: 10px !important;
                height: 320px !important;
                padding: 8px !important;
                min-width: 0;
                overflow-x: auto;
                overflow-y: visible;
            }
            #revenueChart, #hourlyChart {
                min-height: 180px !important;
                height: 180px !important;
                max-height: 220px !important;
                width: 100% !important;
                display: block;
            }
        }
        }
    </style>
</head>

<body>

    <div class="container">
        <header>
            <div class="header-top">
                <h2 style="margin:0;">🛡️ 支付监控中心 <small style="font-size:12px; opacity:0.6; font-weight:normal;">v4.8
                        Enterprise</small></h2>
                <div style="display: flex; gap: 10px; align-items: center;">
                    <div style="background: rgba(255,255,255,0.1); padding: 4px; border-radius: 10px; display: flex; align-items:center; gap:6px;">
                        <a href="?token=<?= $access_token ?>&date=<?= $prev_date ?>&mode=<?= $view_mode ?>"
                            class="nav-btn" style="background:transparent; padding:8px;">«</a>
                        <input type="date" id="mainDatePicker" value="<?= $log_date ?>"
                            onchange="location.href='?token=<?= $access_token ?>&mode=<?= $view_mode ?>&date='+this.value"
                            style="background:transparent; border:none; color:white; font-weight:bold; width:130px; text-align:center;">
                        <a href="?token=<?= $access_token ?>&date=<?= $next_date ?>&mode=<?= $view_mode ?>"
                            class="nav-btn" style="background:transparent; padding:8px;">»</a>
                        <button type="button" class="nav-btn" id="quickTodayBtn" style="font-size:12px;">今天</button>
                        <button type="button" class="nav-btn" id="quickPickBtn" style="font-size:12px;">选择日期…</button>
                    </div>
                    <a href="?<?= http_build_query(array_merge($_GET, ['mode' => 'analysis'])) ?>"
                        class="nav-btn <?= $view_mode == 'analysis' ? 'active' : '' ?>">📊 分析</a>
                    <a href="?<?= http_build_query(array_merge($_GET, ['mode' => 'raw'])) ?>"
                        class="nav-btn <?= $view_mode == 'raw' ? 'active' : '' ?>">📝 源码</a>
                </div>
            </div>
        </header>

        <?php if ($view_mode === 'analysis'): ?>
                <div class="stats-overview">
                <div class="overview-card"><span class="label">总尝试</span><span
                    class="value"><?= $stats['total_attempts'] ?></span></div>
                <div class="overview-card" style="border-bottom: 3px solid var(--success);"><span
                    class="label">成功单量</span><span class="value"
                    style="color:var(--success);"><?= $stats['total_success'] ?></span></div>
                <div class="overview-card" style="border-bottom: 3px solid #db2777;"><span class="label">营收USD-今日指数</span><span class="value"
                    style="color:#db2777;">$<?= format_money($stats['total_usd_sum']) ?></span></div>
                <div class="overview-card"><span class="label">转化率</span><span
                    class="value"><?= $stats['total_orders'] > 0 ? round(($stats['total_success'] / $stats['total_orders']) * 100, 1) : 0 ?>%</span>
                </div>
                </div>

                <div class="chart-container" style="margin-bottom:20px;">
                    <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:8px; gap:10px; flex-wrap:wrap;">
                        <span style="font-size:15px; font-weight:600; color:#6366f1;">📈 区间营收统计</span>
                        <form method="get" style="display:flex; align-items:center; gap:8px;">
                            <input type="hidden" name="token" value="<?= $access_token ?>">
                            <input type="hidden" name="mode" value="<?= $view_mode ?>">
                            <label style="font-size:13px; color:#475569;">区间:
                                <input type="date" name="range_start" value="<?= htmlspecialchars($range_start) ?>" min="<?= $min_date ?>" max="<?= $max_date ?>" style="margin:0 4px; padding:2px 6px; border-radius:6px; border:1px solid #e2e8f0;">
                                ~
                                <input type="date" name="range_end" value="<?= htmlspecialchars($range_end ?: date('Y-m-d')) ?>" min="<?= $min_date ?>" max="<?= $max_date ?>" style="margin:0 4px; padding:2px 6px; border-radius:6px; border:1px solid #e2e8f0;">
                            </label>
                            <button type="submit" style="padding:4px 12px; border-radius:6px; background:#6366f1; color:white; border:none; font-size:13px;">查询</button>
                            <span id="rangeLabel" style="font-size:13px;"></span>
                        </form>
                    </div>
                    <canvas id="revenueChart"></canvas>
                </div>

                <?php
                // ====== 多天营收统计 (与今日营收口径一致: 只统计 success.log 有的订单) ======
                // 统计所有可用日志日期（以 success.log 为准）
                $log_files_list = glob("*success.log");
                $all_dates = [];
                foreach ($log_files_list as $file) {
                    if (preg_match('/^(\d{4}-\d{2}-\d{2})success\\.log$/', $file, $m)) {
                        $all_dates[] = $m[1];
                    }
                }
                sort($all_dates);
                $min_date = $all_dates[0] ?? date('Y-m-d');
                $max_date = $all_dates[count($all_dates)-1] ?? date('Y-m-d');
                // 区间参数
                // 默认区间为前5天到今天
                if (isset($_GET['range_start']) && isset($_GET['range_end'])) {
                    $range_start = $_GET['range_start'];
                    $range_end = $_GET['range_end'];
                } else {
                    $max_date_ts = strtotime($max_date);
                    $range_start = date('Y-m-d', strtotime('-5 days', $max_date_ts));
                    $range_end = $max_date;
                    // 若最早日志日期比默认区间还晚，则取最早日志日期
                    if ($range_start < $min_date) $range_start = $min_date;
                }
                // 生成区间内所有日期
                $revenue_days = [];
                $cur = strtotime($range_start);
                $end = strtotime($range_end);
                while ($cur <= $end) {
                    $date = date('Y-m-d', $cur);
                    $success_file = $date . 'success.log';
                    $notify_file = $date . 'notify.log';
                    $usd_sum = 0;
                    $success_orders = [];
                    if (file_exists($success_file)) {
                        $lines = file($success_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
                        foreach ($lines as $line) {
                            if (preg_match('/order_no=(\d+)/', $line, $m)) {
                                $success_orders[$m[1]] = true;
                            }
                        }
                    }
                    if (file_exists($notify_file) && !empty($success_orders)) {
                        $lines = file($notify_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
                        foreach ($lines as $line) {
                            if (preg_match('/"order_no":"(\d+)"/', $line, $m)) {
                                $current_order_no = $m[1];
                                if (!isset($success_orders[$current_order_no])) continue;
                                unset($success_orders[$current_order_no]);
                                if ($json = strstr($line, '{')) {
                                    $d = json_decode($json, true);
                                    if (isset($d['usd_amount']) && is_numeric($d['usd_amount'])) {
                                        $usd_sum += floatval($d['usd_amount']);
                                    } else {
                                        $amt = $d['amount'] ?? 0;
                                        $curc = $d['currency'] ?? '';
                                        $usd_sum += convert_to_usd($amt, $curc);
                                    }
                                }
                            }
                        }
                    }
                    $revenue_days[] = [
                        'date' => $date,
                        'usd' => round($usd_sum, 2)
                    ];
                    $cur = strtotime('+1 day', $cur);
                }
                ?>

            <div class="main-layout">
                <aside class="side-panel">
                    <div class="overview-card" style="height: auto;">
                        <h3 style="margin-top:0; font-size:16px; display:flex; align-items:center; gap:8px;">
                            <span style="background:var(--primary); color:white; padding:4px; border-radius:6px;">💰</span>
                            站点营收排行
                        </h3>
                        <ul class="ranking-list">
                            <?php if (empty($stats['domain_amount'])): ?>
                                <li style="color:#94a3b8; font-size:13px; text-align:center; padding:20px;">今日暂无成交</li>
                            <?php endif; ?>
                            <?php foreach ($stats['domain_amount'] as $dom => $currs): ?>
                                <li class="ranking-item">
                                    <span class="dom-name"
                                        title="<?= htmlspecialchars($dom) ?>"><?= htmlspecialchars($dom) ?></span>
                                    <div style="text-align:right;">
                                        <?php foreach ($currs as $c => $v): ?>
                                            <div class="dom-val"><?= $c ?>             <?= format_money($v) ?></div>
                                        <?php endforeach; ?>
                                    </div>
                                </li>
                            <?php endforeach; ?>
                        </ul>
                    </div>
                </aside>
                <div class="content-area">
                    <div class="chart-container"><canvas id="hourlyChart"></canvas></div>

                    <div
                        style="display:flex; justify-content:space-between; align-items:center; margin-bottom:15px; padding:0 5px;">
                        <h3 style="margin:0; font-size:18px;">📋 实时解析列表</h3>
                        <form method="get" style="display:flex; align-items:center; gap:10px;">
                            <input type="hidden" name="token" value="<?= $access_token ?>">
                            <input type="hidden" name="date" value="<?= $log_date ?>">
                            <select name="status" onchange="this.form.submit()"
                                style="padding:8px 12px; border-radius:10px; border:1px solid #e2e8f0; background:white; font-weight:600;">
                                <option value="all" <?= $status_filter == 'all' ? 'selected' : '' ?>>全部记录</option>
                                <option value="success" <?= $status_filter == 'success' ? 'selected' : '' ?>>✅ 仅成功</option>
                                <option value="fail" <?= $status_filter == 'fail' ? 'selected' : '' ?>>❌ 仅失败</option>
                            </select>
                            <label style="font-size:13px; color:#475569; display:flex; align-items:center; gap:4px;">
                                <input type="checkbox" name="amount_nonzero" value="1" onchange="this.form.submit()" <?= $amount_nonzero ? 'checked' : '' ?>>
                                仅显示金额非零
                            </label>
                            <label style="font-size:13px; color:#475569; display:flex; align-items:center; gap:4px;">
                                <input type="checkbox" name="group_by_domain" value="1" onchange="this.form.submit()" <?= $group_by_domain ? 'checked' : '' ?>>
                                按站点分组折叠
                            </label>
                        </form>
                    </div>

                    <div class="order-list">
                        <?php
                        $order_index = 1;
                        if ($group_by_domain) {
                            $grouped = [];
                            foreach ($analysis_data as $no => $item) {
                                $grouped[$item['domain']][] = ['no' => $no, 'item' => $item];
                            }
                            $group_index = 1;
                            foreach ($grouped as $domain => $orders) {
                                echo '<div class="order-item" style="border-left:5px solid #6366f1; margin-bottom:18px;">';
                                echo '<div class="order-main" onclick="document.getElementById(\'group_' . md5($domain) . '\').style.display = (document.getElementById(\'group_' . md5($domain) . '\').style.display==\'none\'?\'block\':\'none\');">';
                                echo '<span style="font-size:14px; color:#fff; font-weight:bold; background:#6366f1; border-radius:6px; padding:2px 10px; margin-right:10px;">' . $group_index . '</span>';
                                $group_index++;
                                echo '<strong style="font-size:16px; color:#6366f1;">' . htmlspecialchars($domain) . '</strong>';
                                echo '<span class="badge badge-attempts" style="margin-left:10px;">' . count($orders) . '条订单</span>';
                                echo '<span style="margin-left:10px; color:#64748b; font-size:13px;">点击展开/收起</span>';
                                echo '</div>';
                                echo '<div id="group_' . md5($domain) . '" style="display:none;">';
                                foreach ($orders as $order) {
                                    $item = $order['item'];
                                    $no = $order['no'];
                                    $st_class = $item['is_success'] ? 'is-success' : (!empty($item['details']['err']) ? 'is-fail' : '');
                                    echo '<div class="order-item ' . $st_class . '" style="margin-bottom:8px;">';
                                    echo '<div class="order-main" onclick="toggleLog(\'log_' . $no . '\')">';
                                    echo '<div style="flex:1;">';
                                    echo '<div style="display:flex; align-items:center; gap:8px; flex-wrap:wrap;">';
                                    echo '<span style="font-size:13px; color:#64748b; font-weight:bold; background:#f1f5f9; border-radius:6px; padding:2px 8px; margin-right:6px;">' . $order_index . '</span>';
                                    $order_index++;
                                    echo '<strong style="font-size:15px;">' . htmlspecialchars($item['domain']) . '</strong>';
                                    echo '<span class="badge badge-attempts">' . $item['attempts'] . '次尝试</span>';
                                    echo '</div>';
                                    echo '<div style="font-size:12px; color:#94a3b8; margin-top:4px;">单号: ' . $no . ' · ' . substr($item['time'], 11) . '</div>';
                                    if (!empty($item['details']['err'])) {
                                        echo '<div class="error-msg">⚠️ ' . htmlspecialchars($item['details']['err']) . '</div>';
                                    }
                                    echo '</div>';
                                    echo '<div style="text-align:right; min-width:120px;">';
                                    echo '<div style="font-size:16px; font-weight:800;">';
                                    echo '<small style="font-size:11px; color:#64748b;">' . $item['details']['cur'] . '</small>';
                                    echo format_money($item['details']['amt']);
                                    echo '</div>';
                                    if ($item['details']['usd_amt'] > 0) {
                                        echo '<div style="font-size:12px; color:#94a3b8; margin-bottom:4px;">≈$' . format_money($item['details']['usd_amt']) . '</div>';
                                    }
                                    echo '<span class="badge" style="background:' . ($item['is_success'] ? '#ecfdf5' : '#f8fafc') . '; color:' . ($item['is_success'] ? '#059669' : '#64748b') . ';">' . ($item['is_success'] ? 'SUCCESS' : 'INCOMPLETE') . '</span>';
                                    echo '</div>';
                                    echo '</div>';
                                    echo '<div class="log-section" id="log_' . $no . '">';
                                    foreach ($item['logs'] as $type => $lines) {
                                        echo '<div style="color: #6366f1; font-size: 10px; font-weight: 800; padding: 5px 0; border-bottom: 1px solid #1e293b; margin-bottom: 8px;">' . strtoupper($type) . '</div>';
                                        echo '<div class="log-content" data-json-auto="true">';
                                        foreach ($lines as $l) echo highlight_log($l) . "\n";
                                        echo '</div>';
                                    }
                                    echo '</div>';
                                    echo '</div>';
                                }
                                echo '</div>';
                                echo '</div>';
                            }
                        } else {
                            foreach ($analysis_data as $no => $item) {
                                $st_class = $item['is_success'] ? 'is-success' : (!empty($item['details']['err']) ? 'is-fail' : '');
                                echo '<div class="order-item ' . $st_class . '">';
                                echo '<div class="order-main" onclick="toggleLog(\'log_' . $no . '\')">';
                                echo '<div style="flex:1;">';
                                echo '<div style="display:flex; align-items:center; gap:8px; flex-wrap:wrap;">';
                                echo '<span style="font-size:13px; color:#64748b; font-weight:bold; background:#f1f5f9; border-radius:6px; padding:2px 8px; margin-right:6px;">' . $order_index . '</span>';
                                $order_index++;
                                echo '<strong style="font-size:15px;">' . htmlspecialchars($item['domain']) . '</strong>';
                                echo '<span class="badge badge-attempts">' . $item['attempts'] . '次尝试</span>';
                                echo '</div>';
                                echo '<div style="font-size:12px; color:#94a3b8; margin-top:4px;">单号: ' . $no . ' · ' . substr($item['time'], 11) . '</div>';
                                if (!empty($item['details']['err'])) {
                                    echo '<div class="error-msg">⚠️ ' . htmlspecialchars($item['details']['err']) . '</div>';
                                }
                                echo '</div>';
                                echo '<div style="text-align:right; min-width:120px;">';
                                echo '<div style="font-size:16px; font-weight:800;">';
                                echo '<small style="font-size:11px; color:#64748b;">' . $item['details']['cur'] . '</small>';
                                echo format_money($item['details']['amt']);
                                echo '</div>';
                                if ($item['details']['usd_amt'] > 0) {
                                    echo '<div style="font-size:12px; color:#94a3b8; margin-bottom:4px;">≈$' . format_money($item['details']['usd_amt']) . '</div>';
                                }
                                echo '<span class="badge" style="background:' . ($item['is_success'] ? '#ecfdf5' : '#f8fafc') . '; color:' . ($item['is_success'] ? '#059669' : '#64748b') . ';">' . ($item['is_success'] ? 'SUCCESS' : 'INCOMPLETE') . '</span>';
                                echo '</div>';
                                echo '</div>';
                                echo '<div class="log-section" id="log_' . $no . '">';
                                foreach ($item['logs'] as $type => $lines) {
                                    echo '<div style="color: #6366f1; font-size: 10px; font-weight: 800; padding: 5px 0; border-bottom: 1px solid #1e293b; margin-bottom: 8px;">' . strtoupper($type) . '</div>';
                                    echo '<div class="log-content" data-json-auto="true">';
                                    foreach ($lines as $l) echo highlight_log($l) . "\n";
                                    echo '</div>';
                                }
                                echo '</div>';
                                echo '</div>';
                            }
                        }
                        ?>
                    </div>
                </div>


            </div>

        <?php else: ?>
            <div class="raw-box">
                <div
                    style="padding:12px 16px; background:#e0e7ef; border-bottom:1px solid #cbd5e1; display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px;">
                    <div style="display:flex; gap:6px; overflow-x:auto; padding-bottom:2px;">
                        <?php foreach ($log_files as $k => $v): ?>
                            <a href="?<?= http_build_query(array_merge($_GET, ['file_key' => $k])) ?>"
                                class="nav-btn <?= $k == $target_file_key ? 'active' : '' ?>"
                                style="padding:6px 12px; font-size:12px;"><?= $k ?></a>
                        <?php endforeach; ?>
                    </div>
                    <div style="display:flex; gap:8px; align-items:center;">
                        <a href="?<?= http_build_query(array_merge($_GET, ['raw_order' => ($raw_order == 'desc' ? 'asc' : 'desc')])) ?>"
                            class="nav-btn" style="background:#64748b; font-size:12px;">
                            <?= $raw_order == 'desc' ? '⬇️ 倒序' : '⬆️ 正序' ?>
                        </a>
                        <a href="?<?= http_build_query(array_merge($_GET, ['raw_view_type' => ($raw_view_type == 'plain' ? 'optimized' : 'plain')])) ?>"
                            class="nav-btn"
                            style="background:<?= $raw_view_type == 'optimized' ? '#10b981' : '#64748b' ?>; font-size:12px;">
                            <?= $raw_view_type == 'optimized' ? '✨ 已美化' : '📄 原始' ?>
                        </a>
                        <button class="copy-btn" id="copyRawContentBtn" type="button">复制全部</button>
                    </div>
                </div>
                <div style="overflow-x: auto;">
                    <table class="code-window" id="rawCodeTable">
                        <?php
                        $f = $log_files[$target_file_key];
                        $raw_content_for_copy = '';
                        if (file_exists($f)) {
                            $lines = file($f);
                            if ($raw_order === 'desc')
                                $lines = array_reverse($lines, true);
                            foreach ($lines as $idx => $line) {
                                $display_line = htmlspecialchars($line);
                                if ($raw_view_type === 'optimized') {
                                    if ($json_start = strpos($line, '{')) {
                                        $json_part = substr($line, $json_start);
                                        $data = json_decode($json_part, true);
                                        if ($data) {
                                            $pretty = json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
                                            $display_line = substr($line, 0, $json_start) . "\n<span style='color:#059669; font-weight:bold;'>[JSON 解码]</span>\n" . htmlspecialchars($pretty);
                                        }
                                    }
                                }
                                $raw_content_for_copy .= $line;
                                echo '<tr><td class="num-col">' . ($idx + 1) . '</td><td class="code-col">' . $display_line . '</td></tr>';
                            }
                        } else {
                            echo '<tr><td colspan="2" style="padding:40px; text-align:center; color:#94a3b8;">日志文件不存在 (' . $f . ')</td></tr>';
                        }
                        ?>
                    </table>
                </div>
            </div>
        <?php endif; ?>
    </div>

    <!-- 已移除滑条滑块相关依赖 -->
    <script>
                // 源码复制按钮功能
                document.addEventListener('DOMContentLoaded', function() {
                    var copyBtn = document.getElementById('copyRawContentBtn');
                    if (copyBtn) {
                        copyBtn.onclick = function() {
                            var codeTable = document.getElementById('rawCodeTable');
                            if (!codeTable) return;
                            // 拼接所有 code-col 的纯文本
                            var text = '';
                            codeTable.querySelectorAll('.code-col').forEach(function(td) {
                                text += td.innerText + '\n';
                            });
                            if (navigator.clipboard) {
                                navigator.clipboard.writeText(text).then(function() {
                                    copyBtn.innerText = '已复制!';
                                    setTimeout(function() { copyBtn.innerText = '复制全部'; }, 1200);
                                });
                            } else {
                                // fallback
                                var textarea = document.createElement('textarea');
                                textarea.value = text;
                                document.body.appendChild(textarea);
                                textarea.select();
                                document.execCommand('copy');
                                document.body.removeChild(textarea);
                                copyBtn.innerText = '已复制!';
                                setTimeout(function() { copyBtn.innerText = '复制全部'; }, 1200);
                            }
                        }
                    }
                });
        // 日期选择器增强：弹窗日历和快速跳转
        document.addEventListener('DOMContentLoaded', function() {
            const mainDatePicker = document.getElementById('mainDatePicker');
            const quickTodayBtn = document.getElementById('quickTodayBtn');
            const quickPickBtn = document.getElementById('quickPickBtn');
            if (quickTodayBtn) {
                quickTodayBtn.onclick = function() {
                    const today = new Date();
                    const yyyy = today.getFullYear();
                    const mm = String(today.getMonth() + 1).padStart(2, '0');
                    const dd = String(today.getDate()).padStart(2, '0');
                    const dateStr = `${yyyy}-${mm}-${dd}`;
                    location.href = `?token=<?= $access_token ?>&mode=<?= $view_mode ?>&date=${dateStr}`;
                };
            }
            if (quickPickBtn) {
                quickPickBtn.onclick = function() {
                    mainDatePicker.showPicker ? mainDatePicker.showPicker() : mainDatePicker.focus();
                };
            }
        });
        // 多天营收统计图表（滑块已移除，默认全区间）
        const revenueData = <?= json_encode($revenue_days) ?>;
        const allDates = revenueData.map(d => d.date);
        // 默认全区间
        let startIdx = 0;
        let endIdx = allDates.length - 1;
        document.getElementById('rangeLabel').innerText = allDates[startIdx] + ' ~ ' + allDates[endIdx];
        function renderRevenueChart(startIdx, endIdx) {
            const data = revenueData.slice(startIdx, endIdx+1);
            const ctx = document.getElementById('revenueChart').getContext('2d');
            if (window.revenueChartInstance) window.revenueChartInstance.destroy();
            let showLabel = (data.length <= 5);
            window.revenueChartInstance = new Chart(ctx, {
                type: 'line',
                data: {
                    labels: data.map(d => d.date),
                    datasets: [{
                        label: '日总营收参考',
                        data: data.map(d => d.usd),
                        borderColor: '#6366f1',
                        backgroundColor: 'rgba(99,102,241,0.08)',
                        fill: true,
                        tension: 0.3,
                        pointRadius: 4,
                        pointBackgroundColor: '#6366f1',
                        pointBorderColor: '#fff',
                        borderWidth: 3
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: { display: false },
                        tooltip: {
                            callbacks: {
                                label: function(context) {
                                    return '金额: $' + context.parsed.y.toLocaleString(undefined, {minimumFractionDigits:2, maximumFractionDigits:2});
                                }
                            }
                        },
                        datalabels: {
                            display: showLabel,
                            color: '#222',
                            align: 'end',
                            anchor: 'end',
                            formatter: function(value, context) {
                                return value > 0 ? '$' + value.toLocaleString(undefined, {minimumFractionDigits:2, maximumFractionDigits:2}) : '';
                            }
                        }
                    },
                    scales: {
                        y: { beginAtZero: true, grid: { color: '#f1f5f9' } },
                        x: { grid: { display: false } }
                    }
                }
            });
        }
        // 初始渲染
        renderRevenueChart(startIdx, endIdx);
        function toggleLog(id) {
            const el = document.getElementById(id);
            const isOpening = el.style.display !== 'block';
            el.style.display = isOpening ? 'block' : 'none';

            if (isOpening && !el.dataset.optimized) {
                el.querySelectorAll('.log-content[data-json-auto="true"]').forEach(container => {
                    const text = container.innerText;
                    const jsonMatch = text.match(/\{.*\}/);
                    if (jsonMatch) {
                        try {
                            let jsonStr = jsonMatch[0].replace(/\\"/g, '"').replace(/\\\\/g, '\\');
                            const jsonObj = JSON.parse(jsonStr);
                            const formatted = JSON.stringify(jsonObj, null, 4);
                            container.innerHTML = text.replace(jsonMatch[0], "\n<span style='color:#4ade80;font-weight:bold;'>[自动美化 JSON]:</span>\n<pre style='color:#4ade80;margin:5px 0 0 0; font-family:inherit;'>" + formatted + "</pre>");
                        } catch (e) { }
                    }
                });
                el.dataset.optimized = "true";
            }
        }

        <?php if ($view_mode === 'analysis'): ?>
            const ctx = document.getElementById('hourlyChart').getContext('2d');
            new Chart(ctx, {
                type: 'line',
                data: {
                    labels: <?= json_encode(range(0, 23)) ?>.map(h => h + ':00'),
                    datasets: [{
                        label: '尝试次数', data: <?= json_encode(array_values($stats['hourly_attempts'])) ?>,
                        borderColor: '#6366f1', backgroundColor: 'rgba(99, 102, 241, 0.05)', fill: true, tension: 0.4, borderWidth: 2, pointRadius: 3
                    }, {
                        label: '成功次数', data: <?= json_encode(array_values($stats['hourly_success'])) ?>,
                        borderColor: '#10b981', backgroundColor: 'transparent', borderDash: [5, 5], tension: 0.4, borderWidth: 2, pointRadius: 3
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    interaction: { intersect: false, mode: 'index' },
                    plugins: { legend: { position: 'top', labels: { usePointStyle: true, boxSize: 6 } } },
                    scales: {
                        y: { beginAtZero: true, grid: { color: '#f1f5f9' }, ticks: { stepSize: 1 } },
                        x: { grid: { display: false } }
                    }
                }
            });
        <?php endif; ?>
    </script>
    <!-- 悬浮回顶部/底部控件 -->
    <div id="float-nav" style="position:fixed;right:24px;bottom:80px;z-index:9999;display:flex;flex-direction:column;gap:12px;">
        <button onclick="window.scrollTo({top:0,behavior:'smooth'});" style="width:48px;height:48px;border-radius:50%;border:none;background:#6366f1;color:#fff;box-shadow:0 2px 8px #0002;cursor:pointer;font-size:20px;">↑</button>
        <button onclick="window.scrollTo({top:document.body.scrollHeight,behavior:'smooth'});" style="width:48px;height:48px;border-radius:50%;border:none;background:#10b981;color:#fff;box-shadow:0 2px 8px #0002;cursor:pointer;font-size:20px;">↓</button>
    </div>

</body>

</html>