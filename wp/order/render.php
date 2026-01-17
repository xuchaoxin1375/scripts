<?php

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
                <input type="hidden" name="pending_as_success" value="<?= (isset($_GET['pending_as_success']) && (string)$_GET['pending_as_success'] === '0') ? '0' : '1' ?>">
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
            <div id="revenueChartLoading" style="width:100%; height:180px; min-height:180px; display:flex; align-items:center; justify-content:center;">
                <div style="display:flex; align-items:center; gap:10px; color:#64748b; font-size:13px; font-weight:700;">
                    <span class="mini-spinner" style="width:18px; height:18px; border-radius:999px; border:2px solid #e2e8f0; border-top-color:#6366f1; display:inline-block;"></span>
                    <span>加载中…</span>
                </div>
            </div>
            <div id="revenueChartContent" style="width:100%; height:180px; min-height:180px; display:none;">
                <canvas id="revenueChart" style="width:100%; height:180px; min-height:180px;"></canvas>
            </div>
            <div id="revenueChartLegend" style="margin-top:6px; font-size:12px; color:#64748b; line-height:1.35; display:flex; flex-wrap:wrap; gap:10px; align-items:center;">
                <span style="display:inline-flex; align-items:center; gap:6px;"><span style="width:10px; height:10px; border-radius:999px; background:#6366f1; display:inline-block;"></span><span>左轴: 营收(USD)</span></span>
                <span style="display:inline-flex; align-items:center; gap:6px;"><span style="width:10px; height:10px; border-radius:999px; background:#f59e0b; display:inline-block;"></span><span>右轴: 转化率(%)</span></span>
                <span style="display:inline-flex; align-items:center; gap:6px;"><span style="width:10px; height:10px; border-radius:999px; background:#10b981; display:inline-block;"></span><span>右轴: 尝试次数</span></span>
                <span style="font-size:11px; color:#94a3b8;">(点击折线点可跳转到对应日期)</span>
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
    $pending_as_success0 = true;
    if (isset($_GET['pending_as_success']) && (string)$_GET['pending_as_success'] === '0') {
        $pending_as_success0 = false;
    }
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
                class="label">成功单量<?php if ($pending_as_success0): ?><span style="font-size:12px; font-weight:400; opacity:.75;">(包括pending)</span><?php endif; ?></span><span class="value"
                style="color:var(--success);"><?= $stats['total_success'] ?></span></div>
            <div class="overview-card" style="border-bottom: 3px solid #a855f7;"><span class="label">待定单量 <span style="font-size:12px; font-weight:400; opacity:.75;">一般可视为成功</span></span><span class="value"
                style="color:#a855f7;"><?= (int)($stats['total_pending'] ?? 0) ?></span></div>
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
                $revenue_days = compute_range_revenue_days($range_start, $range_end, $pending_as_success0);
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
                            <?php
                                $dom_usd_sum = (float)($stats['domain_usd_sum'][$dom] ?? 0);
                                $dom_orders = $stats['domain_success_orders'][$dom] ?? [];
                                $dom_orders_cnt = is_array($dom_orders) ? count($dom_orders) : 0;
                                $dom_id = 'dom_rev_' . md5((string)$dom);
                            ?>
                            <li class="ranking-item">
                                <?php
                                    $side_has_people = (bool)($csv_data_for_side['meta']['has_people'] ?? false);
                                    $side_has_country = (bool)($csv_data_for_side['meta']['has_country'] ?? false);
                                    $side_has_category = (bool)($csv_data_for_side['meta']['has_category'] ?? false);
                                    $side_has_date = (bool)($csv_data_for_side['meta']['has_date'] ?? false);
                                    $dom_key_side = normalize_domain_key((string)$dom);
                                    $owner_side = ($dom_key_side !== '' && isset($csv_data_for_side['map'][$dom_key_side])) ? $csv_data_for_side['map'][$dom_key_side] : null;
                                    $people_side = $owner_side ? trim((string)($owner_side['people'] ?? '')) : '';
                                    $country_side = $owner_side ? trim((string)($owner_side['country'] ?? '')) : '';
                                    $category_side = $owner_side ? trim((string)($owner_side['category'] ?? '')) : '';
                                    $site_date_side = $owner_side ? trim((string)($owner_side['date'] ?? '')) : '';
                                ?>
                                <div style="min-width:0; flex:1;">
                                    <div style="display:flex; align-items:center; gap:10px; min-width:0;">
                                        <span class="rank-num"><?= $rank_i ?></span>
                                        <span class="dom-name" style="max-width: 300px;" title="<?= htmlspecialchars($dom) ?>"><?= htmlspecialchars($dom) ?></span>
                                    </div>
                                    <?php if ($side_has_people || $side_has_country || $side_has_category || $side_has_date): ?>
                                        <div class="ranking-meta">
                                            <?php if ($side_has_people): ?>
                                                <span class="ranking-badge ranking-badge-people">人员:<?= $people_side !== '' ? htmlspecialchars($people_side) : '未匹配' ?></span>
                                            <?php endif; ?>
                                            <?php if ($side_has_country && $country_side !== ''): ?>
                                                <span class="ranking-badge ranking-badge-country"><?= htmlspecialchars($country_side) ?></span>
                                            <?php endif; ?>
                                            <?php if ($side_has_category && $category_side !== ''): ?>
                                                <span class="ranking-badge ranking-badge-category">内容:<?= htmlspecialchars($category_side) ?></span>
                                            <?php endif; ?>
                                            <?php if ($side_has_date && $site_date_side !== ''): ?>
                                                <span class="ranking-badge ranking-badge-date">建站:<?= htmlspecialchars($site_date_side) ?></span>
                                            <?php endif; ?>
                                        </div>
                                    <?php endif; ?>
                                </div>
                                <div style="text-align:right;">
                                    <?php foreach ($currs as $c => $v): ?>
                                        <div class="dom-val"><?= $c ?>             <?= format_money($v) ?></div>
                                    <?php endforeach; ?>
                                    <div class="dom-val" style="color:#0ea5e9;">USD            <?= format_money($dom_usd_sum) ?></div>
                                    <?php if ($dom_orders_cnt > 1): ?>
                                        <div style="margin-top:6px;">
                                            <button type="button" class="nav-btn" style="padding:6px 10px; font-size:12px;" onclick="(function(){var el=document.getElementById('<?= $dom_id ?>'); if(!el) return; el.style.display=(el.style.display==='none'?'block':'none');})();">展开/收起(<?= (int)$dom_orders_cnt ?>)</button>
                                        </div>
                                    <?php endif; ?>
                                </div>
                            </li>
                            <?php if ($dom_orders_cnt > 1): ?>
                                <li id="<?= $dom_id ?>" style="display:none; padding:10px 12px; margin:-8px 0 10px 0; border-radius:12px; background:#f8fafc; border:1px solid #e2e8f0;">
                                    <div style="font-size:12px; color:#64748b; margin-bottom:6px;">成功单明细</div>
                                    <?php foreach ($dom_orders as $od): ?>
                                        <div style="display:flex; justify-content:space-between; gap:10px; font-size:12px; padding:6px 0; border-top:1px dashed #e2e8f0;">
                                            <div style="min-width:0;">
                                                <div style="font-weight:600; color:#334155;">#<?= htmlspecialchars((string)($od['order_no'] ?? '')) ?></div>
                                                <div style="color:#94a3b8;"><?= htmlspecialchars((string)($od['time'] ?? '')) ?></div>
                                            </div>
                                            <div style="text-align:right; white-space:nowrap;">
                                                <div style="color:#334155;"><?= htmlspecialchars((string)($od['cur'] ?? '')) ?> <?= format_money((float)($od['amt'] ?? 0)) ?></div>
                                                <div style="color:#0ea5e9;">USD <?= format_money((float)($od['usd_amt'] ?? 0)) ?></div>
                                                <div style="color:#0ea5e9;">Basis <?= htmlspecialchars((string)($od['usd_basis'] ?? '')) ?></div>
                                            </div>
                                        </div>
                                    <?php endforeach; ?>
                                </li>
                            <?php endif; ?>
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
                            <input type="hidden" name="pending_as_success" value="<?= $pending_as_success0 ? '1' : '0' ?>">
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
                                <?php if (!$pending_as_success0): ?>
                                <option value="pending" <?= $status_filter == 'pending' ? 'selected' : '' ?>>🟨 待定组</option>
                                <?php endif; ?>
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
                            <label style="font-size:13px; color:#475569; display:flex; align-items:center; gap:4px;">
                                <input type="hidden" name="cluster_prefix6" value="0">
                                <input type="checkbox" name="cluster_prefix6" value="1" onchange="window.__ordersFilterChange ? window.__ordersFilterChange(this.form) : this.form.submit()" <?= (!isset($_GET['cluster_prefix6']) || (string)$_GET['cluster_prefix6'] !== '0') ? 'checked' : '' ?>>
                                前6位相同的单号合并
                            </label>
                        </form>

                        <?php
                            $matched_fields0 = $csv_data_for_side['meta']['matched_fields'] ?? [];
                            $matched_headers0 = $csv_data_for_side['meta']['matched_headers'] ?? [];
                            $csv_encoding0 = (string)($csv_data_for_side['meta']['encoding'] ?? '');
                            $field_labels = [
                                'domain' => '域名',
                                'people' => '人员',
                                'country' => '国家',
                                'category' => '内容',
                                'date' => '日期',
                                'server' => '服务器',
                            ];
                        ?>
                        <?php if (!empty($csv_path)): ?>
                            <div class="order-filter-note" style="margin-top:10px; font-size:12px; color:#94a3b8; line-height:1.3;">
                                <span style="font-weight:700;">注:</span>
                                <span>CSV已识别字段</span>
                                <?php if (trim($csv_encoding0) !== ''): ?>
                                    <span style="margin-left:6px; opacity:.75;">(encoding: <?= htmlspecialchars($csv_encoding0) ?>)</span>
                                <?php endif; ?>
                                <?php if (!empty($matched_fields0) && is_array($matched_fields0)): ?>
                                    <?php
                                        $parts = [];
                                        foreach ($matched_fields0 as $fk) {
                                            $lab = $field_labels[$fk] ?? $fk;
                                            $hdr = (string)($matched_headers0[$fk] ?? '');
                                            $parts[] = $hdr !== '' ? ($lab . '(' . $hdr . ')') : $lab;
                                        }
                                    ?>
                                    <span>：<?= htmlspecialchars(implode('，', $parts)) ?></span>
                                <?php else: ?>
                                    <span style="color:#c2410c; font-weight:700;">：未命中任何有用字段（可能选错CSV）</span>
                                <?php endif; ?>
                            </div>
                        <?php endif; ?>
                    </div>
                </div>

                <div class="order-list" id="orderListContainer"><?= render_order_list_items($analysis_data, $group_by_domain, $order_sort, $status_filter, $owner_filter, $csv_path, $list_view) ?></div>
            </div>


        </div>
    <?php
    return ob_get_clean();
}
