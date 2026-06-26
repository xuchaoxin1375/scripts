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
$order_sort = $_GET['sort'] ?? 'time_desc';
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
    'revenue_by_currency' => ['USD' => 0, 'EUR' => 0, 'GBP' => 0],
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
                'details' => ['amt' => 0, 'cur' => '', 'usd_amt' => 0, 'err' => '', 'notify_count' => 0, 'notify_errors' => []]
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
            $analysis_data[$no]['details']['notify_count'] = ($analysis_data[$no]['details']['notify_count'] ?? 0) + 1;
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
                    $err_msg = $d['failure_msg'] ?? $d['error_code'] ?? $d['msg'] ?? '';
                    if ($err_msg !== '') {
                        $analysis_data[$no]['details']['notify_errors'][] = $err_msg;
                    }
                }
            }
        }
    }

    foreach ($analysis_data as $no => &$item_ref) {
        if (!empty($item_ref['details']['notify_errors']) && is_array($item_ref['details']['notify_errors'])) {
            $uniq = array_values(array_unique(array_filter(array_map('strval', $item_ref['details']['notify_errors']))));
            $item_ref['details']['notify_errors'] = $uniq;
            if (empty($item_ref['details']['err']) && !empty($uniq)) {
                $item_ref['details']['err'] = 'notify中非成功日志错误类型: ' . implode(' | ', $uniq);
            }
        }
    }
    unset($item_ref);

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

            $cur_upper = strtoupper((string)($item['details']['cur'] ?? ''));
            if (isset($stats['revenue_by_currency'][$cur_upper])) {
                $stats['revenue_by_currency'][$cur_upper] += (float)($item['details']['amt'] ?? 0);
            }
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

function render_order_list_items($analysis_data, $group_by_domain, $order_sort, $status_filter)
{
    ob_start();
    $order_index = 1;

    $sort_orders_inplace = function (&$orders) use ($order_sort) {
        uasort($orders, function ($a, $b) use ($order_sort) {
            $get_amt = function ($x) {
                $v = $x['details']['amt'] ?? 0;
                return is_numeric($v) ? (float)$v : 0.0;
            };
            $get_attempts = function ($x) {
                $v = $x['attempts'] ?? 0;
                return is_numeric($v) ? (int)$v : 0;
            };
            $get_time = function ($x) {
                return (string)($x['time'] ?? '');
            };

            switch ($order_sort) {
                case 'amt_asc':
                    $cmp = $get_amt($a) <=> $get_amt($b);
                    break;
                case 'amt_desc':
                    $cmp = $get_amt($b) <=> $get_amt($a);
                    break;
                case 'attempts_asc':
                    $cmp = $get_attempts($a) <=> $get_attempts($b);
                    break;
                case 'attempts_desc':
                    $cmp = $get_attempts($b) <=> $get_attempts($a);
                    break;
                case 'time_asc':
                    $cmp = strcmp($get_time($a), $get_time($b));
                    break;
                case 'time_desc':
                default:
                    $cmp = strcmp($get_time($b), $get_time($a));
                    break;
            }

            if ($cmp !== 0) return $cmp;
            return strcmp($get_time($b), $get_time($a));
        });
    };

    if ($group_by_domain) {
        // 站点分组折叠
        $grouped = [];
        foreach ($analysis_data as $no => $item) {
            $grouped[$item['domain']][] = ['no' => $no, 'item' => $item];
        }
        $group_index = 1;

        if ($status_filter === 'success' || $status_filter === 'fail') {
            foreach ($grouped as $domain => $orders) {
                $has_success = false;
                foreach ($orders as $order) {
                    if (!empty($order['item']['is_success'])) {
                        $has_success = true;
                        break;
                    }
                }
                if ($status_filter === 'success' && !$has_success) {
                    unset($grouped[$domain]);
                    continue;
                }
                if ($status_filter === 'fail' && $has_success) {
                    unset($grouped[$domain]);
                    continue;
                }
            }
        }

        foreach ($grouped as $domain => $orders) {
            usort($orders, function ($a, $b) use ($order_sort) {
                $ia = $a['item'];
                $ib = $b['item'];
                $get_amt = function ($x) {
                    $v = $x['details']['amt'] ?? 0;
                    return is_numeric($v) ? (float)$v : 0.0;
                };
                $get_attempts = function ($x) {
                    $v = $x['attempts'] ?? 0;
                    return is_numeric($v) ? (int)$v : 0;
                };
                $get_time = function ($x) {
                    return (string)($x['time'] ?? '');
                };

                switch ($order_sort) {
                    case 'amt_asc':
                        $cmp = $get_amt($ia) <=> $get_amt($ib);
                        break;
                    case 'amt_desc':
                        $cmp = $get_amt($ib) <=> $get_amt($ia);
                        break;
                    case 'attempts_asc':
                        $cmp = $get_attempts($ia) <=> $get_attempts($ib);
                        break;
                    case 'attempts_desc':
                        $cmp = $get_attempts($ib) <=> $get_attempts($ia);
                        break;
                    case 'time_asc':
                        $cmp = strcmp($get_time($ia), $get_time($ib));
                        break;
                    case 'time_desc':
                    default:
                        $cmp = strcmp($get_time($ib), $get_time($ia));
                        break;
                }
                if ($cmp !== 0) return $cmp;
                return strcmp($get_time($ib), $get_time($ia));
            });
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
                echo '<button type="button" class="copy-domain-btn" data-copy-domain="' . htmlspecialchars($item['domain']) . '">复制域名</button>';
                $notify_cnt = (int)($item['details']['notify_count'] ?? 0);
                echo '<span class="badge badge-attempts">' . $notify_cnt . '条notify</span>';
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
        // 成功/失败大分组折叠
        $grouped_orders = [
            'success' => [],
            'fail' => []
        ];
        foreach ($analysis_data as $no => $item) {
            if ($item['is_success']) {
                $grouped_orders['success'][$no] = $item;
            } else {
                $grouped_orders['fail'][$no] = $item;
            }
        }

        foreach ($grouped_orders as $k => &$orders_ref) {
            $sort_orders_inplace($orders_ref);
        }
        unset($orders_ref);

        $group_titles = [
            'success' => '✅ 成功订单',
            'fail' => '❌ 失败订单'
        ];
        foreach ($grouped_orders as $group_key => $orders) {
            $group_id = 'order_group_' . $group_key;
            echo '<div class="order-item" id="' . $group_id . '_wrap" style="border-left:5px solid ' . ($group_key == 'success' ? '#10b981' : '#ef4444') . '; margin-bottom:18px;">';
            echo '<div class="order-main" style="cursor:pointer;user-select:none;" onclick="var el=document.getElementById(\'' . $group_id . '\');el.style.display=(el.style.display==\'none\'?\'block\':\'none\');">';
            echo '<span style="font-size:15px; font-weight:bold; color:' . ($group_key == 'success' ? '#10b981' : '#ef4444') . ';">' . $group_titles[$group_key] . '</span>';
            echo '<span class="badge badge-attempts" style="margin-left:10px;">' . count($orders) . '条</span>';
            echo '<span style="margin-left:10px; color:#64748b; font-size:13px;">点击展开/收起</span>';
            echo '</div>';
            echo '<div id="' . $group_id . '" style="display:none;">';
            foreach ($orders as $no => $item) {
                $st_class = $item['is_success'] ? 'is-success' : (!empty($item['details']['err']) ? 'is-fail' : '');
                echo '<div class="order-item ' . $st_class . '" style="margin-bottom:8px;">';
                echo '<div class="order-main" onclick="toggleLog(\'log_' . $no . '\')">';
                echo '<div style="flex:1;">';
                echo '<div style="display:flex; align-items:center; gap:8px; flex-wrap:wrap;">';
                echo '<span style="font-size:13px; color:#64748b; font-weight:bold; background:#f1f5f9; border-radius:6px; padding:2px 8px; margin-right:6px;">' . $order_index . '</span>';
                $order_index++;
                echo '<strong style="font-size:15px;">' . htmlspecialchars($item['domain']) . '</strong>';
                echo '<button type="button" class="copy-domain-btn" data-copy-domain="' . htmlspecialchars($item['domain']) . '">复制域名</button>';
                $notify_cnt = (int)($item['details']['notify_count'] ?? 0);
                echo '<span class="badge badge-attempts">' . $notify_cnt . '条notify</span>';
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
    }
    return ob_get_clean();
}

$is_partial_order_list = ($view_mode === 'analysis' && (($_GET['partial'] ?? '') === 'order_list'));
if ($is_partial_order_list) {
    header('Content-Type: text/html; charset=UTF-8');
    echo render_order_list_items($analysis_data, $group_by_domain, $order_sort, $status_filter);
    exit;
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
            padding: 0;
            color: #1e293b;
            line-height: 1.5;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 10px;
        }

        /* Header 优化 */
        header {
            background: var(--dark);
            padding: 15px 20px;
            border-radius: 16px;
            color: white;
            margin-bottom: 20px;
            box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
            position: static;
            top: auto;
            z-index: auto;
        }

        header.is-collapsed {
            padding: 0;
            margin-bottom: 10px;
            border-radius: 0 0 16px 16px;
        }

        header.is-collapsed .header-top {
            display: none;
        }

        #headerCollapseBtn {
            flex: 0 0 auto;
            padding: 10px 12px;
            min-height: 40px;
            line-height: 1;
        }

        #headerExpandBtn {
            position: fixed;
            top: calc(10px + env(safe-area-inset-top, 0px));
            right: calc(14px + env(safe-area-inset-right, 0px));
            z-index: 1200;
            background: var(--dark);
            color: #fff;
            border: 1px solid rgba(255,255,255,0.18);
            border-radius: 12px;
            padding: 10px 12px;
            font-size: 13px;
            font-weight: 700;
            cursor: pointer;
            box-shadow: 0 10px 18px rgba(0,0,0,0.18);
            display: none;
        }

        @media (max-width: 900px) {
            #headerCollapseBtn {
                padding: 8px 10px;
                min-height: 36px;
                font-size: 12px;
            }
            #headerExpandBtn {
                padding: 10px 12px;
                min-height: 40px;
            }
        }

        .order-filter-bar {
            position: static;
            top: auto;
            z-index: auto;
            padding: 8px 0 10px;
            background: linear-gradient(to bottom, rgba(241,245,249,0.98), rgba(241,245,249,0.94));
            backdrop-filter: blur(6px);
        }

        @media (max-width: 899px) {
            .order-filter-bar {
                position: static;
                left: auto;
                right: auto;
                bottom: auto;
                top: auto;
                padding: 0;
                background: transparent;
                z-index: auto;
                backdrop-filter: none;
            }
            #orderFilterCollapsedChip {
                display: none;
            }
            #mobileFilterFab {
                position: fixed;
                /* right: calc(10px + env(safe-area-inset-right, 0px)); */
                right:1px;
                top: 50%;
                bottom: auto;
                transform: translateY(-50%);
                z-index: 1200;
                width: 24px;
                height: 54px;
                border-radius: 999px;
                border: 1px solid rgba(225, 240, 14, 1);
                background: #0b122254;
                color: #fff;
                font-weight: 900;
                font-size: 13px;
                cursor: pointer;
                box-shadow: 0 14px 28px rgba(0,0,0,0.25);
                display: none;
                align-items: center;
                justify-content: center;
            }
            #mobileFilterFab.is-visible {
                display: flex;
            }
            #mobileFilterFab:active {
                transform: translateY(-50%) scale(0.98);
            }
            #mobileFilterSheet {
                position: fixed;
                inset: 0;
                z-index: 1300;
                display: none;
            }
            #mobileFilterSheet.is-open {
                display: block;
            }
            #mobileFilterSheet .sheet-backdrop {
                position: absolute;
                inset: 0;
                background: rgba(15, 23, 42, 0.45);
            }
            #mobileFilterSheet .sheet-panel {
                position: absolute;
                left: 10px;
                right: 10px;
                bottom: calc(10px + env(safe-area-inset-bottom, 0px));
                border-radius: 16px;
                background: #fff;
                border: 1px solid #e2e8f0;
                box-shadow: 0 20px 40px rgba(0,0,0,0.25);
                padding: 12px;
                max-height: 70vh;
                overflow: auto;
            }
            #mobileFilterSheet .sheet-header {
                display: flex;
                align-items: center;
                justify-content: space-between;
                gap: 10px;
                padding-bottom: 10px;
                border-bottom: 1px solid #e2e8f0;
                margin-bottom: 10px;
            }
            #mobileFilterSheet .sheet-title {
                font-size: 14px;
                font-weight: 900;
                color: #0f172a;
            }
            #mobileFilterSheet .sheet-close {
                border: none;
                border-radius: 10px;
                background: #0b1222;
                color: #fff;
                font-size: 13px;
                font-weight: 800;
                padding: 8px 10px;
                cursor: pointer;
            }
            #mobileFilterSheet .order-filter-inner {
                border: none;
                box-shadow: none;
                padding: 0;
            }
            #mobileFilterSheet .order-filter-title {
                display: none;
            }
            #mobileFilterSheet .order-filter-controls {
                justify-content: flex-start;
            }
            #mobileFilterSheet .order-filter-controls select {
                flex: 1 1 160px;
                min-width: 0;
            }
        }

        @media (min-width: 900px) {
            header {
                position: sticky;
                top: 0;
                z-index: 1000;
            }
            .order-filter-bar {
                position: sticky;
                top: var(--sticky-filter-top, 88px);
                z-index: 900;
            }
        }

        .order-filter-inner {
            background: white;
            border: 1px solid #e2e8f0;
            border-radius: 14px;
            padding: 10px 12px;
            box-shadow: 0 6px 14px rgba(15, 23, 42, 0.06);
            display: grid;
            grid-template-columns: 1fr;
            gap: 10px;
        }

        @media (min-width: 900px) {
            .order-filter-inner {
                grid-template-columns: auto 1fr;
                align-items: center;
            }
        }

        .order-filter-title {
            font-size: 18px;
            font-weight: 800;
            margin: 0;
            color: #0f172a;
            white-space: nowrap;
        }

        .order-filter-controls {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            align-items: center;
            justify-content: flex-start;
        }

        .order-filter-controls select {
            min-width: 110px;
        }

        @media (max-width: 520px) {
            .order-filter-controls select {
                flex: 1 1 140px;
                min-width: 0;
            }
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
                top: var(--sticky-side-top, 180px);
            }
        }

        .chart-container {
            background: white;
            padding: 20px;
            border-radius: 16px;
            border: 1px solid #e2e8f0;
            margin-bottom: 20px;
            min-height: 320px;
            height: auto;
            box-sizing: border-box;
            overflow-x: auto;
            overflow-y: visible;
            width: 100%;
            display: flex;
            flex-direction: column;
            justify-content: center;
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

        .copy-domain-btn {
            background: #0b1222;
            color: #fff;
            border: none;
            border-radius: 8px;
            padding: 6px 10px;
            font-size: 12px;
            font-weight: 700;
            cursor: pointer;
            box-shadow: 0 2px 8px rgba(0,0,0,0.08);
        }

        .copy-domain-btn:hover {
            background: #111c33;
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
        @media (max-width: 900px) {
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
                min-height: 180px !important;
                height: auto !important;
                padding: 8px !important;
                min-width: 0;
                overflow-x: auto;
                overflow-y: visible;
            }
            #revenueChart, #hourlyChart {
                min-height: 140px !important;
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
                    <button type="button" id="headerCollapseBtn" class="nav-btn" title="收起页眉" aria-label="收起页眉" style="background:#0b1222; padding:8px 10px;">收起</button>
                </div>
            </div>
        </header>

        <button type="button" id="headerExpandBtn" title="展开页眉" aria-label="展开页眉">展开页眉</button>

        <?php if ($view_mode === 'analysis'): ?>
                <div class="stats-overview">
                <div class="overview-card"><span class="label">总尝试</span><span
                    class="value"><?= $stats['total_attempts'] ?></span></div>
                <div class="overview-card" style="border-bottom: 3px solid var(--success);"><span
                    class="label">成功单量</span><span class="value"
                    style="color:var(--success);"><?= $stats['total_success'] ?></span></div>
                <div class="overview-card" style="border-bottom: 3px solid #db2777;"><span class="label">营收USD-今日指数</span><span class="value"
                    style="color:#db2777;">$<?= format_money($stats['total_usd_sum']) ?></span></div>
                <div class="overview-card" style="border-bottom: 3px solid #0ea5e9;"><span class="label">营收(USD/EUR/GBP)</span><span class="value"
                    style="color:#0ea5e9; font-size:16px;">$<?= format_money($stats['revenue_by_currency']['USD']) ?> / €<?= format_money($stats['revenue_by_currency']['EUR']) ?> / £<?= format_money($stats['revenue_by_currency']['GBP']) ?></span></div>
                <div class="overview-card"><span class="label">转化率</span><span
                    class="value"><?= $stats['total_orders'] > 0 ? round(($stats['total_success'] / $stats['total_orders']) * 100, 1) : 0 ?>%</span>
                </div>
                </div>

                <div class="chart-container" id="revenueChartContainer">
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
                    <div style="width:100%;height:100%;min-height:180px;">
                        <canvas id="revenueChart" style="width:100%;height:100%;min-height:180px;"></canvas>
                    </div>
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
                    <div class="chart-container" id="hourlyChartContainer">
                        <div style="width:100%;height:100%;min-height:180px;">
                            <canvas id="hourlyChart" style="width:100%;height:100%;min-height:180px;"></canvas>
                        </div>
                    </div>

                    <div class="order-filter-bar" id="orderFilterBar">
                        <div class="order-filter-inner">
                            <h3 class="order-filter-title">📋 实时解析列表</h3>
                            <form method="get" id="orderFilterForm" class="order-filter-controls">
                                <input type="hidden" name="token" value="<?= $access_token ?>">
                                <input type="hidden" name="date" value="<?= $log_date ?>">
                                <select name="status" onchange="window.__ordersFilterChange ? window.__ordersFilterChange(this.form) : this.form.submit()"
                                    style="padding:8px 12px; border-radius:10px; border:1px solid #e2e8f0; background:white; font-weight:600;">
                                    <option value="all" <?= $status_filter == 'all' ? 'selected' : '' ?>>全部记录</option>
                                    <option value="success" <?= $status_filter == 'success' ? 'selected' : '' ?>>✅ 成功组</option>
                                    <option value="fail" <?= $status_filter == 'fail' ? 'selected' : '' ?>>❌ 失败组</option>
                                </select>
                                <select name="sort" onchange="window.__ordersFilterChange ? window.__ordersFilterChange(this.form) : this.form.submit()"
                                    style="padding:8px 12px; border-radius:10px; border:1px solid #e2e8f0; background:white; font-weight:600;">
                                    <option value="time_desc" <?= $order_sort == 'time_desc' ? 'selected' : '' ?>>时间↓</option>
                                    <option value="time_asc" <?= $order_sort == 'time_asc' ? 'selected' : '' ?>>时间↑</option>
                                    <option value="amt_desc" <?= $order_sort == 'amt_desc' ? 'selected' : '' ?>>金额↓</option>
                                    <option value="amt_asc" <?= $order_sort == 'amt_asc' ? 'selected' : '' ?>>金额↑</option>
                                    <option value="attempts_desc" <?= $order_sort == 'attempts_desc' ? 'selected' : '' ?>>尝试次数↓</option>
                                    <option value="attempts_asc" <?= $order_sort == 'attempts_asc' ? 'selected' : '' ?>>尝试次数↑</option>
                                </select>
                                <label style="font-size:13px; color:#475569; display:flex; align-items:center; gap:4px;">
                                    <input type="checkbox" name="amount_nonzero" value="1" onchange="window.__ordersFilterChange ? window.__ordersFilterChange(this.form) : this.form.submit()" <?= $amount_nonzero ? 'checked' : '' ?>>
                                    仅显示金额非零
                                </label>
                                <label style="font-size:13px; color:#475569; display:flex; align-items:center; gap:4px;">
                                    <input type="checkbox" name="group_by_domain" value="1" onchange="window.__ordersFilterChange ? window.__ordersFilterChange(this.form) : this.form.submit()" <?= $group_by_domain ? 'checked' : '' ?>>
                                    按站点分组折叠
                                </label>
                            </form>
                        </div>
                    </div>

                    <div class="order-list" id="orderListContainer"><?= render_order_list_items($analysis_data, $group_by_domain, $order_sort, $status_filter) ?></div>
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
                                            if ($pretty !== false) {
                                                $pretty = str_replace('\\', '', $pretty);
                                            }
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
        (function() {
            function updateStickyOffsets() {
                const headerEl = document.querySelector('header');
                const filterBarEl = document.getElementById('orderFilterBar');
                if (!headerEl) return;

                if (window.matchMedia && window.matchMedia('(min-width: 900px)').matches === false) {
                    document.documentElement.style.removeProperty('--sticky-filter-top');
                    document.documentElement.style.removeProperty('--sticky-side-top');
                    return;
                }

                const headerRect = headerEl.getBoundingClientRect();
                const headerH = headerRect.height || 0;
                const gap = 0;
                document.documentElement.style.setProperty('--sticky-filter-top', (Math.round(headerH + gap)) + 'px');

                if (filterBarEl) {
                    const filterInner = filterBarEl.querySelector('.order-filter-inner');
                    const filterH = (filterInner ? filterInner.getBoundingClientRect().height : filterBarEl.getBoundingClientRect().height) || 0;
                    document.documentElement.style.setProperty('--sticky-side-top', (Math.round(headerH + filterH + 16)) + 'px');
                } else {
                    document.documentElement.style.setProperty('--sticky-side-top', (Math.round(headerH + 16)) + 'px');
                }
            }
            window.addEventListener('resize', updateStickyOffsets);
            document.addEventListener('DOMContentLoaded', updateStickyOffsets);
            updateStickyOffsets();
        })();
        (function() {
            function isMobile() {
                return window.matchMedia && window.matchMedia('(max-width: 899px)').matches;
            }

            function ensureMobileFilterUI() {
                if (!isMobile()) {
                    const fab = document.getElementById('mobileFilterFab');
                    const sheet = document.getElementById('mobileFilterSheet');
                    if (fab) fab.classList.remove('is-visible');
                    if (sheet) sheet.classList.remove('is-open');
                    return;
                }
                if (!document.getElementById('mobileFilterFab')) {
                    const fab = document.createElement('button');
                    fab.type = 'button';
                    fab.id = 'mobileFilterFab';
                    fab.textContent = '筛选';
                    document.body.appendChild(fab);
                }
                if (!document.getElementById('mobileFilterSheet')) {
                    const sheet = document.createElement('div');
                    sheet.id = 'mobileFilterSheet';
                    sheet.innerHTML = "<div class='sheet-backdrop'></div><div class='sheet-panel'><div class='sheet-header'><div class='sheet-title'>筛选 / 排序</div><button type='button' class='sheet-close'>关闭</button></div><div class='sheet-body'></div></div>";
                    document.body.appendChild(sheet);
                }
            }

            function syncFormIntoSheet() {
                const sheet = document.getElementById('mobileFilterSheet');
                if (!sheet) return;
                const body = sheet.querySelector('.sheet-body');
                if (!body) return;
                const form = document.getElementById('orderFilterForm');
                if (!form) return;
                body.innerHTML = '';
                body.appendChild(form);
            }

            function restoreFormBack() {
                const filterBar = document.getElementById('orderFilterBar');
                if (!filterBar) return;
                const inner = filterBar.querySelector('.order-filter-inner');
                if (!inner) return;
                const form = document.getElementById('orderFilterForm');
                if (!form) return;
                if (form.parentElement !== inner) {
                    inner.appendChild(form);
                }
            }

            function setSheetOpen(open) {
                const sheet = document.getElementById('mobileFilterSheet');
                if (!sheet) return;
                if (open) {
                    syncFormIntoSheet();
                    sheet.classList.add('is-open');
                } else {
                    sheet.classList.remove('is-open');
                    restoreFormBack();
                }
            }

            function setFabVisible(visible) {
                const fab = document.getElementById('mobileFilterFab');
                if (!fab) return;
                if (visible) fab.classList.add('is-visible');
                else fab.classList.remove('is-visible');
            }

            function init() {
                ensureMobileFilterUI();
                setFabVisible(false);

                const fab = document.getElementById('mobileFilterFab');
                const sheet = document.getElementById('mobileFilterSheet');
                if (!fab || !sheet) return;

                fab.addEventListener('click', function(e) {
                    e.preventDefault();
                    setSheetOpen(true);
                });

                sheet.addEventListener('click', function(e) {
                    if (e.target && (e.target.classList.contains('sheet-backdrop') || e.target.classList.contains('sheet-close'))) {
                        e.preventDefault();
                        setSheetOpen(false);
                    }
                });

                document.addEventListener('keydown', function(e) {
                    if (!isMobile()) return;
                    if (e.key === 'Escape') setSheetOpen(false);
                });
            }

            let lastY = window.scrollY;
            window.addEventListener('scroll', function() {
                if (!isMobile()) return;
                const sheet = document.getElementById('mobileFilterSheet');
                if (sheet && sheet.classList.contains('is-open')) return;
                const y = window.scrollY;
                const delta = Math.abs(y - lastY);
                lastY = y;
                if (delta < 10) return;
                setFabVisible(true);
            }, { passive: true });

            window.addEventListener('resize', function() {
                ensureMobileFilterUI();
                if (!isMobile()) {
                    restoreFormBack();
                }
            });

            init();
        })();
        (function() {
            const headerEl = document.querySelector('header');
            const collapseBtn = document.getElementById('headerCollapseBtn');
            const expandBtn = document.getElementById('headerExpandBtn');

            if (!headerEl || !collapseBtn || !expandBtn) return;

            function setCollapsed(isCollapsed) {
                if (isCollapsed) {
                    headerEl.classList.add('is-collapsed');
                    expandBtn.style.display = 'block';
                    collapseBtn.innerText = '展开';
                    collapseBtn.setAttribute('title', '展开页眉');
                    collapseBtn.setAttribute('aria-label', '展开页眉');
                } else {
                    headerEl.classList.remove('is-collapsed');
                    expandBtn.style.display = 'none';
                    collapseBtn.innerText = '收起';
                    collapseBtn.setAttribute('title', '收起页眉');
                    collapseBtn.setAttribute('aria-label', '收起页眉');
                }
                try { localStorage.setItem('orders_header_collapsed', isCollapsed ? '1' : '0'); } catch (e) {}

                setTimeout(function() {
                    if (typeof window.dispatchEvent === 'function') {
                        window.dispatchEvent(new Event('resize'));
                    }
                }, 0);
            }

            function getCollapsed() {
                try { return localStorage.getItem('orders_header_collapsed') === '1'; } catch (e) { return false; }
            }

            setCollapsed(getCollapsed());

            collapseBtn.addEventListener('click', function() {
                setCollapsed(!headerEl.classList.contains('is-collapsed'));
            });
            expandBtn.addEventListener('click', function() {
                setCollapsed(false);
            });
        })();
        (function() {
            function copyText(text) {
                if (navigator.clipboard && window.isSecureContext) {
                    return navigator.clipboard.writeText(text);
                }
                return new Promise(function(resolve, reject) {
                    try {
                        var textarea = document.createElement('textarea');
                        textarea.value = text;
                        textarea.setAttribute('readonly', '');
                        textarea.style.position = 'fixed';
                        textarea.style.top = '-9999px';
                        document.body.appendChild(textarea);
                        textarea.select();
                        var ok = document.execCommand('copy');
                        document.body.removeChild(textarea);
                        ok ? resolve() : reject(new Error('copy_failed'));
                    } catch (e) {
                        reject(e);
                    }
                });
            }

            document.addEventListener('click', function(e) {
                var btn = e.target && e.target.closest ? e.target.closest('.copy-domain-btn[data-copy-domain]') : null;
                if (!btn) return;
                e.preventDefault();
                e.stopPropagation();
                var domain = btn.getAttribute('data-copy-domain') || '';
                if (!domain) return;
                var oldText = btn.innerText;
                copyText(domain).then(function() {
                    btn.innerText = '已复制';
                    setTimeout(function() { btn.innerText = oldText; }, 900);
                }).catch(function() {
                    btn.innerText = '失败';
                    setTimeout(function() { btn.innerText = oldText; }, 900);
                });
            }, true);
        })();
        (function() {
            let controller = null;
            window.__ordersFilterChange = function(form) {
                const container = document.getElementById('orderListContainer');
                if (!container || !form) {
                    form && form.submit();
                    return;
                }

                const openedState = {
                    ids: Array.from(container.querySelectorAll('[id]'))
                        .filter(function(el) {
                            if (!el || !el.id) return false;
                            if (!/^log_/.test(el.id) && !/^group_/.test(el.id) && !/^order_group_/.test(el.id)) return false;
                            return el.style && el.style.display === 'block';
                        })
                        .map(function(el) { return el.id; })
                };
                const url = new URL(window.location.href);
                const fd = new FormData(form);

                const token = fd.get('token');
                const date = fd.get('date');
                const status = fd.get('status') || 'all';
                const sort = fd.get('sort') || 'time_desc';
                const groupByDomain = !!fd.get('group_by_domain');

                const isJumpStatus = (status === 'success' || status === 'fail');
                const shouldJump = (!groupByDomain) && isJumpStatus && (window.event && window.event.target && window.event.target.name === 'status');

                if (token) url.searchParams.set('token', token);
                if (date) url.searchParams.set('date', date);
                url.searchParams.set('mode', 'analysis');
                url.searchParams.set('status', status);
                url.searchParams.set('sort', sort);

                if (fd.get('amount_nonzero')) url.searchParams.set('amount_nonzero', '1');
                else url.searchParams.delete('amount_nonzero');

                if (fd.get('group_by_domain')) url.searchParams.set('group_by_domain', '1');
                else url.searchParams.delete('group_by_domain');

                const fetchUrl = new URL(url.toString());
                fetchUrl.searchParams.set('partial', 'order_list');
                if ((!groupByDomain) && isJumpStatus) fetchUrl.searchParams.set('status', 'all');

                if (controller) controller.abort();
                controller = new AbortController();
                container.style.opacity = '0.6';

                fetch(fetchUrl.toString(), {
                    method: 'GET',
                    headers: { 'X-Requested-With': 'fetch' },
                    signal: controller.signal
                })
                .then(function(res) {
                    if (!res.ok) throw new Error('bad_status');
                    return res.text();
                })
                .then(function(html) {
                    container.innerHTML = html;

                    if (openedState && openedState.ids && openedState.ids.length) {
                        openedState.ids.forEach(function(id) {
                            const el = document.getElementById(id);
                            if (el) {
                                el.style.display = 'block';
                            }
                        });
                    }

                    const cleanUrl = new URL(url.toString());
                    cleanUrl.searchParams.delete('partial');
                    history.replaceState(null, '', cleanUrl.toString());

                    if (shouldJump) {
                        const groupId = 'order_group_' + status;
                        const groupEl = document.getElementById(groupId);
                        if (groupEl) {
                            groupEl.style.display = 'block';
                            const wrapper = document.getElementById(groupId + '_wrap') || groupEl.closest('.order-item') || groupEl;

                            const headerEl = document.querySelector('header');
                            const filterBarEl = document.getElementById('orderFilterBar');
                            let offset = 0;
                            if (window.matchMedia && window.matchMedia('(min-width: 900px)').matches) {
                                if (headerEl) offset += headerEl.getBoundingClientRect().height || 0;
                                if (filterBarEl) {
                                    const inner = filterBarEl.querySelector('.order-filter-inner');
                                    offset += (inner ? inner.getBoundingClientRect().height : filterBarEl.getBoundingClientRect().height) || 0;
                                }
                                offset += 12;
                            }
                            const rect = wrapper.getBoundingClientRect();
                            const targetY = window.scrollY + rect.top - offset;
                            window.scrollTo({ top: Math.max(0, targetY), behavior: 'smooth' });
                        }
                    }
                })
                .catch(function(err) {
                    if (err && err.name === 'AbortError') return;
                    location.href = url.toString();
                })
                .finally(function() {
                    container.style.opacity = '1';
                });
            };
        })();
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

        function escapeHtml(str) {
            return String(str)
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;')
                .replace(/'/g, '&#039;');
        }

        function highlightLogHtml(line) {
            let s = escapeHtml(line);
            s = s.replace(/(\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2})/g, '<span style="color:#ce9178;">$1</span>');
            s = s.replace(/(&quot;\w+&quot;):/g, '<span style="color:#9cdcfe;">$1</span>:');
            s = s.replace(/(https?:\/\/[^\s\|]+)/g, '<span style="color:#4fc1ff;text-decoration:underline;">$1</span>');
            return s;
        }

        function toggleLog(id) {
            const el = document.getElementById(id);
            const isOpening = el.style.display !== 'block';
            el.style.display = isOpening ? 'block' : 'none';

            if (isOpening && !el.dataset.optimized) {
                el.querySelectorAll('.log-content[data-json-auto="true"]').forEach(container => {
                    const originalText = container.innerText;
                    const lines = originalText.split(/\r?\n/);
                    const htmlLines = [];

                    for (const line of lines) {
                        if (!line) {
                            htmlLines.push('');
                            continue;
                        }

                        const jsonStart = line.indexOf('{');
                        if (jsonStart === -1) {
                            htmlLines.push(highlightLogHtml(line));
                            continue;
                        }

                        const prefix = line.slice(0, jsonStart);
                        const jsonPart = line.slice(jsonStart);

                        let parsed = null;
                        try {
                            parsed = JSON.parse(jsonPart);
                        } catch (e1) {
                            try {
                                const fixed = jsonPart.replace(/\\"/g, '"').replace(/\\\\/g, '\\');
                                parsed = JSON.parse(fixed);
                            } catch (e2) {
                                parsed = null;
                            }
                        }

                        if (parsed) {
                            const formatted = JSON.stringify(parsed, null, 4);
                            const prettyHtml = "\n<span style='color:#4ade80;font-weight:bold;'>[自动美化 JSON]:</span>\n<pre style='color:#4ade80;margin:5px 0 0 0; font-family:inherit;'>" + escapeHtml(formatted) + "</pre>";
                            htmlLines.push(highlightLogHtml(prefix) + prettyHtml);
                        } else {
                            htmlLines.push(highlightLogHtml(line));
                        }
                    }

                    container.innerHTML = htmlLines.join("\n");
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

    <style>
        @media (max-width: 899px) {
            #float-nav {
                right: calc(4px + env(safe-area-inset-right, 0px)) !important;
                bottom: calc(6px + env(safe-area-inset-bottom, 0px)) !important;
                gap: 8px !important;
            }
            #float-nav button {
                width: 20px !important;
                height: 20px !important;
                font-size: 10px !important;
                box-shadow: 0 2px 8px rgba(0,0,0,0.12) !important;
            }
        }
    </style>

</body>

</html>