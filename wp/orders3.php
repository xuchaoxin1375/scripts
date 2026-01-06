<?php
// ====== 配置与权限控制 ======
// v1.0.20260105.2
$access_token = 'cxxu';
$current_token = $_GET['token'] ?? '';
if ($current_token !== $access_token) {
    http_response_code(403);
    die('403 Forbidden');
}

function find_available_log_date_range()
{
    $log_files_list = glob("*success.log");
    $all_dates = [];
    foreach (($log_files_list ?? []) as $file) {
        if (preg_match('/^(\d{4}-\d{2}-\d{2})success\.log$/', $file, $m)) {
            $all_dates[] = $m[1];
        }
    }
    sort($all_dates);
    $min_date = $all_dates[0] ?? date('Y-m-d');
    $max_date = $all_dates[count($all_dates) - 1] ?? date('Y-m-d');
    return [$min_date, $max_date];
}

function validate_date_range($range_start, $range_end, $min_date, $max_date)
{
    $rs = trim((string)$range_start);
    $re = trim((string)$range_end);
    if ($rs === '' || $re === '') {
        return '请选择开始/结束日期';
    }
    if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $rs) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $re)) {
        return '日期格式不正确';
    }
    if ($rs > $re) {
        return '开始日期不能晚于结束日期';
    }
    if ($rs < $min_date || $re > $max_date) {
        return '日期范围不在可用区间内：' . $min_date . ' ~ ' . $max_date;
    }
    return '';
}

function compute_range_revenue_days($range_start, $range_end)
{
    $revenue_days = [];
    $cur = strtotime($range_start);
    $end = strtotime($range_end);
    while ($cur <= $end) {
        $date = date('Y-m-d', $cur);
        $success_file = $date . 'success.log';
        $notify_file = $date . 'notify.log';
        $forpay_new_file = $date . 'forpay_new.log';
        $forpay_file = $date . 'forpay.log';
        $usd_sum = 0;
        $success_orders_map = [];
        $total_orders = 0;
        $attempts_cnt = 0;
        // 以 forpay_new 中的唯一订单号作为当日订单总量
        $order_set = [];
        if (file_exists($forpay_new_file)) {
            $lines = file($forpay_new_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            foreach ($lines as $line) {
                if (preg_match('/\\|(\\d+)\\|/', $line, $m)) {
                    $order_set[$m[1]] = true;
                }
            }
            $total_orders = count($order_set);
        }

        // forpay.log：统计当日总尝试次数（仅统计属于当日订单集合的记录）
        if (file_exists($forpay_file) && !empty($order_set)) {
            $lines = file($forpay_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            foreach ($lines as $line) {
                if (preg_match('/\\|(\\d+)\\|/', $line, $m)) {
                    if (isset($order_set[$m[1]])) {
                        $attempts_cnt++;
                    }
                }
            }
        }

        if (file_exists($success_file)) {
            $lines = file($success_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            if (!empty($lines)) $lines = array_values(array_unique($lines));
            foreach ($lines as $line) {
                if (preg_match('/order_no=(\d+)/', $line, $m)) {
                    $success_orders_map[$m[1]] = true;
                }
            }
        }
        // 为 usd 汇总使用的可变副本
        $success_orders_for_usd = $success_orders_map;
        if (file_exists($notify_file) && !empty($success_orders_for_usd)) {
            $lines = file($notify_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            foreach ($lines as $line) {
                if (preg_match('/"order_no":"(\d+)"/', $line, $m)) {
                    $current_order_no = $m[1];
                    if (!isset($success_orders_for_usd[$current_order_no])) continue;
                    unset($success_orders_for_usd[$current_order_no]);
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
        $success_cnt = count($success_orders_map);
        $conv = ($total_orders > 0) ? round(($success_cnt / $total_orders) * 100, 2) : 0;
        $revenue_days[] = [
            'date' => $date,
            'usd' => round($usd_sum, 2),
            'conversion' => $conv,
            'total_orders' => $total_orders,
            'success_orders' => $success_cnt,
            'attempts' => $attempts_cnt,
        ];
        $cur = strtotime('+1 day', $cur);
    }
    return $revenue_days;
}

function export_orders_csv_range($access_token, $range_start, $range_end, $status_filter, $owner_filter, $amount_nonzero, $csv_selected)
{
    [$min_date0, $max_date0] = find_available_log_date_range();
    $range_error0 = validate_date_range($range_start, $range_end, $min_date0, $max_date0);
    if ($range_error0 !== '') {
        header('Content-Type: text/plain; charset=UTF-8');
        echo $range_error0;
        return;
    }

    $csv_files = list_csv_files_in_dir(__DIR__);
    $csv_path = resolve_selected_csv_path(__DIR__, $csv_selected, $csv_files);
    $csv_data = load_domain_owner_map_from_csv($csv_path);
    $domain_owner_map = $csv_data['map'] ?? [];

    $filename = 'orders_' . $range_start . '_to_' . $range_end . '.csv';
    header('Content-Type: text/csv; charset=UTF-8');
    header('Content-Disposition: attachment; filename="' . $filename . '"');
    header('Pragma: no-cache');
    header('Expires: 0');

    $out = fopen('php://output', 'w');
    if (!$out) {
        echo "cannot_open_output";
        return;
    }
    fwrite($out, "\xEF\xBB\xBF");

    $headers = [
        'log_date',
        'order_no',
        'time',
        'hour',
        'domain',
        'is_success',
        'attempts',
        'notify_count',
        'amount',
        'currency',
        'usd_amount',
        'error',
        'notify_errors',
        'people',
        'country',
        'category',
        'site_date',
        'csv_file',
    ];
    fputcsv($out, $headers);

    $cur = strtotime($range_start);
    $end = strtotime($range_end);
    while ($cur <= $end) {
        $date = date('Y-m-d', $cur);

        $analysis_data = [];
        $stats_stub = [
            'hourly_attempts' => array_fill(0, 24, 0),
            'hourly_success' => array_fill(0, 24, 0),
        ];

        $log_files = [
            'forpay_new' => $date . 'forpay_new.log',
            'forpay' => $date . 'forpay.log',
            'notify' => $date . 'notify.log',
            'success' => $date . 'success.log',
        ];

        $logs = [];
        foreach ($log_files as $type => $file) {
            $lines = file_exists($file) ? file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) : [];
            if ($type === 'success' && !empty($lines)) {
                $lines = array_values(array_unique($lines));
            }
            $logs[$type] = $lines;
        }

        foreach ($logs['forpay_new'] as $line) {
            if (preg_match('/^(\d{4}-\d{2}-\d{2}\s(\d{2}):\d{2}:\d{2})\|(.*?)\|(\d+)\|/', $line, $m)) {
                $order_no = $m[4];
                $hour = (int)$m[2];
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
                    $stats_stub['hourly_attempts'][$analysis_data[$no]['hour']]++;
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
                if (!isset($analysis_data[$no])) continue;
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
                    $item_ref['details']['err'] = '尝试中出现过的错误类型: ' . implode(' | ', $uniq);
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
                    $stats_stub['hourly_success'][$analysis_data[$no]['hour']]++;
                }
            }
        }

        foreach ($analysis_data as $no => $item) {
            if ($amount_nonzero && (empty($item['details']['amt']) || $item['details']['amt'] == 0)) {
                continue;
            }
            if ($status_filter === 'success' && empty($item['is_success'])) {
                continue;
            }
            if ($status_filter === 'fail' && !empty($item['is_success'])) {
                continue;
            }

            $dom_key = normalize_domain_key($item['domain'] ?? '');
            $owner = ($dom_key !== '' && isset($domain_owner_map[$dom_key])) ? $domain_owner_map[$dom_key] : null;
            $people = $owner ? trim((string)($owner['people'] ?? '')) : '';
            if (!owner_match_filter($people, $owner_filter)) {
                continue;
            }
            $country = $owner ? trim((string)($owner['country'] ?? '')) : '';
            $category = $owner ? trim((string)($owner['category'] ?? '')) : '';
            $site_date = $owner ? trim((string)($owner['date'] ?? '')) : '';

            $row = [
                $date,
                (string)$no,
                (string)($item['time'] ?? ''),
                (string)($item['hour'] ?? ''),
                (string)($item['domain'] ?? ''),
                (!empty($item['is_success']) ? '1' : '0'),
                (string)($item['attempts'] ?? 0),
                (string)($item['details']['notify_count'] ?? 0),
                (string)($item['details']['amt'] ?? 0),
                (string)($item['details']['cur'] ?? ''),
                (string)($item['details']['usd_amt'] ?? 0),
                (string)($item['details']['err'] ?? ''),
                is_array($item['details']['notify_errors'] ?? null) ? implode(' | ', $item['details']['notify_errors']) : '',
                $people,
                $country,
                $category,
                $site_date,
                ($csv_path ? basename($csv_path) : ''),
            ];
            fputcsv($out, $row);
        }

        $cur = strtotime('+1 day', $cur);
    }

    fclose($out);
}

function render_range_revenue_module($access_token, $view_mode, $range_start, $range_end, $min_date, $max_date, $revenue_days, $range_error)
{
    ob_start();
    ?>
    <div class="chart-container" id="revenueChartContainer" style="height: auto;" data-collapsible-card="range_revenue">
        <div class="collapsible-card-header" data-collapsible-card-header style="display:flex; align-items:center; justify-content:space-between; margin-bottom:8px; gap:10px; flex-wrap:wrap;">
            <span style="font-size:15px; font-weight:600; color:#6366f1;">📈 区间营收统计</span>
            <button type="button" class="collapsible-card-toggle" data-collapsible-card-toggle>收起</button>
        </div>
        <div class="collapsible-card-body" data-collapsible-card-body>
            <form method="get" id="rangeRevenueForm" class="range-revenue-form" style="display:flex; align-items:center; gap:8px; flex-wrap:wrap; margin-bottom:8px;">
                <input type="hidden" name="token" value="<?= htmlspecialchars($access_token) ?>">
                <input type="hidden" name="mode" value="<?= htmlspecialchars($view_mode) ?>">
                <div class="range-revenue-row">
                    <span class="range-revenue-title">区间:</span>
                    <input type="date" name="range_start" value="<?= htmlspecialchars($range_start) ?>" min="<?= htmlspecialchars($min_date) ?>" max="<?= htmlspecialchars($max_date) ?>" class="range-revenue-date">
                    <span class="range-revenue-tilde">~</span>
                    <input type="date" name="range_end" value="<?= htmlspecialchars($range_end ?: date('Y-m-d')) ?>" min="<?= htmlspecialchars($min_date) ?>" max="<?= htmlspecialchars($max_date) ?>" class="range-revenue-date">
                </div>

                <button type="submit" class="range-revenue-btn">查询</button>
                <span id="rangeLabel" class="range-revenue-label"></span>

                <div class="range-revenue-sliders">
                    <input type="range" min="0" max="100" value="0" id="rangeStartSlider" style="flex:1;">
                    <input type="range" min="0" max="100" value="100" id="rangeEndSlider" style="flex:1;">
                </div>
            </form>
            <?php if ($range_error !== ''): ?>
                <div id="rangeRevenueError" style="background:#fff7ed; border:1px solid #fdba74; color:#9a3412; padding:10px 12px; border-radius:10px; font-size:13px; margin-bottom:10px;">
                    <?= htmlspecialchars($range_error) ?>
                </div>
            <?php else: ?>
                <div id="rangeRevenueError" style="display:none;"></div>
            <?php endif; ?>
            <div style="width:100%; height:180px; min-height:180px;">
                <canvas id="revenueChart" style="width:100%; height:180px; min-height:180px;"></canvas>
            </div>
        </div>
    </div>
    <script>
        window.__rangeRevenueData = <?php echo json_encode($revenue_days, JSON_UNESCAPED_UNICODE); ?>;
        window.__rangeRevenueMeta = <?php echo json_encode([
            'min_date' => $min_date,
            'max_date' => $max_date,
            'range_start' => $range_start,
            'range_end' => $range_end,
            'range_error' => $range_error,
        ], JSON_UNESCAPED_UNICODE); ?>;
    </script>
    <?php
    return ob_get_clean();
}

function get_current_range_from_query_or_default($log_date)
{
    [$min_date, $max_date] = find_available_log_date_range();
    if (isset($_GET['range_start']) && isset($_GET['range_end'])) {
        $range_start = (string)$_GET['range_start'];
        $range_end = (string)$_GET['range_end'];
    } else {
        $center_ts = strtotime($log_date);
        $range_start = date('Y-m-d', strtotime('-5 days', $center_ts));
        $range_end = date('Y-m-d', strtotime('+5 days', $center_ts));
        if ($range_start < $min_date) $range_start = $min_date;
        if ($range_end > $max_date) $range_end = $max_date;
    }
    return [$range_start, $range_end, $min_date, $max_date];
}

function render_analysis_content($access_token, $view_mode, $log_date, $stats, $analysis_data, $group_by_domain, $order_sort, $status_filter, $owner_filter, $csv_selected)
{
    ob_start();
    ?>
    <script>
        window.__ordersFocusDate = <?php echo json_encode($log_date, JSON_UNESCAPED_UNICODE); ?>;
        window.__hourlyChartData = <?php echo json_encode([
            'attempts' => array_values($stats['hourly_attempts'] ?? []),
            'success' => array_values($stats['hourly_success'] ?? []),
        ], JSON_UNESCAPED_UNICODE); ?>;
    </script>
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

            <?php
            [$range_start, $range_end, $min_date, $max_date] = get_current_range_from_query_or_default($log_date);
            $range_error = validate_date_range($range_start, $range_end, $min_date, $max_date);
            $revenue_days = [];
            if ($range_error === '') {
                $revenue_days = compute_range_revenue_days($range_start, $range_end);
            }
            ?>

            <?= render_range_revenue_module($access_token, $view_mode, $range_start, $range_end, $min_date, $max_date, $revenue_days, $range_error) ?>


        <div class="main-layout">
            <aside class="side-panel">
                <?php
                $csv_files = list_csv_files_in_dir(__DIR__);
                $csv_path = resolve_selected_csv_path(__DIR__, $csv_selected, $csv_files);
                $csv_data_for_side = load_domain_owner_map_from_csv($csv_path);
                $people_stats = build_people_stats($analysis_data, $csv_data_for_side['map'] ?? []);
                $people_has_people = (bool)($csv_data_for_side['meta']['has_people'] ?? false);
                $people_has_country = (bool)($csv_data_for_side['meta']['has_country'] ?? false);
                $people_list_for_filter = list_people_from_domain_map($csv_data_for_side['map'] ?? []);
                ?>
                <?php if ($people_has_people): ?>
                    <div class="overview-card" style="height: auto; margin-bottom: 12px;" data-collapsible-card="people_summary">
                        <div class="collapsible-card-header" data-collapsible-card-header>
                            <h3 style="margin:0; font-size:16px; display:flex; align-items:center; gap:8px;">
                                <span style="background:#ffe6e5; color:white; padding:4px; border-radius:6px;">👤</span>
                                人员业绩汇总
                            </h3>
                            <button type="button" class="collapsible-card-toggle" data-collapsible-card-toggle>收起</button>
                        </div>
                        <div class="collapsible-card-body" data-collapsible-card-body>
                            <div style="color:#64748b; font-size:12px; margin-bottom:8px;">
                                映射来源: <?= $csv_path ? htmlspecialchars(basename($csv_path)) : '未选择' ?> · 未匹配订单: <?= (int)($people_stats['unmapped_orders'] ?? 0) ?>
                            </div>
                            <ul class="ranking-list">
                            <?php if (empty($people_stats['people'])): ?>
                                <li style="color:#94a3b8; font-size:13px; text-align:center; padding:20px;">暂无人员数据</li>
                            <?php endif; ?>
                            <?php foreach (($people_stats['people'] ?? []) as $pname => $p): ?>
                                <li class="ranking-item" style="align-items:flex-start; gap:10px;">
                                    <div style="min-width:0;">
                                        <div class="dom-name" style="max-width: 220px;" title="<?= htmlspecialchars($pname) ?>"><?= htmlspecialchars($pname) ?></div>
                                        <div style="font-size:12px; color:#94a3b8; margin-top:4px;">
                                            总订单: <?= (int)($p['orders_total'] ?? 0) ?> · 成功: <?= (int)($p['orders_success'] ?? 0) ?>
                                            <?php if ($people_has_country && !empty($p['countries'])): ?>
                                                · <?= htmlspecialchars(implode(',', $p['countries'])) ?>
                                            <?php endif; ?>
                                        </div>
                                    </div>
                                    <div style="text-align:right;">
                                        <div class="dom-val">$<?= format_money((float)($p['usd_sum_success'] ?? 0)) ?></div>
                                        <div style="font-size:11px; color:#94a3b8;">成功USD合计</div>
                                    </div>
                                </li>
                            <?php endforeach; ?>
                            </ul>
                        </div>
                    </div>
                <?php endif; ?>

                <div class="overview-card" style="height: auto;" data-collapsible-card="domain_revenue">
                    <div class="collapsible-card-header" data-collapsible-card-header>
                        <h3 style="margin:0; font-size:16px; display:flex; align-items:center; gap:8px;">
                            <span style="background:var(--primary); color:white; padding:4px; border-radius:6px;">💰</span>
                            站点营收排行
                        </h3>
                        <button type="button" class="collapsible-card-toggle" data-collapsible-card-toggle>收起</button>
                    </div>
                    <div class="collapsible-card-body" data-collapsible-card-body>
                        <ul class="ranking-list">
                        <?php if (empty($stats['domain_amount'])): ?>
                            <li style="color:#94a3b8; font-size:13px; text-align:center; padding:20px;">今日暂无成交</li>
                        <?php endif; ?>
                        <?php $rank_i = 1; foreach ($stats['domain_amount'] as $dom => $currs): ?>
                            <li class="ranking-item">
                                <div style="display:flex; align-items:center; gap:10px; min-width:0; flex:1;">
                                    <span class="rank-num"><?= $rank_i ?></span>
                                    <span class="dom-name" style="max-width: 300px;" title="<?= htmlspecialchars($dom) ?>"><?= htmlspecialchars($dom) ?></span>
                                </div>
                                <div style="text-align:right;">
                                    <?php foreach ($currs as $c => $v): ?>
                                        <div class="dom-val"><?= $c ?>             <?= format_money($v) ?></div>
                                    <?php endforeach; ?>
                                </div>
                            </li>
                        <?php $rank_i++; endforeach; ?>
                        </ul>
                    </div>
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
                            <select name="list_view" onchange="window.__ordersFilterChange ? window.__ordersFilterChange(this.form) : this.form.submit()"
                                style="padding:8px 12px; border-radius:10px; border:1px solid #e2e8f0; background:white; font-weight:600;">
                                <option value="card" <?= $list_view === 'card' ? 'selected' : '' ?>>卡片视图</option>
                                <option value="table" <?= $list_view === 'table' ? 'selected' : '' ?>>表格视图</option>
                            </select>
                            <?php if (!empty($csv_files)): ?>
                                <select name="csv_file" onchange="window.__ordersFilterChange ? window.__ordersFilterChange(this.form) : this.form.submit()"
                                    style="padding:8px 12px; border-radius:10px; border:1px solid #e2e8f0; background:white; font-weight:600;">
                                    <?php foreach ($csv_files as $f): ?>
                                        <option value="<?= htmlspecialchars($f) ?>" <?= ($csv_selected === '' ? ($f === basename($csv_path)) : ($csv_selected === $f)) ? 'selected' : '' ?>><?= htmlspecialchars($f) ?></option>
                                    <?php endforeach; ?>
                                </select>
                            <?php endif; ?>
                            <?php if (!empty($people_list_for_filter)): ?>
                                <select name="owner" onchange="window.__ordersFilterChange ? window.__ordersFilterChange(this.form) : this.form.submit()"
                                    style="padding:8px 12px; border-radius:10px; border:1px solid #e2e8f0; background:white; font-weight:600;">
                                    <option value="" <?= $owner_filter === '' ? 'selected' : '' ?>>全部人员</option>
                                    <option value="__unmatched__" <?= $owner_filter === '__unmatched__' ? 'selected' : '' ?>>未匹配</option>
                                    <?php foreach ($people_list_for_filter as $pname): ?>
                                        <option value="<?= htmlspecialchars($pname) ?>" <?= $owner_filter === $pname ? 'selected' : '' ?>><?= htmlspecialchars($pname) ?></option>
                                    <?php endforeach; ?>
                                </select>
                            <?php endif; ?>
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
                                <option value="site_date_desc" <?= $order_sort == 'site_date_desc' ? 'selected' : '' ?>>建站日期↓</option>
                                <option value="site_date_asc" <?= $order_sort == 'site_date_asc' ? 'selected' : '' ?>>建站日期↑</option>
                                <option value="amt_desc" <?= $order_sort == 'amt_desc' ? 'selected' : '' ?>>金额↓</option>
                                <option value="amt_asc" <?= $order_sort == 'amt_asc' ? 'selected' : '' ?>>金额↑</option>
                                <option value="attempts_desc" <?= $order_sort == 'attempts_desc' ? 'selected' : '' ?>>尝试次数↓</option>
                                <option value="attempts_asc" <?= $order_sort == 'attempts_asc' ? 'selected' : '' ?>>尝试次数↑</option>
                            </select>

                            <span class="filter-break" style="flex-basis:100%; height:0;"></span>
                            <label style="font-size:13px; color:#475569; display:flex; align-items:center; gap:4px;">
                                <input type="checkbox" name="amount_nonzero" value="1" onchange="window.__ordersFilterChange ? window.__ordersFilterChange(this.form) : this.form.submit()" <?= (isset($_GET['amount_nonzero']) && $_GET['amount_nonzero']) ? 'checked' : '' ?>>
                                仅显示金额非零
                            </label>
                            <label style="font-size:13px; color:#475569; display:flex; align-items:center; gap:4px;">
                                <input type="checkbox" name="group_by_domain" value="1" onchange="window.__ordersFilterChange ? window.__ordersFilterChange(this.form) : this.form.submit()" <?= (isset($_GET['group_by_domain']) && $_GET['group_by_domain']) ? 'checked' : '' ?>>
                                按站点分组折叠
                            </label>
                        </form>
                    </div>
                </div>

                <div class="order-list" id="orderListContainer"><?= render_order_list_items($analysis_data, $group_by_domain, $order_sort, $status_filter, $owner_filter, $csv_path, $list_view) ?></div>
            </div>


        </div>
    <?php
    return ob_get_clean();
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
$owner_filter = trim((string)($_GET['owner'] ?? ''));
$csv_selected = trim((string)($_GET['csv_file'] ?? ''));
$list_view = trim((string)($_GET['list_view'] ?? ''));
if ($list_view !== 'table' && $list_view !== 'card') {
    $list_view = 'card';
}
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
                $item_ref['details']['err'] = '尝试中出现过的错误类型: ' . implode(' | ', $uniq);
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
    // 按站点营收(USD 参考)倒序排序
    uasort($stats['domain_amount'], function ($a, $b) {
        $sum_a = 0.0;
        foreach (($a ?? []) as $cur => $v) {
            $sum_a += convert_to_usd($v, $cur);
        }
        $sum_b = 0.0;
        foreach (($b ?? []) as $cur => $v) {
            $sum_b += convert_to_usd($v, $cur);
        }
        return $sum_b <=> $sum_a;
    });
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

function normalize_domain_key($domain)
{
    $s = strtolower(trim((string)$domain));
    $s = preg_replace('/^https?:\/\//', '', $s);
    $s = preg_replace('/^www\./', '', $s);
    $s = preg_replace('/[\/#\?].*$/', '', $s);
    $s = trim($s, " \t\n\r\0\x0B.");
    return $s;
}

function normalize_header_key($s)
{
    $s = strtolower(trim((string)$s));
    // strip UTF-8 BOM / invisible prefix characters
    $s = preg_replace('/^\xEF\xBB\xBF/', '', $s);
    $s = preg_replace('/^[\x00-\x1F\x7F\x{200B}\x{FEFF}]+/u', '', $s);
    $s = preg_replace('/\s+/', '', $s);
    $s = str_replace(['（', '）', '：', ':', '-', '_', '　'], '', $s);
    return $s;
}

function find_header_index($headers, $candidates)
{
    $map = [];
    foreach ($headers as $idx => $h) {
        $map[normalize_header_key($h)] = $idx;
    }
    foreach ($candidates as $c) {
        $k = normalize_header_key($c);
        if (isset($map[$k])) {
            return $map[$k];
        }
    }
    return null;
}

function list_csv_files_in_dir($dir)
{
    $res = [];
    if (!is_dir($dir)) return $res;
    $items = scandir($dir);
    if (!is_array($items)) return $res;
    foreach ($items as $f) {
        if ($f === '.' || $f === '..') continue;
        if (!preg_match('/\.csv$/i', $f)) continue;
        $full = rtrim($dir, '/').'/'.$f;
        if (is_file($full)) {
            $res[] = $f;
        }
    }
    sort($res);
    return $res;
}

function resolve_selected_csv_path($dir, $csv_selected, $csv_files)
{
    if (is_string($csv_selected) && $csv_selected !== '') {
        foreach ($csv_files as $f) {
            if ($f === $csv_selected) {
                $full = rtrim($dir, '/').'/'.$f;
                if (is_file($full)) return $full;
            }
        }
    }
    if (!empty($csv_files)) {
        $full = rtrim($dir, '/').'/'.$csv_files[0];
        if (is_file($full)) return $full;
    }
    return '';
}

function load_domain_owner_map_from_csv($csv_file)
{
    $res = [
        'map' => [],
        'meta' => [
            'has_people' => false,
            'has_country' => false,
            'has_category' => false,
            'has_date' => false,
            'headers' => [],
            'total_rows' => 0,
            'ok_rows' => 0,
            'skipped_rows' => 0,
            'dup_domains' => 0,
        ],
    ];
    if (!is_string($csv_file) || $csv_file === '' || !file_exists($csv_file)) {
        return $res;
    }

    $fh = fopen($csv_file, 'r');
    if (!$fh) {
        return $res;
    }

    $headers = fgetcsv($fh);
    if (!is_array($headers) || empty($headers)) {
        fclose($fh);
        return $res;
    }
    $res['meta']['headers'] = $headers;

    $domain_idx = find_header_index($headers, ['域名', '网站', '站点', 'domain', 'site']);
    $people_idx = find_header_index($headers, ['数据采集员', '人员', '归属人员', '名字', '姓名', '采集员']);
    $country_idx = find_header_index($headers, ['国家', '语言', '网站语言', '站点语言', 'lang', 'country']);
    $category_idx = find_header_index($headers, ['内容', '产品类别', '产品分类', '品类', '类目', '类别', '产品', 'category', 'productcategory']);
    $date_idx = find_header_index($headers, ['完成日期','建站日期','申请日期', '日期', '创建日期', '上线日期', '完成时间', '时间', 'date', 'createdate', 'created_at', 'updated_at']);

    $res['meta']['has_people'] = ($people_idx !== null);
    $res['meta']['has_country'] = ($country_idx !== null);
    $res['meta']['has_category'] = ($category_idx !== null);
    $res['meta']['has_date'] = ($date_idx !== null);

    if ($domain_idx === null) {
        fclose($fh);
        return $res;
    }

    while (($row = fgetcsv($fh)) !== false) {
        if (!is_array($row) || empty($row)) {
            continue;
        }
        $res['meta']['total_rows']++;
        $domain_raw = $row[$domain_idx] ?? '';
        $domain_key = normalize_domain_key($domain_raw);
        if ($domain_key === '') {
            $res['meta']['skipped_rows']++;
            continue;
        }

        $people = $people_idx !== null ? trim((string)($row[$people_idx] ?? '')) : '';
        $country = $country_idx !== null ? trim((string)($row[$country_idx] ?? '')) : '';
        $category = $category_idx !== null ? trim((string)($row[$category_idx] ?? '')) : '';
        $date = $date_idx !== null ? trim((string)($row[$date_idx] ?? '')) : '';

        if (isset($res['map'][$domain_key])) {
            $res['meta']['dup_domains']++;
            if ($res['map'][$domain_key]['people'] === '' && $people !== '') {
                $res['map'][$domain_key]['people'] = $people;
            }
            if ($res['map'][$domain_key]['country'] === '' && $country !== '') {
                $res['map'][$domain_key]['country'] = $country;
            }
            if (($res['map'][$domain_key]['category'] ?? '') === '' && $category !== '') {
                $res['map'][$domain_key]['category'] = $category;
            }
            if (($res['map'][$domain_key]['date'] ?? '') === '' && $date !== '') {
                $res['map'][$domain_key]['date'] = $date;
            }
            continue;
        }

        $res['map'][$domain_key] = [
            'people' => $people,
            'country' => $country,
            'category' => $category,
            'date' => $date,
            'raw_domain' => (string)$domain_raw,
        ];
        $res['meta']['ok_rows']++;
    }
    fclose($fh);
    return $res;
}

function list_people_from_domain_map($domain_owner_map)
{
    $set = [];
    foreach (($domain_owner_map ?? []) as $dom => $info) {
        $p = trim((string)($info['people'] ?? ''));
        if ($p !== '') {
            $set[$p] = true;
        }
    }
    $arr = array_values(array_keys($set));
    sort($arr);
    return $arr;
}

function owner_match_filter($people_name, $owner_filter)
{
    $f = trim((string)$owner_filter);
    if ($f === '') return true;
    if ($f === '__unmatched__') return trim((string)$people_name) === '';
    return trim((string)$people_name) === $f;
}

function get_owner_info_for_domain($domain, $domain_owner_map)
{
    $dom_key = normalize_domain_key($domain);
    if ($dom_key === '' || !isset($domain_owner_map[$dom_key])) {
        return null;
    }
    return $domain_owner_map[$dom_key];
}

function parse_site_date_to_ts($s)
{
    $v = trim((string)$s);
    if ($v === '') return 0;
    $v = preg_replace('/[\x{200B}\x{FEFF}\s]+/u', '', $v);
    $v = str_replace(['.', '年', '月'], ['-', '-', '-'], $v);
    $v = str_replace(['日', '/'], ['', '-'], $v);
    if (preg_match('/^(\d{4})-(\d{1,2})-(\d{1,2})/', $v, $m)) {
        $y = (int)$m[1];
        $mo = (int)$m[2];
        $d = (int)$m[3];
        if ($y >= 1970 && $mo >= 1 && $mo <= 12 && $d >= 1 && $d <= 31) {
            return mktime(0, 0, 0, $mo, $d, $y);
        }
    }
    $ts = strtotime($v);
    if ($ts === false) return 0;
    return (int)$ts;
}

function build_people_stats($analysis_data, $domain_owner_map)
{
    $stats = [
        'people' => [],
        'unmapped_orders' => 0,
        'unmapped_domains' => [],
    ];
    foreach ($analysis_data as $no => $item) {
        $domain_key = normalize_domain_key($item['domain'] ?? '');
        $owner = ($domain_key !== '' && isset($domain_owner_map[$domain_key])) ? $domain_owner_map[$domain_key] : null;
        $people_name = $owner ? trim((string)($owner['people'] ?? '')) : '';
        $country = $owner ? trim((string)($owner['country'] ?? '')) : '';
        if ($people_name === '') {
            $people_name = '未归属';
        }
        if (!$owner) {
            $stats['unmapped_orders']++;
            if ($domain_key !== '') {
                $stats['unmapped_domains'][$domain_key] = true;
            }
        }
        if (!isset($stats['people'][$people_name])) {
            $stats['people'][$people_name] = [
                'orders_total' => 0,
                'orders_success' => 0,
                'usd_sum_success' => 0.0,
                'countries' => [],
            ];
        }
        $stats['people'][$people_name]['orders_total']++;
        if ($country !== '') {
            $stats['people'][$people_name]['countries'][$country] = true;
        }
        if (!empty($item['is_success'])) {
            $stats['people'][$people_name]['orders_success']++;
            $stats['people'][$people_name]['usd_sum_success'] += (float)($item['details']['usd_amt'] ?? 0);
        }
    }
    foreach ($stats['people'] as $k => &$p) {
        $p['countries'] = array_values(array_keys($p['countries']));
        sort($p['countries']);
    }
    unset($p);

    uasort($stats['people'], function ($a, $b) {
        $cmp = ($b['usd_sum_success'] <=> $a['usd_sum_success']);
        if ($cmp !== 0) return $cmp;
        return ($b['orders_success'] <=> $a['orders_success']);
    });

    $stats['unmapped_domains'] = array_values(array_keys($stats['unmapped_domains']));
    sort($stats['unmapped_domains']);
    return $stats;
}

function render_order_list_items($analysis_data, $group_by_domain, $order_sort, $status_filter, $owner_filter, $csv_path, $list_view = 'card')
{
    ob_start();
    $order_index = 1;

    $csv_data = load_domain_owner_map_from_csv($csv_path);
    $domain_owner_map = $csv_data['map'] ?? [];
    $has_people = (bool)($csv_data['meta']['has_people'] ?? false);
    $has_country = (bool)($csv_data['meta']['has_country'] ?? false);
    $has_category = (bool)($csv_data['meta']['has_category'] ?? false);
    $has_date = (bool)($csv_data['meta']['has_date'] ?? false);

    $list_view = trim((string)$list_view);
    if ($list_view !== 'table' && $list_view !== 'card') {
        $list_view = 'card';
    }

    if ($list_view === 'table') {
        $rows = [];
        foreach ($analysis_data as $no => $item) {
            if ($status_filter === 'success' && empty($item['is_success'])) {
                continue;
            }
            if ($status_filter === 'fail' && !empty($item['is_success'])) {
                continue;
            }

            $dom = (string)($item['domain'] ?? '');
            $dom_key = normalize_domain_key($dom);
            $owner = ($dom_key !== '' && isset($domain_owner_map[$dom_key])) ? $domain_owner_map[$dom_key] : null;
            $people = $owner ? trim((string)($owner['people'] ?? '')) : '';
            if (!owner_match_filter($people, $owner_filter)) {
                continue;
            }
            $country = $owner ? trim((string)($owner['country'] ?? '')) : '';
            $category = $owner ? trim((string)($owner['category'] ?? '')) : '';
            $site_date = $owner ? trim((string)($owner['date'] ?? '')) : '';

            $amt = $item['details']['amt'] ?? 0;
            $cur = (string)($item['details']['cur'] ?? '');
            $usd = $item['details']['usd_amt'] ?? 0;
            $attempts = (int)($item['attempts'] ?? 0);
            $notify_cnt = (int)($item['details']['notify_count'] ?? 0);
            $err = (string)($item['details']['err'] ?? '');
            $time = (string)($item['time'] ?? '');
            $time_short = ($time !== '' && strlen($time) >= 16) ? substr($time, 11, 5) : $time;

            $rows[] = [
                'no' => (string)$no,
                'time' => $time,
                'time_short' => $time_short,
                'domain' => $dom,
                'is_success' => !empty($item['is_success']),
                'attempts' => $attempts,
                'notify_cnt' => $notify_cnt,
                'cur' => $cur,
                'amt' => $amt,
                'usd' => $usd,
                'people' => $people,
                'country' => $country,
                'category' => $category,
                'site_date' => $site_date,
                'err' => $err,
            ];
        }

        $sort_rows = function (&$arr) use ($order_sort) {
            $get_amt = function ($x) {
                $v = $x['amt'] ?? 0;
                return is_numeric($v) ? (float)$v : 0.0;
            };
            $get_attempts = function ($x) {
                $v = $x['attempts'] ?? 0;
                return is_numeric($v) ? (int)$v : 0;
            };
            $get_time = function ($x) {
                return (string)($x['time'] ?? '');
            };
            $get_site_date_ts = function ($x) {
                return parse_site_date_to_ts((string)($x['site_date'] ?? ''));
            };
            usort($arr, function ($a, $b) use ($order_sort, $get_amt, $get_attempts, $get_time, $get_site_date_ts) {
                switch ($order_sort) {
                    case 'site_date_asc':
                        $ta = $get_site_date_ts($a);
                        $tb = $get_site_date_ts($b);
                        if ($ta === 0 && $tb !== 0) return 1;
                        if ($tb === 0 && $ta !== 0) return -1;
                        $cmp = $ta <=> $tb;
                        if ($cmp !== 0) return $cmp;
                        break;
                    case 'site_date_desc':
                        $ta = $get_site_date_ts($a);
                        $tb = $get_site_date_ts($b);
                        if ($ta === 0 && $tb !== 0) return 1;
                        if ($tb === 0 && $ta !== 0) return -1;
                        $cmp = $tb <=> $ta;
                        if ($cmp !== 0) return $cmp;
                        break;
                    case 'amt_asc':
                        $cmp = $get_amt($a) <=> $get_amt($b);
                        if ($cmp !== 0) return $cmp;
                        break;
                    case 'amt_desc':
                        $cmp = $get_amt($b) <=> $get_amt($a);
                        if ($cmp !== 0) return $cmp;
                        break;
                    case 'attempts_asc':
                        $cmp = $get_attempts($a) <=> $get_attempts($b);
                        if ($cmp !== 0) return $cmp;
                        break;
                    case 'attempts_desc':
                        $cmp = $get_attempts($b) <=> $get_attempts($a);
                        if ($cmp !== 0) return $cmp;
                        break;
                    case 'time_asc':
                        $cmp = strcmp($get_time($a), $get_time($b));
                        if ($cmp !== 0) return $cmp;
                        break;
                    case 'time_desc':
                    default:
                        $cmp = strcmp($get_time($b), $get_time($a));
                        if ($cmp !== 0) return $cmp;
                        break;
                }
                return strcmp($get_time($b), $get_time($a));
            });
        };

        $sort_rows($rows);

        echo '<div class="excel-table-wrap">';
        echo '<table class="excel-table" id="ordersExcelTable">';
        echo '<thead><tr>';
        echo '<th style="width:48px;">#</th>';
        echo '<th style="width:60px;">时间</th>';
        echo '<th>域名</th>';
        if ($has_people) echo '<th style="width:90px;">人员</th>';
        if ($has_country) echo '<th style="width:70px;">国家</th>';
        if ($has_category) echo '<th style="width:120px;">内容</th>';
        if ($has_date) echo '<th style="width:98px;">建站日期</th>';
        echo '<th style="width:130px; text-align:right;">金额</th>';
        echo '<th style="width:76px; text-align:right;">$</th>';
        echo '<th style="width:56px; text-align:right;">尝试</th>';
        echo '<th style="width:66px; text-align:right;">notify</th>';
        echo '<th style="width:92px;">状态</th>';
        echo '<th>错误</th>';
        echo '</tr></thead>';
        echo '<tbody>';

        $i = 1;
        foreach ($rows as $r) {
            $st = $r['is_success'] ? 'SUCCESS' : 'INCOMPLETE';
            $st_class = $r['is_success'] ? 'row-success' : ($r['err'] !== '' ? 'row-fail' : '');
            echo '<tr class="' . $st_class . '" data-order-no="' . htmlspecialchars($r['no']) . '">';
            echo '<td class="cell-num">' . $i . '</td>';
            echo '<td class="cell-mono">' . htmlspecialchars($r['time_short']) . '</td>';
            echo '<td class="cell-domain">';
            echo '<button type="button" class="copy-domain-btn" data-copy-domain="' . htmlspecialchars($r['domain']) . '">复制</button>';
            echo '<span style="margin-left:6px;">' . htmlspecialchars($r['domain']) . '</span>';
            echo '</td>';
            if ($has_people) {
                echo '<td>' . ($r['people'] !== '' ? htmlspecialchars($r['people']) : '<span style="color:#c2410c; font-weight:700;">未匹配</span>') . '</td>';
            }
            if ($has_country) echo '<td>' . htmlspecialchars($r['country']) . '</td>';
            if ($has_category) echo '<td class="cell-ellipsis" title="' . htmlspecialchars($r['category']) . '">' . htmlspecialchars($r['category']) . '</td>';
            if ($has_date) echo '<td class="cell-mono">' . htmlspecialchars($r['site_date']) . '</td>';
            echo '<td class="cell-num" style="text-align:right;">' . htmlspecialchars($r['cur']) . ' ' . format_money($r['amt']) . '</td>';
            echo '<td class="cell-num" style="text-align:right;">' . ($r['usd'] > 0 ? ('$' . format_money($r['usd'])) : '') . '</td>';
            echo '<td class="cell-num" style="text-align:right;">' . (int)$r['attempts'] . '</td>';
            echo '<td class="cell-num" style="text-align:right;">' . (int)$r['notify_cnt'] . '</td>';
            echo '<td><span class="excel-status ' . ($r['is_success'] ? 'is-ok' : 'is-warn') . '">' . $st . '</span></td>';
            echo '<td class="cell-ellipsis" title="' . htmlspecialchars($r['err']) . '">' . htmlspecialchars($r['err']) . '</td>';
            echo '</tr>';
            $i++;
        }
        echo '</tbody>';
        echo '</table>';
        echo '</div>';

        return ob_get_clean();
    }

    $sort_orders_inplace = function (&$orders) use ($order_sort, $domain_owner_map) {
        uasort($orders, function ($a, $b) use ($order_sort, $domain_owner_map) {
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

            $get_site_date_ts = function ($x) use ($domain_owner_map) {
                $dom = (string)($x['domain'] ?? '');
                $key = normalize_domain_key($dom);
                $date = ($key !== '' && isset($domain_owner_map[$key])) ? (string)($domain_owner_map[$key]['date'] ?? '') : '';
                return parse_site_date_to_ts($date);
            };

            switch ($order_sort) {
                case 'site_date_asc':
                    $ta = $get_site_date_ts($a);
                    $tb = $get_site_date_ts($b);
                    if ($ta === 0 && $tb !== 0) { $cmp = 1; break; }
                    if ($tb === 0 && $ta !== 0) { $cmp = -1; break; }
                    $cmp = $ta <=> $tb;
                    break;
                case 'site_date_desc':
                    $ta = $get_site_date_ts($a);
                    $tb = $get_site_date_ts($b);
                    if ($ta === 0 && $tb !== 0) { $cmp = 1; break; }
                    if ($tb === 0 && $ta !== 0) { $cmp = -1; break; }
                    $cmp = $tb <=> $ta;
                    break;
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
            $dom_key = normalize_domain_key($item['domain'] ?? '');
            $owner = ($dom_key !== '' && isset($domain_owner_map[$dom_key])) ? $domain_owner_map[$dom_key] : null;
            $people = $owner ? trim((string)($owner['people'] ?? '')) : '';
            if (!owner_match_filter($people, $owner_filter)) {
                continue;
            }
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

        // 对每个站点内部订单排序，并按排序字段对站点分组本身进行排序（取每组排序后第一条作为代表）
        $sorted_groups = [];
        foreach ($grouped as $domain => $orders) {
            usort($orders, function ($a, $b) use ($order_sort, $domain_owner_map) {
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

                $get_site_date_ts = function ($x) use ($domain_owner_map) {
                    $dom = (string)($x['domain'] ?? '');
                    $key = normalize_domain_key($dom);
                    $date = ($key !== '' && isset($domain_owner_map[$key])) ? (string)($domain_owner_map[$key]['date'] ?? '') : '';
                    return parse_site_date_to_ts($date);
                };

                switch ($order_sort) {
                    case 'site_date_asc':
                        $ta = $get_site_date_ts($ia);
                        $tb = $get_site_date_ts($ib);
                        if ($ta === 0 && $tb !== 0) { $cmp = 1; break; }
                        if ($tb === 0 && $ta !== 0) { $cmp = -1; break; }
                        $cmp = $ta <=> $tb;
                        break;
                    case 'site_date_desc':
                        $ta = $get_site_date_ts($ia);
                        $tb = $get_site_date_ts($ib);
                        if ($ta === 0 && $tb !== 0) { $cmp = 1; break; }
                        if ($tb === 0 && $ta !== 0) { $cmp = -1; break; }
                        $cmp = $tb <=> $ta;
                        break;
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
            $sorted_groups[] = ['domain' => $domain, 'orders' => $orders, 'rep' => ($orders[0]['item'] ?? null)];
        }

        usort($sorted_groups, function ($ga, $gb) use ($order_sort, $domain_owner_map) {
            $ia = $ga['rep'] ?? [];
            $ib = $gb['rep'] ?? [];

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
            $get_site_date_ts = function ($x) use ($domain_owner_map) {
                $dom = (string)($x['domain'] ?? '');
                $key = normalize_domain_key($dom);
                $date = ($key !== '' && isset($domain_owner_map[$key])) ? (string)($domain_owner_map[$key]['date'] ?? '') : '';
                return parse_site_date_to_ts($date);
            };

            switch ($order_sort) {
                case 'site_date_asc':
                    $ta = $get_site_date_ts($ia);
                    $tb = $get_site_date_ts($ib);
                    if ($ta === 0 && $tb !== 0) { $cmp = 1; break; }
                    if ($tb === 0 && $ta !== 0) { $cmp = -1; break; }
                    $cmp = $ta <=> $tb;
                    break;
                case 'site_date_desc':
                    $ta = $get_site_date_ts($ia);
                    $tb = $get_site_date_ts($ib);
                    if ($ta === 0 && $tb !== 0) { $cmp = 1; break; }
                    if ($tb === 0 && $ta !== 0) { $cmp = -1; break; }
                    $cmp = $tb <=> $ta;
                    break;
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

        foreach ($sorted_groups as $g) {
            $domain = $g['domain'];
            $orders = $g['orders'];
            echo '<div class="order-item" style="border-left:5px solid #6366f1; margin-bottom:18px;">';
            echo '<div class="order-main" onclick="document.getElementById(\'group_' . md5($domain) . '\').style.display = (document.getElementById(\'group_' . md5($domain) . '\').style.display==\'none\'?\'block\':\'none\');">';
            echo '<span style="font-size:14px; color:#fff; font-weight:bold; background:#6366f1; border-radius:6px; padding:2px 10px; margin-right:10px;">' . $group_index . '</span>';
            $group_index++;
            echo '<strong style="font-size:16px; color:#6366f1;">' . htmlspecialchars($domain) . '</strong>';
            echo '<div class="order-tags">';
            if ($has_people || $has_country) {
                $dom_key = normalize_domain_key($domain);
                $owner = ($dom_key !== '' && isset($domain_owner_map[$dom_key])) ? $domain_owner_map[$dom_key] : null;
                $people = $owner ? trim((string)($owner['people'] ?? '')) : '';
                $country = $owner ? trim((string)($owner['country'] ?? '')) : '';
                $category = $owner ? trim((string)($owner['category'] ?? '')) : '';
                $site_date = $owner ? trim((string)($owner['date'] ?? '')) : '';
                if ($people !== '') {
                    echo '<span class="badge badge-attempts" style="margin-left:10px; background:#eef2ff; color:#4f46e5;">人员:' . htmlspecialchars($people) . '</span>';
                }
                if ($has_country && $country !== '') {
                    echo '<span class="badge badge-attempts" style="margin-left:6px; background:#ecfeff; color:#0e7490;">' . htmlspecialchars($country) . '</span>';
                }
                if ($has_category && $category !== '') {
                    echo '<span class="badge badge-attempts" style="margin-left:6px; background:#f0fdf4; color:#166534;">内容:' . htmlspecialchars($category) . '</span>';
                }
                if ($has_date && $site_date !== '') {
                    echo '<span class="badge badge-attempts" style="margin-left:6px; background:#f1f5f9; color:#334155;">建站日期:' . htmlspecialchars($site_date) . '</span>';
                }
            }
            echo '<span class="badge badge-attempts" style="margin-left:10px;">' . count($orders) . '条订单</span>';
            echo '<span style="margin-left:10px; color:#64748b; font-size:13px;">点击展开/收起</span>';
            echo '</div>';
            echo '</div>';
            echo '<div id="group_' . md5($domain) . '" style="display:none;">';
            foreach ($orders as $order) {
                $item = $order['item'];
                $no = $order['no'];
                $st_class = $item['is_success'] ? 'is-success' : (!empty($item['details']['err']) ? 'is-fail' : '');
                echo '<div class="order-item ' . $st_class . '" style="margin-bottom:8px;">';
                echo '<div class="order-main" onclick="toggleLog(\'log_' . $no . '\')">';
                echo '<div style="flex:1;">';
                echo '<div class="order-tags" style="display:flex; align-items:center; gap:8px; flex-wrap:wrap;">';
                echo '<span style="font-size:13px; color:#64748b; font-weight:bold; background:#f1f5f9; border-radius:6px; padding:2px 8px; margin-right:6px;">' . $order_index . '</span>';
                $order_index++;
                echo '<strong style="font-size:15px;">' . htmlspecialchars($item['domain']) . '</strong>';
                echo '<button type="button" class="copy-domain-btn" data-copy-domain="' . htmlspecialchars($item['domain']) . '">复制域名</button>';
                if ($has_people || $has_country || $has_category || $has_date) {
                    $dom_key = normalize_domain_key($item['domain'] ?? '');
                    $owner = ($dom_key !== '' && isset($domain_owner_map[$dom_key])) ? $domain_owner_map[$dom_key] : null;
                    $people = $owner ? trim((string)($owner['people'] ?? '')) : '';
                    $country = $owner ? trim((string)($owner['country'] ?? '')) : '';
                    $category = $owner ? trim((string)($owner['category'] ?? '')) : '';
                    $date = $owner ? trim((string)($owner['date'] ?? '')) : '';
                    if ($people !== '') {
                        echo '<span class="badge badge-attempts" style="background:#eef2ff; color:#4f46e5;">人员:' . htmlspecialchars($people) . '</span>';
                    } else {
                        echo '<span class="badge badge-attempts" style="background:#fff7ed; color:#c2410c;">人员:未匹配</span>';
                    }
                    if ($has_country && $country !== '') {
                        echo '<span class="badge badge-attempts" style="background:#ecfeff; color:#0e7490;">' . htmlspecialchars($country) . '</span>';
                    }
                    if ($has_category && $category !== '') {
                        echo '<span class="badge badge-attempts" style="background:#f0fdf4; color:#166534;">' . htmlspecialchars($category) . '</span>';
                    }
                    if ($has_date && $date !== '') {
                        echo '<span class="badge badge-attempts" style="background:#f1f5f9; color:#334155;">建站日期:' . htmlspecialchars($date) . '</span>';
                    }
                }
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
            echo '<div class="order-item" id="' . $group_id . '_wrap" data-order-group-wrap="' . $group_key . '" style="border-left:5px solid ' . ($group_key == 'success' ? '#10b981' : '#ef4444') . '; margin-bottom:18px;">';
            echo '<div class="order-main" data-order-group-header="' . $group_key . '" style="cursor:pointer;user-select:none;" onclick="var el=document.getElementById(\'' . $group_id . '\');el.style.display=(el.style.display==\'none\'?\'block\':\'none\');">';
            echo '<span style="font-size:15px; font-weight:bold; color:' . ($group_key == 'success' ? '#10b981' : '#ef4444') . ';">' . $group_titles[$group_key] . '</span>';
            $filtered_cnt = 0;
            foreach ($orders as $no0 => $it0) {
                $oi0 = get_owner_info_for_domain($it0['domain'] ?? '', $domain_owner_map);
                $p0 = $oi0 ? trim((string)($oi0['people'] ?? '')) : '';
                if (owner_match_filter($p0, $owner_filter)) {
                    $filtered_cnt++;
                }
            }
            echo '<div class="order-tags">';
            echo '<span class="badge badge-attempts" style="margin-left:10px;">' . $filtered_cnt . '条</span>';
            echo '<span style="margin-left:10px; color:#64748b; font-size:13px;">点击展开/收起</span>';
            echo '</div>';
            echo '</div>';
            $default_open = ($group_key === 'fail' && $status_filter !== 'success') || ($group_key === 'success' && $status_filter === 'success');
            echo '<div id="' . $group_id . '" data-order-group-body="' . $group_key . '" style="display:' . ($default_open ? 'block' : 'none') . ';">';
            foreach ($orders as $no => $item) {
                $dom_key = normalize_domain_key($item['domain'] ?? '');
                $owner = ($dom_key !== '' && isset($domain_owner_map[$dom_key])) ? $domain_owner_map[$dom_key] : null;
                $people = $owner ? trim((string)($owner['people'] ?? '')) : '';
                if (!owner_match_filter($people, $owner_filter)) {
                    continue;
                }
                $st_class = $item['is_success'] ? 'is-success' : (!empty($item['details']['err']) ? 'is-fail' : '');
                echo '<div class="order-item ' . $st_class . '" style="margin-bottom:8px;">';
                echo '<div class="order-main" onclick="toggleLog(\'log_' . $no . '\')">';
                echo '<div style="flex:1;">';
                echo '<div class="order-tags" style="display:flex; align-items:center; gap:8px; flex-wrap:wrap;">';
                echo '<span style="font-size:13px; color:#64748b; font-weight:bold; background:#f1f5f9; border-radius:6px; padding:2px 8px; margin-right:6px;">' . $order_index . '</span>';
                $order_index++;
                echo '<strong style="font-size:15px;">' . htmlspecialchars($item['domain']) . '</strong>';
                echo '<button type="button" class="copy-domain-btn" data-copy-domain="' . htmlspecialchars($item['domain']) . '">复制域名</button>';
                if ($has_people || $has_country || $has_category || $has_date) {
                    $country = $owner ? trim((string)($owner['country'] ?? '')) : '';
                    $category = $owner ? trim((string)($owner['category'] ?? '')) : '';
                    $date = $owner ? trim((string)($owner['date'] ?? '')) : '';
                    if ($people !== '') {
                        echo '<span class="badge badge-attempts" style="background:#eef2ff; color:#4f46e5;">人员:' . htmlspecialchars($people) . '</span>';
                    } else {
                        echo '<span class="badge badge-attempts" style="background:#fff7ed; color:#c2410c;">人员:未匹配</span>';
                    }
                    if ($has_country && $country !== '') {
                        echo '<span class="badge badge-attempts" style="background:#ecfeff; color:#0e7490;">' . htmlspecialchars($country) . '</span>';
                    }
                    if ($has_category && $category !== '') {
                        echo '<span class="badge badge-attempts" style="background:#f0fdf4; color:#166534;">' . htmlspecialchars($category) . '</span>';
                    }
                    if ($has_date && $date !== '') {
                        echo '<span class="badge badge-attempts" style="background:#f1f5f9; color:#334155;">建站日期:' . htmlspecialchars($date) . '</span>';
                    }
                }
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
    $csv_files = list_csv_files_in_dir(__DIR__);
    $csv_path = resolve_selected_csv_path(__DIR__, $csv_selected, $csv_files);
    echo render_order_list_items($analysis_data, $group_by_domain, $order_sort, $status_filter, $owner_filter, $csv_path, $list_view);
    exit;
}

$is_partial_range_revenue_json = ($view_mode === 'analysis' && (($_GET['partial'] ?? '') === 'range_revenue_json'));
if ($is_partial_range_revenue_json) {
    header('Content-Type: application/json; charset=UTF-8');
    [$min_date0, $max_date0] = find_available_log_date_range();
    $rs0 = (string)($_GET['range_start'] ?? '');
    $re0 = (string)($_GET['range_end'] ?? '');
    $range_error0 = validate_date_range($rs0, $re0, $min_date0, $max_date0);
    $rev_days0 = [];
    if ($range_error0 === '') {
        $rev_days0 = compute_range_revenue_days($rs0, $re0);
    }
    echo json_encode([
        'meta' => [
            'min_date' => $min_date0,
            'max_date' => $max_date0,
            'range_start' => $rs0,
            'range_end' => $re0,
            'range_error' => $range_error0,
        ],
        'data' => $rev_days0,
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

$is_partial_range_revenue = ($view_mode === 'analysis' && (($_GET['partial'] ?? '') === 'range_revenue'));
if ($is_partial_range_revenue) {
    header('Content-Type: text/html; charset=UTF-8');
    [$min_date0, $max_date0] = find_available_log_date_range();
    $rs0 = (string)($_GET['range_start'] ?? '');
    $re0 = (string)($_GET['range_end'] ?? '');
    $range_error0 = validate_date_range($rs0, $re0, $min_date0, $max_date0);
    $rev_days0 = [];
    if ($range_error0 === '') {
        $rev_days0 = compute_range_revenue_days($rs0, $re0);
    }
    echo render_range_revenue_module($access_token, $view_mode, $rs0, $re0, $min_date0, $max_date0, $rev_days0, $range_error0);
    exit;
}

$is_export_orders_csv = ($view_mode === 'analysis' && (($_GET['export'] ?? '') === 'orders_csv'));
if ($is_export_orders_csv) {
    $rs0 = (string)($_GET['export_start'] ?? ($_GET['range_start'] ?? ''));
    $re0 = (string)($_GET['export_end'] ?? ($_GET['range_end'] ?? ''));
    export_orders_csv_range($access_token, $rs0, $re0, $status_filter, $owner_filter, $amount_nonzero, $csv_selected);
    exit;
}

$is_partial_analysis = ($view_mode === 'analysis' && (($_GET['partial'] ?? '') === 'analysis'));
if ($is_partial_analysis) {
    header('Content-Type: text/html; charset=UTF-8');
    echo render_analysis_content($access_token, $view_mode, $log_date, $stats, $analysis_data, $group_by_domain, $order_sort, $status_filter, $owner_filter, $csv_selected);
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

        .excel-table-wrap {
            border: 1px solid #e2e8f0;
            border-radius: 12px;
            background: #fff;
            overflow: auto;
            box-shadow: 0 10px 15px -10px rgba(2, 6, 23, 0.15);
        }

        .excel-table {
            width: 100%;
            border-collapse: separate;
            border-spacing: 0;
            font-size: 12px;
            line-height: 1.25;
        }

        .excel-table thead th {
            position: sticky;
            top: 0;
            z-index: 2;
            background: #f8fafc;
            color: #0f172a;
            font-weight: 800;
            text-align: left;
            padding: 8px 8px;
            border-bottom: 1px solid #e2e8f0;
            white-space: nowrap;
        }

        .excel-table tbody td {
            padding: 6px 8px;
            border-bottom: 1px solid #f1f5f9;
            border-right: 1px solid #f1f5f9;
            vertical-align: middle;
            white-space: nowrap;
        }

        .excel-table tbody tr:hover td {
            background: #f8fafc;
        }

        .excel-table tbody tr.row-success td {
            background: rgba(16,185,129,0.04);
        }

        .excel-table tbody tr.row-fail td {
            background: rgba(239,68,68,0.04);
        }

        .excel-table .cell-num {
            font-variant-numeric: tabular-nums;
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
        }

        .excel-table .cell-mono {
            font-variant-numeric: tabular-nums;
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
            color: #334155;
        }

        .excel-table .cell-domain {
            min-width: 260px;
        }

        .excel-table .cell-ellipsis {
            max-width: 280px;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .excel-status {
            display: inline-block;
            padding: 2px 8px;
            border-radius: 999px;
            font-weight: 800;
            font-size: 11px;
            border: 1px solid #e2e8f0;
        }

        .excel-status.is-ok {
            background: #ecfdf5;
            color: #059669;
            border-color: #a7f3d0;
        }

        .excel-status.is-warn {
            background: #f8fafc;
            color: #64748b;
            border-color: #e2e8f0;
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
                width: 35%;
                position: sticky;
                top: var(--sticky-side-top, 180px);
                max-height: calc(100vh - var(--sticky-side-top, 180px) - 12px);
                overflow: auto;
                overscroll-behavior: contain;
            }
        }

        .collapsible-card-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 10px;
            cursor: pointer;
            user-select: none;
        }

        .collapsible-card-toggle {
            border: 1px solid #e2e8f0;
            background: #ffffff;
            color: #0f172a;
            border-radius: 10px;
            padding: 6px 10px;
            font-size: 12px;
            font-weight: 800;
            cursor: pointer;
        }

        .collapsible-card-toggle:hover {
            border-color: #cbd5e1;
            background: #f8fafc;
        }

        .collapsible-card-body.is-collapsed {
            display: none;
        }

        #revenueChartContainer.is-collapsed {
            min-height: 0 !important;
            padding-bottom: 10px !important;
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
            /* padding: 0px; */
            margin-bottom: 14px;
            border: 1px solid #e2e8f0;
            box-shadow: 0 4px 14px rgba(15,23,42,0.06);
        }

        @media (max-width: 900px) {
            .order-item {
                /* padding: 1px 1px; */
                margin-bottom: 10px;
                border-radius: 14px;
            }
            .order-main {
                gap: 10px;
                
            }
            .order-main strong {
                font-size: 14px !important;
            }
            .order-tags {
                gap: 6px 6px;
            }
            .order-tags .badge {
                display: inline-flex;
                align-items: center;
                width: auto;
                max-width: 100%;
                flex: 0 0 auto;
                white-space: nowrap;
            }
            .badge {
                padding: 4px 8px;
                border-radius: 999px;
                font-size: 11px;
            }
            .badge-attempts {
                padding: 4px 8px;
                font-size: 11px;
            }
            .error-msg {
                font-size: 12px;
                padding: 8px 10px;
            }
            .log-content {
                font-size: 11px;
                line-height: 1.35;
            }
            .copy-domain-btn {
                padding: 5px 8px;
                font-size: 11px;
            }

            .order-group-float {
                position: fixed;
                left: 10px;
                right: 10px;
                bottom: 10px;
                z-index: 1200;
                background: rgba(255,255,255,0.98);
                border: 1px solid #e2e8f0;
                border-radius: 14px;
                box-shadow: 0 10px 24px rgba(15,23,42,0.18);
                padding: 8px 10px;
            }
            .order-group-float .order-main {
                padding: 0 !important;
            }
        }

        .order-group-float {
            display: none;
        }

        .order-group-float.is-active {
            display: block;
        }

        .order-group-float button {
            border: none;
            background: transparent;
            padding: 0;
            margin: 0;
            cursor: pointer;
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

        .order-tags {
            display: flex;
            align-items: center;
            gap: 8px;
            flex-wrap: wrap;
            min-width: 0;
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
            max-width: 260px;
        }

        .rank-num {
            width: 26px;
            flex: 0 0 26px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            font-size: 12px;
            font-weight: 900;
            color: #64748b;
            background: #f1f5f9;
            border-radius: 8px;
            height: 22px;
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
                <h2 style="margin:0;">🛡️ 支付监控中心 <small style="font-size:12px; opacity:0.6; font-weight:normal;">v1.0.20260105

                </small></h2>
                <div style="display: flex; gap: 10px; align-items: center;">
                    <div style="background: rgba(255,255,255,0.1); padding: 4px; border-radius: 10px; display: flex; align-items:center; gap:6px;">
                        <a href="?token=<?= $access_token ?>&date=<?= $prev_date ?>&mode=<?= $view_mode ?>"
                            class="nav-btn" data-nav-date="<?= $prev_date ?>" onclick="if(window.__ordersSetDate){event.preventDefault();event.stopPropagation();window.__ordersSetDate('<?= $prev_date ?>');return false;}" style="background:transparent; padding:8px;">«</a>
                        <input type="date" id="mainDatePicker" value="<?= $log_date ?>"
                            onchange="window.__ordersSetDate ? window.__ordersSetDate(this.value) : (location.href='?token=<?= $access_token ?>&mode=<?= $view_mode ?>&date='+this.value)"
                            style="background:transparent; border:none; color:white; font-weight:bold; width:130px; text-align:center;">
                        <a href="?token=<?= $access_token ?>&date=<?= $next_date ?>&mode=<?= $view_mode ?>"
                            class="nav-btn" data-nav-date="<?= $next_date ?>" onclick="if(window.__ordersSetDate){event.preventDefault();event.stopPropagation();window.__ordersSetDate('<?= $next_date ?>');return false;}" style="background:transparent; padding:8px;">»</a>
                        <button type="button" class="nav-btn" id="quickTodayBtn" style="font-size:12px;">今天</button>
                        <button type="button" class="nav-btn" id="quickPickBtn" style="font-size:12px;">选择日期…</button>
                    </div>
                    <a href="?<?= http_build_query(array_merge($_GET, ['mode' => 'analysis'])) ?>"
                        class="nav-btn <?= $view_mode == 'analysis' ? 'active' : '' ?>">📊 分析</a>
                    <a href="?<?= http_build_query(array_merge($_GET, ['mode' => 'raw'])) ?>"
                        class="nav-btn <?= $view_mode == 'raw' ? 'active' : '' ?>">📝 源码</a>
                    <button type="button" id="headerCollapseBtn" class="nav-btn" title="收起页眉" aria-label="收起页眉" style="background:#0b1222; padding:8px 10px;">收起</button>
                    <?php if ($view_mode === 'analysis'): ?>
                        <form method="get" style="display:flex; align-items:center; gap:8px; margin-left:8px;">
                            <input type="hidden" name="token" value="<?= htmlspecialchars($access_token) ?>">
                            <input type="hidden" name="mode" value="analysis">
                            <input type="hidden" name="export" value="orders_csv">
                            <input type="hidden" name="status" value="<?= htmlspecialchars($status_filter) ?>">
                            <input type="hidden" name="sort" value="<?= htmlspecialchars($order_sort) ?>">
                            <input type="hidden" name="owner" value="<?= htmlspecialchars($owner_filter) ?>">
                            <input type="hidden" name="csv_file" value="<?= htmlspecialchars($csv_selected) ?>">
                            <?php if (!empty($_GET['amount_nonzero'])): ?>
                                <input type="hidden" name="amount_nonzero" value="1">
                            <?php endif; ?>
                            <input type="hidden" name="range_start" value="">
                            <input type="hidden" name="range_end" value="">
                            <button type="submit" class="nav-btn" data-export-range-btn="1" style="background:#0ea5e9; color:white; border:none; padding:8px 14px; font-size:13px; font-weight:600; border-radius:10px; cursor:pointer; transition:background 0.2s, box-shadow 0.2s, transform 0.2s; box-shadow:0 2px 10px rgba(14,165,233,0.22);" onmouseover="this.style.background='#0284c7'; this.style.boxShadow='0 6px 18px rgba(14,165,233,0.30)'; this.style.transform='translateY(-1px)';" onmouseout="this.style.background='#0ea5e9'; this.style.boxShadow='0 2px 10px rgba(14,165,233,0.22)'; this.style.transform='translateY(0)';">
                                📤 导出 CSV
                            </button>
                        </form>
                    <?php endif; ?>
                </div>
            </div>
        </header>

        <button type="button" id="headerExpandBtn" title="展开页眉" aria-label="展开页眉">展开页眉</button>

        <?php if ($view_mode === 'analysis'): ?>
            <div id="analysisRoot"><?= render_analysis_content($access_token, $view_mode, $log_date, $stats, $analysis_data, $group_by_domain, $order_sort, $status_filter, $owner_filter, $csv_selected) ?></div>
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
                    if (window.__ordersSetDate) {
                        window.__ordersSetDate(dateStr);
                    } else {
                        location.href = `?token=<?= $access_token ?>&mode=<?= $view_mode ?>&date=${dateStr}`;
                    }
                };
            }
            if (quickPickBtn) {
                quickPickBtn.onclick = function() {
                    mainDatePicker.showPicker ? mainDatePicker.showPicker() : mainDatePicker.focus();
                };
            }
        });
        (function() {
            document.addEventListener('click', function(e) {
                const a = e.target && e.target.closest ? e.target.closest('a[data-nav-date]') : null;
                if (!a) return;
                const date = a.getAttribute('data-nav-date') || '';
                if (!date) return;
                if (!window.__ordersSetDate) return;
                e.preventDefault();
                e.stopPropagation();
                window.__ordersSetDate(date);
            }, true);
        })();
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
            function setCollapsed(cardEl, collapsed) {
                if (!cardEl) return;
                const body = cardEl.querySelector('[data-collapsible-card-body]');
                const btn = cardEl.querySelector('[data-collapsible-card-toggle]');
                if (!body || !btn) return;

                if (collapsed) {
                    body.classList.add('is-collapsed');
                    btn.textContent = '展开';
                    cardEl.setAttribute('data-collapsed', '1');
                    cardEl.classList.add('is-collapsed');
                } else {
                    body.classList.remove('is-collapsed');
                    btn.textContent = '收起';
                    cardEl.setAttribute('data-collapsed', '0');
                    cardEl.classList.remove('is-collapsed');
                }
            }

            function init() {
                document.querySelectorAll('[data-collapsible-card]').forEach(function(cardEl) {
                    const key = cardEl.getAttribute('data-collapsible-card') || '';
                    const storageKey = key ? ('orders3_collapsed_' + key) : '';
                    let collapsed = false;

                    if (key !== 'range_revenue' && storageKey) {
                        try {
                            const v = localStorage.getItem(storageKey);
                            if (v === '1') collapsed = true;
                            if (v === '0') collapsed = false;
                        } catch (e) {}
                    }
                    // 多日营收统计卡片：每次页面加载/刷新都默认折叠
                    if (key === 'range_revenue') {
                        if (typeof window.__rangeRevenueDesiredCollapsed === 'boolean') {
                            collapsed = window.__rangeRevenueDesiredCollapsed;
                            try { delete window.__rangeRevenueDesiredCollapsed; } catch (e) { window.__rangeRevenueDesiredCollapsed = undefined; }
                        } else {
                            collapsed = true;
                        }
                    }

                    setCollapsed(cardEl, collapsed);

                    const header = cardEl.querySelector('[data-collapsible-card-header]');
                    const btn = cardEl.querySelector('[data-collapsible-card-toggle]');

                    const toggle = function() {
                        const nowCollapsed = (cardEl.getAttribute('data-collapsed') === '1');
                        const next = !nowCollapsed;
                        setCollapsed(cardEl, next);
                        if (key !== 'range_revenue' && storageKey) {
                            try { localStorage.setItem(storageKey, next ? '1' : '0'); } catch (e) {}
                        }
                    };

                    if (btn) {
                        btn.addEventListener('click', function(ev) {
                            ev.preventDefault();
                            ev.stopPropagation();
                            toggle();
                        });
                    }
                    if (header) {
                        header.addEventListener('click', function(ev) {
                            ev.preventDefault();
                            toggle();
                        });
                    }
                });
            }

            window.__initCollapsibleCards = init;

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', init);
            } else {
                init();
            }
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
                const owner = (fd.get('owner') || '').toString();
                const csvFile = (fd.get('csv_file') || '').toString();
                const listView = (fd.get('list_view') || '').toString();

                const isJumpStatus = (status === 'success' || status === 'fail');
                const shouldJump = (!groupByDomain) && isJumpStatus && (window.event && window.event.target && window.event.target.name === 'status');
                const triggerName = (window.event && window.event.target && window.event.target.name) ? window.event.target.name : '';

                if (token) url.searchParams.set('token', token);
                if (date) url.searchParams.set('date', date);
                url.searchParams.set('mode', 'analysis');
                url.searchParams.set('status', status);
                url.searchParams.set('sort', sort);

                if (owner) url.searchParams.set('owner', owner);
                else url.searchParams.delete('owner');

                if (csvFile) url.searchParams.set('csv_file', csvFile);
                else url.searchParams.delete('csv_file');

                if (listView) url.searchParams.set('list_view', listView);
                else url.searchParams.delete('list_view');

                // 切换 CSV 时，需要同时刷新：人员下拉、人员汇总、映射来源等（不只是订单列表）
                if (triggerName === 'csv_file') {
                    // 切换 CSV 通常会导致人员列表变化，顺便清理可能不再存在的 owner
                    url.searchParams.delete('owner');
                    location.href = url.toString();
                    return;
                }

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

        function initHourlyChart() {
            const canvas = document.getElementById('hourlyChart');
            if (!canvas || !window.Chart) return;
            const dataObj = window.__hourlyChartData || {};
            const attempts = Array.isArray(dataObj.attempts) ? dataObj.attempts : [];
            const success = Array.isArray(dataObj.success) ? dataObj.success : [];
            const ctx = canvas.getContext('2d');
            if (!ctx) return;
            if (window.hourlyChartInstance) {
                try { window.hourlyChartInstance.destroy(); } catch (e) {}
                window.hourlyChartInstance = null;
            }
            window.hourlyChartInstance = new Chart(ctx, {
                type: 'line',
                data: {
                    labels: Array.from({ length: 24 }).map(function(_, i) { return i + ':00'; }),
                    datasets: [{
                        label: '尝试次数', data: attempts,
                        borderColor: '#6366f1', backgroundColor: 'rgba(99, 102, 241, 0.05)', fill: true, tension: 0.4, borderWidth: 2, pointRadius: 3
                    }, {
                        label: '成功次数', data: success,
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
            try { window.revenueChartInstance.__rawData = data; } catch (e) {}
        }

        (function() {
            let controller = null;
            window.__ordersSetDate = function(nextDate) {
                const dateStr = (nextDate || '').toString();
                if (!/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) return;

                // 保留多日营收统计图当前展开/折叠状态（用于本次局部刷新后恢复）
                try {
                    const rangeCard = document.querySelector('[data-collapsible-card="range_revenue"]');
                    if (rangeCard) {
                        const isCollapsed = (rangeCard.getAttribute('data-collapsed') === '1');
                        window.__rangeRevenueDesiredCollapsed = isCollapsed;
                    }
                } catch (e) {}

                const openedState = {
                    ids: (function() {
                        try {
                            const root0 = document.getElementById('analysisRoot');
                            if (!root0) return [];
                            return Array.from(root0.querySelectorAll('[id]'))
                                .filter(function(el) {
                                    if (!el || !el.id) return false;
                                    if (!/^log_/.test(el.id) && !/^group_/.test(el.id) && !/^order_group_/.test(el.id)) return false;
                                    return el.style && el.style.display === 'block';
                                })
                                .map(function(el) { return el.id; });
                        } catch (e) {
                            return [];
                        }
                    })()
                };

                function computeShiftedDate(s, deltaDays) {
                    try {
                        const m = String(s).match(/^(\d{4})-(\d{2})-(\d{2})$/);
                        if (!m) return '';
                        const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
                        d.setDate(d.getDate() + Number(deltaDays || 0));
                        const y = d.getFullYear();
                        const mm = String(d.getMonth() + 1).padStart(2, '0');
                        const dd = String(d.getDate()).padStart(2, '0');
                        return y + '-' + mm + '-' + dd;
                    } catch (e) {
                        return '';
                    }
                }

                function updateHeaderNavForDate(dstr) {
                    try {
                        const header = document.querySelector('header');
                        if (!header) return;
                        const links = header.querySelectorAll('a[data-nav-date]');
                        if (!links || !links.length) return;

                        const prev = computeShiftedDate(dstr, -1);
                        const next = computeShiftedDate(dstr, +1);
                        const dates = [prev, next];

                        const baseUrl = new URL(location.href);
                        const token = baseUrl.searchParams.get('token') || '';
                        const mode = baseUrl.searchParams.get('mode') || 'analysis';

                        links.forEach(function(a, idx) {
                            const target = dates[idx] || '';
                            if (!target) return;
                            a.setAttribute('data-nav-date', target);
                            a.setAttribute('onclick', "if(window.__ordersSetDate){event.preventDefault();event.stopPropagation();window.__ordersSetDate('" + target + "');return false;}");
                            const u = new URL(location.href);
                            if (token) u.searchParams.set('token', token);
                            u.searchParams.set('mode', mode);
                            u.searchParams.set('date', target);
                            u.searchParams.delete('partial');
                            a.setAttribute('href', '?' + u.searchParams.toString());
                        });
                    } catch (e) {}
                }

                const root = document.getElementById('analysisRoot');
                if (!root) {
                    const url0 = new URL(location.href);
                    url0.searchParams.set('mode', 'analysis');
                    url0.searchParams.set('date', dateStr);
                    url0.searchParams.delete('partial');
                    location.href = url0.toString();
                    return;
                }

                const url = new URL(location.href);
                url.searchParams.set('mode', 'analysis');
                url.searchParams.set('date', dateStr);

                // preserve current filter settings from the live forms
                const filterForm = document.getElementById('orderFilterForm');
                if (filterForm) {
                    const fd = new FormData(filterForm);
                    const status = (fd.get('status') || 'all').toString();
                    const sort = (fd.get('sort') || 'time_desc').toString();
                    const owner = (fd.get('owner') || '').toString();
                    const csvFile = (fd.get('csv_file') || '').toString();
                    url.searchParams.set('status', status);
                    url.searchParams.set('sort', sort);
                    if (owner) url.searchParams.set('owner', owner);
                    else url.searchParams.delete('owner');
                    if (csvFile) url.searchParams.set('csv_file', csvFile);
                    else url.searchParams.delete('csv_file');
                    if (fd.get('amount_nonzero')) url.searchParams.set('amount_nonzero', '1');
                    else url.searchParams.delete('amount_nonzero');
                    if (fd.get('group_by_domain')) url.searchParams.set('group_by_domain', '1');
                    else url.searchParams.delete('group_by_domain');
                }

                const rangeForm = document.getElementById('rangeRevenueForm');
                if (rangeForm) {
                    const fd2 = new FormData(rangeForm);
                    const rs = (fd2.get('range_start') || '').toString();
                    const re = (fd2.get('range_end') || '').toString();
                    if (rs) url.searchParams.set('range_start', rs);
                    else url.searchParams.delete('range_start');
                    if (re) url.searchParams.set('range_end', re);
                    else url.searchParams.delete('range_end');
                }

                url.searchParams.delete('partial');

                const fetchUrl = new URL(url.toString());
                fetchUrl.searchParams.set('partial', 'analysis');

                if (controller) controller.abort();
                controller = new AbortController();
                root.style.opacity = '0.55';

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
                    root.innerHTML = html;

                    try {
                        root.querySelectorAll('script').forEach(function(s) {
                            const code = (s && s.textContent) ? String(s.textContent) : '';
                            if (!code.trim()) return;
                            try {
                                (new Function(code))();
                            } catch (e1) {}
                        });
                    } catch (e0) {}

                    try {
                        if (openedState && openedState.ids && openedState.ids.length) {
                            openedState.ids.forEach(function(id) {
                                const el = document.getElementById(id);
                                if (el) el.style.display = 'block';
                            });
                        }
                    } catch (e) {}

                    try {
                        const dp = document.getElementById('mainDatePicker');
                        if (dp) dp.value = dateStr;
                    } catch (e) {}

                    try { updateHeaderNavForDate(dateStr); } catch (e) {}

                    try {
                        const cleanUrl = new URL(url.toString());
                        cleanUrl.searchParams.delete('partial');
                        history.replaceState(null, '', cleanUrl.toString());
                    } catch (e) {}

                    try { initHourlyChart(); } catch (e) {}
                    try { if (typeof window.__initCollapsibleCards === 'function') window.__initCollapsibleCards(); } catch (e) {}
                    try { if (typeof initRangeRevenueInteractions === 'function') initRangeRevenueInteractions(); } catch (e) {}
                    try {
                        if (typeof window.dispatchEvent === 'function') {
                            window.dispatchEvent(new Event('resize'));
                        }
                    } catch (e) {}
                })
                .catch(function(err) {
                    if (err && err.name === 'AbortError') return;
                    location.href = url.toString();
                })
                .finally(function() {
                    root.style.opacity = '1';
                });
            };
        })();
        // 多天营收统计图表：支持局部刷新（partial=range_revenue） + 双端滑块选择区间
        function renderRevenueChartFromData(revenueData, opts) {
            const canvas = document.getElementById('revenueChart');
            if (!canvas || !revenueData || !Array.isArray(revenueData)) return;
            const ctx = canvas.getContext('2d');

            const data = revenueData;
            const showLabel = (data.length <= 5);
            const isPreview = !!(opts && opts.preview);
            const pointR = isPreview ? 3 : 5;
            const pointHoverR = isPreview ? 4 : 7;
            const pointHitR = isPreview ? 8 : 12;

            let focusDate = '';
            try {
                const u = new URL(location.href);
                focusDate = (u.searchParams.get('date') || '').toString();
            } catch (e) {
                focusDate = '';
            }
            if (!focusDate && window.__ordersFocusDate) focusDate = String(window.__ordersFocusDate);

            const labels = data.map(d => d.date);
            const usdSeries = data.map(d => d.usd);
            const conversionSeries = data.map(d => (typeof d.conversion === 'number' ? d.conversion : 0));
            const attemptsSeries = data.map(d => (typeof d.attempts === 'number' ? d.attempts : Number(d.attempts || 0)));
            const focusIdx = focusDate ? labels.indexOf(focusDate) : -1;
            const defaultPointBg = '#6366f1';
            const defaultPointBorder = '#fff';
            const focusPointBg = '#ef4444';
            const focusPointBorder = '#fecaca';
            const pointBgColors = labels.map(function(_, i) { return i === focusIdx ? focusPointBg : defaultPointBg; });
            const pointBorderColors = labels.map(function(_, i) { return i === focusIdx ? focusPointBorder : defaultPointBorder; });
            if (window.revenueChartInstance) {
                try {
                    const instCanvas = window.revenueChartInstance && window.revenueChartInstance.canvas;
                    if (instCanvas && instCanvas !== canvas) {
                        try { window.revenueChartInstance.destroy(); } catch (e3) {}
                        window.revenueChartInstance = null;
                    }
                } catch (e4) {
                    try { window.revenueChartInstance.destroy(); } catch (e5) {}
                    window.revenueChartInstance = null;
                }
            }

            if (window.revenueChartInstance) {
                try {
                    window.revenueChartInstance.data.labels = labels;
                    if (window.revenueChartInstance.data.datasets && window.revenueChartInstance.data.datasets[0]) {
                        window.revenueChartInstance.data.datasets[0].data = usdSeries;
                        window.revenueChartInstance.data.datasets[0].pointRadius = pointR;
                        window.revenueChartInstance.data.datasets[0].pointHoverRadius = pointHoverR;
                        window.revenueChartInstance.data.datasets[0].pointHitRadius = pointHitR;
                        window.revenueChartInstance.data.datasets[0].pointBackgroundColor = pointBgColors;
                        window.revenueChartInstance.data.datasets[0].pointBorderColor = pointBorderColors;
                    }
                    if (window.revenueChartInstance.data.datasets && window.revenueChartInstance.data.datasets[1]) {
                        window.revenueChartInstance.data.datasets[1].data = conversionSeries;
                    }
                    window.revenueChartInstance.__rawData = data;
                    if (window.revenueChartInstance.options && window.revenueChartInstance.options.plugins && window.revenueChartInstance.options.plugins.datalabels) {
                        window.revenueChartInstance.options.plugins.datalabels.display = showLabel;
                    }
                    if (isPreview) {
                        try {
                            window.revenueChartInstance.update(0);
                        } catch (e0) {
                            window.revenueChartInstance.update();
                        }
                    } else {
                        window.revenueChartInstance.update();
                    }
                    return;
                } catch (e) {
                    try { window.revenueChartInstance.destroy(); } catch (e2) {}
                    window.revenueChartInstance = null;
                }
            }

            if (!canvas.__revenueClickBound) {
                canvas.__revenueClickBound = true;
                canvas.addEventListener('click', function(evt) {
                    try {
                        const chart = window.revenueChartInstance;
                        if (!chart || !chart.getElementsAtEventForMode) return;
                        const points = chart.getElementsAtEventForMode(evt, 'nearest', { intersect: false }, true);
                        if (!points || !points.length) return;
                        const idx = points[0].index;
                        const date = (chart.data && chart.data.labels && chart.data.labels[idx]) ? String(chart.data.labels[idx]) : '';
                        if (!date) return;

                        const url = new URL(location.href);
                        url.searchParams.set('mode', 'analysis');
                        url.searchParams.set('date', date);
                        url.searchParams.delete('range_start');
                        url.searchParams.delete('range_end');
                        url.searchParams.delete('partial');

                        if (window.__ordersSetDate) {
                            window.__ordersSetDate(date);
                        } else {
                            location.href = url.toString();
                        }
                    } catch (e) {}
                }, true);
            }

            window.revenueChartInstance = new Chart(ctx, {
                type: 'line',
                data: {
                    labels: labels,
                    datasets: [{
                        label: '日总营收参考',
                        data: usdSeries,
                        borderColor: '#6366f1',
                        backgroundColor: 'rgba(99,102,241,0.08)',
                        fill: true,
                        tension: 0.3,
                        pointRadius: pointR,
                        pointHoverRadius: pointHoverR,
                        pointHitRadius: pointHitR,
                        pointBackgroundColor: pointBgColors,
                        pointBorderColor: pointBorderColors,
                        pointBorderWidth: 2,
                        borderWidth: 3
                    },
                    {
                        label: '转化率(%)',
                        data: conversionSeries,
                        borderColor: '#f59e0b',
                        backgroundColor: 'rgba(245,158,11,0.08)',
                        fill: false,
                        tension: 0.3,
                        yAxisID: 'y1',
                        pointRadius: pointR,
                        pointHoverRadius: pointHoverR,
                        pointHitRadius: pointHitR,
                        pointBackgroundColor: labels.map(function(_, i) { return i === focusIdx ? '#f97316' : '#f59e0b'; }),
                        pointBorderColor: '#fff',
                        borderWidth: 2,
                        borderDash: [4, 4]
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    animation: isPreview ? false : undefined,
                    plugins: {
                        legend: { display: false },
                        tooltip: {
                            callbacks: {
                                label: function(context) {
                                    if (context.datasetIndex === 1) {
                                        try {
                                            const raw = (context && context.chart && context.chart.__rawData) ? context.chart.__rawData : data;
                                            const idx = (typeof context.dataIndex === 'number') ? context.dataIndex : -1;
                                            const at = (idx >= 0 && raw && raw[idx]) ? (raw[idx].attempts || 0) : 0;
                                            return '转化率: ' + context.parsed.y.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + '%  |  尝试: ' + at;
                                        } catch (e) {
                                            return '转化率: ' + context.parsed.y.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + '%';
                                        }
                                    }
                                    return '金额: $' + context.parsed.y.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
                                }
                            }
                        },
                        datalabels: {
                            display: showLabel,
                            color: '#222',
                            align: 'end',
                            anchor: 'end',
                            formatter: function(value) {
                                return value > 0 ? ('$' + value.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })) : '';
                            }
                        }
                    },
                    interaction: {
                        mode: 'nearest',
                        intersect: false
                    },
                    scales: {
                        y: { beginAtZero: true, grid: { color: '#f1f5f9' } },
                        y1: {
                            beginAtZero: true,
                            position: 'right',
                            grid: { drawOnChartArea: false },
                            ticks: {
                                callback: function(value) { return value + '%'; }
                            }
                        },
                        x: { grid: { display: false } }
                    }
                }
            });
        }

        function initRangeRevenueInteractions() {
            const form = document.getElementById('rangeRevenueForm');
            const container = document.getElementById('revenueChartContainer');
            if (!form || !container) return;

            const startInput = form.querySelector('input[name="range_start"]');
            const endInput = form.querySelector('input[name="range_end"]');
            const startSlider = document.getElementById('rangeStartSlider');
            const endSlider = document.getElementById('rangeEndSlider');
            const rangeLabel = document.getElementById('rangeLabel');

            function parseDate(s) {
                if (!s) return null;
                const m = String(s).match(/^(\d{4})-(\d{2})-(\d{2})$/);
                if (!m) return null;
                return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
            }
            function fmtDate(d) {
                const y = d.getFullYear();
                const m = String(d.getMonth() + 1).padStart(2, '0');
                const dd = String(d.getDate()).padStart(2, '0');
                return y + '-' + m + '-' + dd;
            }
            function daysBetween(a, b) {
                const ms = 24 * 3600 * 1000;
                const da = Date.UTC(a.getFullYear(), a.getMonth(), a.getDate());
                const db = Date.UTC(b.getFullYear(), b.getMonth(), b.getDate());
                return Math.round((db - da) / ms);
            }
            function addDays(d, days) {
                const nd = new Date(d.getTime());
                nd.setDate(nd.getDate() + days);
                return nd;
            }

            const MIN_RANGE_DAYS = 5;

            function clampDate(d, minD, maxD) {
                if (!d) return d;
                if (minD && d < minD) return new Date(minD.getTime());
                if (maxD && d > maxD) return new Date(maxD.getTime());
                return d;
            }

            function ensureMinSpan(opts) {
                if (!startInput || !endInput) return false;
                const meta = getMeta();
                const minD = parseDate(meta.min_date);
                const maxD = parseDate(meta.max_date);
                let rs = parseDate(startInput.value);
                let re = parseDate(endInput.value);
                if (!rs || !re || !minD || !maxD) return false;

                rs = clampDate(rs, minD, maxD);
                re = clampDate(re, minD, maxD);

                let changed = false;
                const span = daysBetween(rs, re);
                if (span < MIN_RANGE_DAYS) {
                    const pin = (opts && opts.pin) ? String(opts.pin) : 'end';
                    if (pin === 'start') {
                        re = addDays(rs, MIN_RANGE_DAYS);
                        re = clampDate(re, minD, maxD);
                        if (daysBetween(rs, re) < MIN_RANGE_DAYS) {
                            rs = addDays(re, -MIN_RANGE_DAYS);
                            rs = clampDate(rs, minD, maxD);
                        }
                    } else {
                        rs = addDays(re, -MIN_RANGE_DAYS);
                        rs = clampDate(rs, minD, maxD);
                        if (daysBetween(rs, re) < MIN_RANGE_DAYS) {
                            re = addDays(rs, MIN_RANGE_DAYS);
                            re = clampDate(re, minD, maxD);
                        }
                    }
                    changed = true;
                }

                const rsStr = fmtDate(rs);
                const reStr = fmtDate(re);
                if (startInput.value !== rsStr) {
                    startInput.value = rsStr;
                    changed = true;
                }
                if (endInput.value !== reStr) {
                    endInput.value = reStr;
                    changed = true;
                }
                return changed;
            }

            function getCache() {
                if (!window.__rangeRevenueCache) window.__rangeRevenueCache = {};
                return window.__rangeRevenueCache;
            }

            function seedCacheFromData(arr) {
                const cache = getCache();
                if (!Array.isArray(arr)) return;
                for (const d of arr) {
                    if (!d || !d.date) continue;
                    cache[d.date] = {
                        usd: (typeof d.usd === 'number') ? d.usd : Number(d.usd || 0),
                        conversion: (typeof d.conversion === 'number') ? d.conversion : Number(d.conversion || 0),
                        attempts: (typeof d.attempts === 'number') ? d.attempts : Number(d.attempts || 0)
                    };
                }
            }

            function buildSeriesFromCache(rs, re) {
                const cache = getCache();
                const out = [];
                if (!rs || !re) return out;
                let cur = new Date(rs.getTime());
                const end = new Date(re.getTime());
                while (cur <= end) {
                    const key = fmtDate(cur);
                    const v = (key in cache) ? cache[key] : { usd: 0, conversion: 0, attempts: 0 };
                    out.push({ date: key, usd: v.usd || 0, conversion: v.conversion || 0, attempts: v.attempts || 0 });
                    cur.setDate(cur.getDate() + 1);
                }
                return out;
            }

            function hasMissingInRange(rs, re) {
                const cache = getCache();
                if (!rs || !re) return false;
                let cur = new Date(rs.getTime());
                const end = new Date(re.getTime());
                while (cur <= end) {
                    const key = fmtDate(cur);
                    if (!(key in cache)) return true;
                    cur.setDate(cur.getDate() + 1);
                }
                return false;
            }

            function computeViewDataByInputs() {
                const rs = parseDate(startInput ? startInput.value : '');
                const re = parseDate(endInput ? endInput.value : '');
                if (!rs || !re) return [];
                return buildSeriesFromCache(rs, re);
            }

            let __localPreviewTimer = null;
            function scheduleLocalPreviewRender() {
                if (__localPreviewTimer) return;
                __localPreviewTimer = requestAnimationFrame(function() {
                    __localPreviewTimer = null;
                    const view = computeViewDataByInputs();
                    if (view && view.length) {
                        renderRevenueChartFromData(view, { preview: true });
                    } else {
                        renderRevenueChartFromData(window.__rangeRevenueData || [], { preview: true });
                    }
                });
            }

            function getMeta() {
                return window.__rangeRevenueMeta || {};
            }

            function syncSlidersFromInputs() {
                if (!startInput || !endInput || !startSlider || !endSlider) return;
                ensureMinSpan({ pin: 'end' });
                const meta = getMeta();
                const minD = parseDate(meta.min_date);
                const maxD = parseDate(meta.max_date);
                const rs = parseDate(startInput.value);
                const re = parseDate(endInput.value);
                if (!minD || !maxD || !rs || !re) return;
                const total = Math.max(1, daysBetween(minD, maxD));
                const a = Math.max(0, Math.min(total, daysBetween(minD, rs)));
                const b = Math.max(0, Math.min(total, daysBetween(minD, re)));
                startSlider.value = String(Math.round((a / total) * 100));
                endSlider.value = String(Math.round((b / total) * 100));
                if (rangeLabel) rangeLabel.textContent = startInput.value + ' ~ ' + endInput.value;
            }

            function syncInputsFromSliders() {
                if (!startInput || !endInput || !startSlider || !endSlider) return;
                const meta = getMeta();
                const minD = parseDate(meta.min_date);
                const maxD = parseDate(meta.max_date);
                if (!minD || !maxD) return;
                const total = Math.max(1, daysBetween(minD, maxD));
                let a = Number(startSlider.value || '0');
                let b = Number(endSlider.value || '100');
                if (a > b) {
                    const tmp = a;
                    a = b;
                    b = tmp;
                    startSlider.value = String(a);
                    endSlider.value = String(b);
                }
                const startDay = Math.round((a / 100) * total);
                const endDay = Math.round((b / 100) * total);
                startInput.value = fmtDate(addDays(minD, startDay));
                endInput.value = fmtDate(addDays(minD, endDay));

                const startBefore = startInput.value;
                const endBefore = endInput.value;
                ensureMinSpan({ pin: 'end' });
                if (startBefore !== startInput.value || endBefore !== endInput.value) {
                    syncSlidersFromInputs();
                }
                if (rangeLabel) rangeLabel.textContent = startInput.value + ' ~ ' + endInput.value;
            }

            let controller = null;
            function fetchAndUpdate() {
                const url = new URL(location.href);
                const fd = new FormData(form);
                const token = (fd.get('token') || '').toString();
                const mode = (fd.get('mode') || 'analysis').toString();
                const rs = (fd.get('range_start') || '').toString();
                const re = (fd.get('range_end') || '').toString();

                if (token) url.searchParams.set('token', token);
                url.searchParams.set('mode', mode);
                if (rs) url.searchParams.set('range_start', rs);
                if (re) url.searchParams.set('range_end', re);

                const fetchUrl = new URL(url.toString());
                fetchUrl.searchParams.set('partial', 'range_revenue_json');

                if (controller) controller.abort();
                controller = new AbortController();

                return fetch(fetchUrl.toString(), {
                    method: 'GET',
                    headers: { 'X-Requested-With': 'fetch' },
                    signal: controller.signal
                })
                .then(function(r) { return r.json(); })
                .then(function(payload) {
                    if (!payload || typeof payload !== 'object') return;
                    const meta = payload.meta || {};
                    const data = payload.data || [];

                    window.__rangeRevenueMeta = meta;
                    window.__rangeRevenueData = Array.isArray(data) ? data : [];
                    seedCacheFromData(window.__rangeRevenueData);

                    if (meta && meta.range_start && startInput) startInput.value = meta.range_start;
                    if (meta && meta.range_end && endInput) endInput.value = meta.range_end;
                    if (rangeLabel && startInput && endInput) rangeLabel.textContent = startInput.value + ' ~ ' + endInput.value;

                    const errEl = document.getElementById('rangeRevenueError');
                    const errMsg = (meta && meta.range_error) ? String(meta.range_error) : '';
                    if (errEl) {
                        if (errMsg) {
                            errEl.style.display = 'block';
                            errEl.textContent = errMsg;
                        } else {
                            errEl.style.display = 'none';
                            errEl.textContent = '';
                        }
                    }

                    syncSlidersFromInputs();
                    scheduleLocalPreviewRender();

                    try { if (typeof window.__syncExportRangeFromCurrent === 'function') window.__syncExportRangeFromCurrent(); } catch (e) {}
                })
                .catch(function(err) {
                    if (err && err.name === 'AbortError') return;
                    location.href = url.toString();
                });
            }

            let __rangeFetchTimer = null;
            seedCacheFromData(window.__rangeRevenueData || []);

            let __ensureTimer = null;
            let __ensureLast = 0;
            const __ensureWaitMs = 160;
            let __ensureController = null;
            function ensureRangeData() {
                const rs = parseDate(startInput ? startInput.value : '');
                const re = parseDate(endInput ? endInput.value : '');
                if (!rs || !re) return;
                if (!hasMissingInRange(rs, re)) return;

                const url = new URL(location.href);
                const fd = new FormData(form);
                const token = (fd.get('token') || '').toString();
                const mode = (fd.get('mode') || 'analysis').toString();
                const rsStr = (fd.get('range_start') || '').toString();
                const reStr = (fd.get('range_end') || '').toString();

                if (token) url.searchParams.set('token', token);
                url.searchParams.set('mode', mode);
                if (rsStr) url.searchParams.set('range_start', rsStr);
                if (reStr) url.searchParams.set('range_end', reStr);
                url.searchParams.set('partial', 'range_revenue_json');

                if (__ensureController) __ensureController.abort();
                __ensureController = new AbortController();

                fetch(url.toString(), {
                    method: 'GET',
                    headers: { 'X-Requested-With': 'fetch' },
                    signal: __ensureController.signal
                })
                .then(function(r) { return r.json(); })
                .then(function(payload) {
                    if (!payload || typeof payload !== 'object') return;
                    const data = payload.data || [];
                    if (Array.isArray(data)) seedCacheFromData(data);
                    scheduleLocalPreviewRender();
                })
                .catch(function(err) {
                    if (err && err.name === 'AbortError') return;
                });
            }

            function scheduleEnsureRangeData(forceNow) {
                const now = Date.now();
                if (forceNow) {
                    if (__ensureTimer) {
                        clearTimeout(__ensureTimer);
                        __ensureTimer = null;
                    }
                    __ensureLast = now;
                    ensureRangeData();
                    return;
                }
                const elapsed = now - __ensureLast;
                if (elapsed >= __ensureWaitMs) {
                    __ensureLast = now;
                    ensureRangeData();
                    return;
                }
                if (__ensureTimer) return;
                __ensureTimer = setTimeout(function() {
                    __ensureTimer = null;
                    __ensureLast = Date.now();
                    ensureRangeData();
                }, __ensureWaitMs - elapsed);
            }

            form.addEventListener('submit', function(ev) {
                ev.preventDefault();
                ensureMinSpan({ pin: 'end' });
                syncSlidersFromInputs();
                fetchAndUpdate();
            });
            if (startInput) startInput.addEventListener('change', function() {
                ensureMinSpan({ pin: 'start' });
                syncSlidersFromInputs();
                scheduleLocalPreviewRender();
                scheduleEnsureRangeData(true);
            });
            if (endInput) endInput.addEventListener('change', function() {
                ensureMinSpan({ pin: 'end' });
                syncSlidersFromInputs();
                scheduleLocalPreviewRender();
                scheduleEnsureRangeData(true);
            });

            if (startSlider) {
                startSlider.addEventListener('input', function() {
                    syncInputsFromSliders();
                    scheduleLocalPreviewRender();
                    scheduleEnsureRangeData(false);
                });
                startSlider.addEventListener('change', function() {
                    syncInputsFromSliders();
                    scheduleLocalPreviewRender();
                    scheduleFetchAndUpdate(true);
                });
            }
            if (endSlider) {
                endSlider.addEventListener('input', function() {
                    syncInputsFromSliders();
                    scheduleLocalPreviewRender();
                    scheduleEnsureRangeData(false);
                });
                endSlider.addEventListener('change', function() {
                    syncInputsFromSliders();
                    scheduleLocalPreviewRender();
                    scheduleFetchAndUpdate(true);
                });
            }

            // 初始渲染 + 初始化联动
            syncSlidersFromInputs();
            renderRevenueChartFromData(window.__rangeRevenueData || []);
        }

        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', initRangeRevenueInteractions);
        } else {
            initRangeRevenueInteractions();
        }

        window.__syncExportRangeFromCurrent = function() {
            try {
                const btn = document.querySelector('[data-export-range-btn="1"]');
                if (!btn) return;
                const form = btn.closest('form');
                if (!form) return;
                const rsEl = form.querySelector('input[name="range_start"]');
                const reEl = form.querySelector('input[name="range_end"]');
                if (!rsEl || !reEl) return;

                // prefer current rangeRevenueForm values if present, fallback to URL
                const rf = document.getElementById('rangeRevenueForm');
                if (rf) {
                    const fd = new FormData(rf);
                    const rs2 = (fd.get('range_start') || '').toString();
                    const re2 = (fd.get('range_end') || '').toString();
                    if (rs2) rsEl.value = rs2;
                    if (re2) reEl.value = re2;
                }

                if (!rsEl.value || !reEl.value) {
                    const u = new URL(location.href);
                    const rs = (u.searchParams.get('range_start') || '').toString();
                    const re = (u.searchParams.get('range_end') || '').toString();
                    if (rs) rsEl.value = rs;
                    if (re) reEl.value = re;
                }
            } catch (e) {}
        };

        try {
            document.addEventListener('click', function(e) {
                const t = e && e.target ? e.target : null;
                if (!t) return;
                if (t && t.matches && t.matches('[data-export-range-btn="1"]')) {
                    try { window.__syncExportRangeFromCurrent(); } catch (e2) {}
                }
            }, true);
        } catch (e) {}

        try { window.__syncExportRangeFromCurrent(); } catch (e) {}

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
            initHourlyChart();
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