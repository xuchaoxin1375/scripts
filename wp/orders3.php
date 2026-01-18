<?php
require_once __DIR__ . '/order/config.php';
require_once __DIR__ . '/order/utils.php';
require_once __DIR__ . '/order/csv.php';
require_once __DIR__ . '/order/stats.php';
require_once __DIR__ . '/order/render.php';
require_once __DIR__ . '/order/list.php';
require_once __DIR__ . '/order/parser.php';
require_once __DIR__ . '/order/auth.php';
require_once __DIR__ . '/order/range.php';
require_once __DIR__ . '/order/export.php';
require_once __DIR__ . '/order/controller.php';

// ====== 配置与权限控制 ======
orders3_require_token($access_token);

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
$cluster_prefix6 = true;
if (isset($_GET['cluster_prefix6']) && (string)$_GET['cluster_prefix6'] === '0') {
    $cluster_prefix6 = false;
}
$amount_nonzero = isset($_GET['amount_nonzero']) ? (bool)$_GET['amount_nonzero'] : false;
$group_by_domain = isset($_GET['group_by_domain']) ? (bool)$_GET['group_by_domain'] : false;
$pending_as_success = true;
if (isset($_GET['pending_as_success']) && (string)$_GET['pending_as_success'] === '0') {
    $pending_as_success = false;
}
if ($pending_as_success && $status_filter === 'pending') {
    $status_filter = 'all';
}
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
    'total_pending' => 0,
    'total_usd_sum' => 0,
    'revenue_by_currency' => ['USD' => 0, 'EUR' => 0, 'GBP' => 0],
    'unique_domains' => 0,
    'domain_amount' => [],
    'domain_usd_sum' => [],
    'domain_success_orders' => [],
    'hourly_attempts' => array_fill(0, 24, 0),
    'hourly_success' => array_fill(0, 24, 0),
];

if ($view_mode === 'analysis') {
    [$analysis_data, $stats] = orders3_build_analysis_data_and_stats($log_files, $pending_as_success, $amount_nonzero);
}

if (orders3_handle_partials_and_exports(
    $access_token,
    $view_mode,
    $log_date,
    $analysis_data,
    $stats,
    $group_by_domain,
    $order_sort,
    $status_filter,
    $owner_filter,
    $csv_selected,
    $amount_nonzero,
    $pending_as_success,
    $list_view
)) {
    exit;
}
?>
<!DOCTYPE html>
<html lang="zh-CN">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PP ORDERS <?= htmlspecialchars($APP_VERSION) ?></title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <link rel="stylesheet" href="/forpay/order/assets/orders3.css.php?v=<?= urlencode($APP_VERSION) ?>">
</head>

<body>

    <div class="container">
        <header>
            <div class="header-top">
                <h2 style="margin:0;">🛡️ 支付监控中心 <small style="font-size:12px; opacity:0.6; font-weight:normal;"><?= htmlspecialchars($APP_VERSION) ?>

                </small></h2>
                <div style="display: flex; gap: 10px; align-items: center;">
                
                    <div id="mainDatePickerWrap" style="background: rgba(255,255,255,0.1); padding: 4px; border-radius: 10px; display: flex; align-items:center; gap:6px; cursor:pointer;">
                        <a href="?token=<?= $access_token ?>&date=<?= $prev_date ?>&mode=<?= $view_mode ?>&pending_as_success=<?= $pending_as_success ? '1' : '0' ?>"
                            class="nav-btn" data-nav-date="<?= $prev_date ?>" onclick="if(window.__ordersSetDate){event.preventDefault();event.stopPropagation();window.__ordersSetDate('<?= $prev_date ?>');return false;}" style="background:transparent; padding:8px;">«</a>
                        <input type="date" id="mainDatePicker" value="<?= $log_date ?>"
                            onchange="window.__ordersSetDate ? window.__ordersSetDate(this.value) : (location.href='?token=<?= $access_token ?>&mode=<?= $view_mode ?>&date='+this.value)"
                            style="background:transparent; border:none; color:white; font-weight:bold; width:130px; text-align:center; cursor:pointer;">
                        <a href="?token=<?= $access_token ?>&date=<?= $next_date ?>&mode=<?= $view_mode ?>&pending_as_success=<?= $pending_as_success ? '1' : '0' ?>"
                            class="nav-btn" data-nav-date="<?= $next_date ?>" onclick="if(window.__ordersSetDate){event.preventDefault();event.stopPropagation();window.__ordersSetDate('<?= $next_date ?>');return false;}" style="background:transparent; padding:8px;">»</a>
                        <button type="button" class="nav-btn" id="quickTodayBtn" style="font-size:12px;">今天</button>
                        <button type="button" class="nav-btn" id="quickPickBtn" style="font-size:12px;">选择日期…</button>
                    </div>
          
                        <a
                        id="goAnalysisBtn"
                        class="nav-btn <?= $view_mode === 'analysis' ? 'active' : '' ?>"
                        href="?<?= http_build_query(array_merge($_GET, ['mode' => 'analysis', 'pending_as_success' => ($pending_as_success ? '1' : '0')])) ?>"
                        style="font-weight:800;">
                        📊分析
                    </a>
                    <a
                        id="goRawBtn"
                        class="nav-btn <?= $view_mode !== 'analysis' ? 'active' : '' ?>"
                        href="?<?= http_build_query(array_merge($_GET, ['mode' => 'raw', 'pending_as_success' => ($pending_as_success ? '1' : '0')])) ?>"
                        style="font-weight:800;">
                        📝源码
                    </a>
                    <label style="font-size:12px; color:rgba(255,255,255,0.85); display:flex; align-items:center; gap:6px; user-select:none; white-space:nowrap; padding:6px 10px; border-radius:12px; background: rgba(255,255,255,0.08); border:1px solid rgba(255,255,255,0.12);">
                        <input type="checkbox" id="pendingAsSuccessToggle" <?= $pending_as_success ? 'checked' : '' ?> style="width:14px; height:14px;">
                        待定计入成功
                    </label>
                    <?php if ($view_mode === 'analysis'): ?>
                        <form method="get" style="display:flex; align-items:center; gap:8px; margin-left:8px;">
                            <input type="hidden" name="token" value="<?= htmlspecialchars($access_token) ?>">
                            <input type="hidden" name="mode" value="analysis">
                            <input type="hidden" name="export" value="orders_csv">
                            <input type="hidden" name="status" value="<?= htmlspecialchars($status_filter) ?>">
                            <input type="hidden" name="sort" value="<?= htmlspecialchars($order_sort) ?>">
                            <input type="hidden" name="owner" value="<?= htmlspecialchars($owner_filter) ?>">
                            <input type="hidden" name="csv_file" value="<?= htmlspecialchars($csv_selected) ?>">
                            <input type="hidden" name="pending_as_success" value="<?= $pending_as_success ? '1' : '0' ?>">
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
                    <button type="button" class="nav-btn" id="headerCollapseBtn" title="收起页眉" aria-label="收起页眉" style="background:rgba(255,255,255,0.14);">收起</button>
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
                            // 对 success.log 去重(源码查看模式)
                            if ($target_file_key === 'success' && !empty($lines)) {
                                $lines = array_values(array_unique($lines));
                            }
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
            // 图表显示参数设置
            window.__ORDERS3_CHART_CFG = window.__ORDERS3_CHART_CFG || {
                hourly: {
                    axisFontMobile: 9,
                    axisFontDesktop: 12,
                    legendFontMobile: 10,
                    legendFontDesktop: 12,
                    xMaxTicksMobile: 12,
                    xMaxTicksDesktop: 12,
                    gridColorX: '#e2e8f0',
                    gridColorY: '#e2e8f0',
                    gridLineWidthX: 2,
                    gridLineWidthY: 2,
                    gridDrawTicks: false,
                    pointRadiusMobile: 2,
                    pointRadiusDesktop: 3,
                    pointHoverRadiusMobile: 3,
                    pointHoverRadiusDesktop: 4,
                },
                revenue: {
                    axisFontMobile: 9,
                    axisFontDesktop: 12,
                    legendFontMobile: 10,
                    legendFontDesktop: 12,
                    xMaxTicksMobile: 4,
                    xMaxTicksDesktop: 8,
                    chartHeightMobile: 180,
                    chartHeightDesktop: 240,
                    gridColorX: '#e2e8f0',
                    gridColorY: '#e2e8f0',
                    gridLineWidthX: 1,
                    gridLineWidthY: 1,
                    gridDrawTicks: false,
                    pointRadiusMobile: 1.5,
                    pointRadiusDesktop: 3,
                    pointHoverRadiusMobile: 2.5,
                    pointHoverRadiusDesktop: 4,
                    pointHitRadiusMobile: 8,
                    pointHitRadiusDesktop: 14,
                }
            };

            window.__applyRevenueChartHeight = function() {
                try {
                    const isMobile = (window.matchMedia && window.matchMedia('(max-width: 900px)').matches);
                    const cfg = (window.__ORDERS3_CHART_CFG && window.__ORDERS3_CHART_CFG.revenue) ? window.__ORDERS3_CHART_CFG.revenue : {};
                    const h = isMobile ? (cfg.chartHeightMobile || 220) : (cfg.chartHeightDesktop || 240);

                    const loadingEl = document.getElementById('revenueChartLoading');
                    const contentEl = document.getElementById('revenueChartContent');
                    const canvasEl = document.getElementById('revenueChart');

                    const loadingEl2 = document.getElementById('peopleChartLoading');
                    const contentEl2 = document.getElementById('peopleChartContent');
                    const canvasEl2 = document.getElementById('peopleChart');

                    if (loadingEl) {
                        loadingEl.style.height = h + 'px';
                        loadingEl.style.minHeight = h + 'px';
                    }
                    if (contentEl) {
                        contentEl.style.height = h + 'px';
                        contentEl.style.minHeight = h + 'px';
                    }
                    if (canvasEl) {
                        canvasEl.style.height = h + 'px';
                        canvasEl.style.minHeight = h + 'px';
                    }

                    if (loadingEl2) {
                        loadingEl2.style.height = h + 'px';
                        loadingEl2.style.minHeight = h + 'px';
                    }
                    if (contentEl2) {
                        contentEl2.style.height = h + 'px';
                        contentEl2.style.minHeight = h + 'px';
                    }
                    if (canvasEl2) {
                        canvasEl2.style.height = h + 'px';
                        canvasEl2.style.minHeight = h + 'px';
                    }
                } catch (e) {}
            };

            try { window.__applyRevenueChartHeight(); } catch (e) {}
            const mainDatePicker = document.getElementById('mainDatePicker');
            const mainDatePickerWrap = document.getElementById('mainDatePickerWrap');
            const pendingAsSuccessToggle = document.getElementById('pendingAsSuccessToggle');
            const quickTodayBtn = document.getElementById('quickTodayBtn');
            const quickPickBtn = document.getElementById('quickPickBtn');
            const goAnalysisBtn = document.getElementById('goAnalysisBtn');
            const goRawBtn = document.getElementById('goRawBtn');

            if (mainDatePicker) {
                mainDatePicker.addEventListener('click', function(e) {
                    try { if (e) e.stopPropagation(); } catch (e0) {}
                    try {
                        mainDatePicker.showPicker ? mainDatePicker.showPicker() : mainDatePicker.focus();
                    } catch (e2) {
                        try { mainDatePicker.focus(); } catch (e3) {}
                    }
                }, true);
            }

            if (mainDatePickerWrap && mainDatePicker) {
                mainDatePickerWrap.addEventListener('click', function(e) {
                    const t = e && e.target ? e.target : null;
                    if (t && t.closest && t.closest('a,button,input,select,textarea')) return;
                    try {
                        mainDatePicker.showPicker ? mainDatePicker.showPicker() : mainDatePicker.focus();
                    } catch (e2) {
                        try { mainDatePicker.focus(); } catch (e3) {}
                    }
                }, true);
            }

            if (pendingAsSuccessToggle) {
                pendingAsSuccessToggle.addEventListener('change', function() {
                    const v = pendingAsSuccessToggle.checked ? '1' : '0';
                    try {
                        const ff = document.getElementById('orderFilterForm');
                        if (ff) {
                            const h = ff.querySelector('input[name="pending_as_success"]');
                            if (h) h.value = v;
                        }
                        const rf = document.getElementById('rangeRevenueForm');
                        if (rf) {
                            const h2 = rf.querySelector('input[name="pending_as_success"]');
                            if (h2) h2.value = v;
                        }
                    } catch (e) {}

                    try {
                        const u = new URL(location.href);
                        u.searchParams.set('pending_as_success', v);
                        u.searchParams.delete('partial');
                        history.replaceState(null, '', u.toString());
                    } catch (e) {}

                    const ds = (mainDatePicker && mainDatePicker.value) ? String(mainDatePicker.value) : '';
                    if (window.__ordersSetDate && /^\d{4}-\d{2}-\d{2}$/.test(ds)) {
                        window.__ordersSetDate(ds);
                    } else {
                        try {
                            const u2 = new URL(location.href);
                            u2.searchParams.set('mode', 'analysis');
                            if (ds) u2.searchParams.set('date', ds);
                            u2.searchParams.set('pending_as_success', v);
                            u2.searchParams.delete('partial');
                            location.href = u2.toString();
                        } catch (e2) {
                            location.href = `?token=<?= $access_token ?>&mode=analysis&date=${ds}&pending_as_success=${v}`;
                        }
                    }
                }, true);
            }

            if (goAnalysisBtn && mainDatePicker) {
                goAnalysisBtn.addEventListener('click', function(e) {
                    const v = (mainDatePicker.value || '').toString();
                    if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) return;
                    e.preventDefault();
                    e.stopPropagation();
                    if (window.__ordersSetDate) {
                        window.__ordersSetDate(v);
                        return;
                    }
                    try {
                        const u = new URL(location.href);
                        const pas = (pendingAsSuccessToggle && pendingAsSuccessToggle.checked) ? '1' : '0';
                        u.searchParams.set('mode', 'analysis');
                        u.searchParams.set('date', v);
                        u.searchParams.set('pending_as_success', pas);
                        u.searchParams.delete('partial');
                        location.href = u.toString();
                    } catch (e2) {
                        const pas = (pendingAsSuccessToggle && pendingAsSuccessToggle.checked) ? '1' : '0';
                        location.href = `?token=<?= $access_token ?>&mode=analysis&date=${v}&pending_as_success=${pas}`;
                    }
                }, true);
            }

            if (goRawBtn && mainDatePicker) {
                goRawBtn.addEventListener('click', function(e) {
                    const v = (mainDatePicker.value || '').toString();
                    if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) return;
                    e.preventDefault();
                    e.stopPropagation();
                    try {
                        const u = new URL(location.href);
                        const pas = (pendingAsSuccessToggle && pendingAsSuccessToggle.checked) ? '1' : '0';
                        u.searchParams.set('mode', 'raw');
                        u.searchParams.set('date', v);
                        u.searchParams.set('pending_as_success', pas);
                        u.searchParams.delete('partial');
                        location.href = u.toString();
                    } catch (e2) {
                        const pas = (pendingAsSuccessToggle && pendingAsSuccessToggle.checked) ? '1' : '0';
                        location.href = `?token=<?= $access_token ?>&mode=raw&date=${v}&pending_as_success=${pas}`;
                    }
                }, true);
            }
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
                const headerH = headerEl ? headerEl.getBoundingClientRect().height : 0;

                if (window.matchMedia && window.matchMedia('(min-width: 900px)').matches === false) {
                    document.documentElement.style.removeProperty('--sticky-filter-top');
                    document.documentElement.style.removeProperty('--sticky-side-top');
                } else {
                    document.documentElement.style.setProperty('--sticky-filter-top', (Math.round(headerH)) + 'px');

                    // 左侧汇总/榜单贴近页眉即可，不要被“实时解析列表”筛选栏高度顶开
                    document.documentElement.style.setProperty('--sticky-side-top', (Math.round(headerH + 12)) + 'px');
                }
            }
            window.addEventListener('resize', updateStickyOffsets);
            document.addEventListener('DOMContentLoaded', updateStickyOffsets);
            updateStickyOffsets();
        })();
        (function() {
            try {
                if (document.getElementById('miniSpinnerKeyframes')) return;
                const style = document.createElement('style');
                style.id = 'miniSpinnerKeyframes';
                style.textContent = '@keyframes miniSpin{0%{transform:rotate(0deg)}100%{transform:rotate(360deg)}}.mini-spinner{animation:miniSpin 1.6s linear infinite;}';
                document.head.appendChild(style);
            } catch (e) {}
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
                            collapsed = false;
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
                const pendingAsSuccess = (fd.get('pending_as_success') || '1').toString();
                const clusterPrefix6 = (function(){
                    const el = form.querySelector('input[name="cluster_prefix6"][type="checkbox"]');
                    if (!el) return true;
                    return !!el.checked;
                })();

                const isJumpStatus = (status === 'success' || status === 'fail');
                const shouldJump = (!groupByDomain) && isJumpStatus && (window.event && window.event.target && window.event.target.name === 'status');
                const triggerName = (window.event && window.event.target && window.event.target.name) ? window.event.target.name : '';

                if (token) url.searchParams.set('token', token);
                if (date) url.searchParams.set('date', date);
                url.searchParams.set('mode', 'analysis');
                url.searchParams.set('status', status);
                url.searchParams.set('sort', sort);
                url.searchParams.set('pending_as_success', pendingAsSuccess === '0' ? '0' : '1');

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

                url.searchParams.set('cluster_prefix6', clusterPrefix6 ? '1' : '0');

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
            const isMobile = (window.matchMedia && window.matchMedia('(max-width: 900px)').matches);
            const cfg = (window.__ORDERS3_CHART_CFG && window.__ORDERS3_CHART_CFG.hourly) ? window.__ORDERS3_CHART_CFG.hourly : {};
            const axisFontSize = isMobile ? (cfg.axisFontMobile || 9) : (cfg.axisFontDesktop || 12);
            const legendFontSize = isMobile ? (cfg.legendFontMobile || 10) : (cfg.legendFontDesktop || 12);
            const pointR = isMobile ? (cfg.pointRadiusMobile || 2) : (cfg.pointRadiusDesktop || 3);
            const pointHoverR = isMobile ? (cfg.pointHoverRadiusMobile || 3) : (cfg.pointHoverRadiusDesktop || 4);
            const xMaxTicks = isMobile ? (cfg.xMaxTicksMobile || 5) : (cfg.xMaxTicksDesktop || 12);
            const gridColorX = cfg.gridColorX || '#e2e8f0';
            const gridColorY = cfg.gridColorY || '#e2e8f0';
            const gridLineWidthX = (typeof cfg.gridLineWidthX === 'number') ? cfg.gridLineWidthX : 2;
            const gridLineWidthY = (typeof cfg.gridLineWidthY === 'number') ? cfg.gridLineWidthY : 2;
            const gridDrawTicks = (typeof cfg.gridDrawTicks === 'boolean') ? cfg.gridDrawTicks : false;
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
                        borderColor: '#6366f1', backgroundColor: 'rgba(99, 102, 241, 0.05)', fill: true, tension: 0.4, borderWidth: 2, pointRadius: pointR, pointHoverRadius: pointHoverR
                    }, {
                        label: '成功次数', data: success,
                        borderColor: '#10b981', backgroundColor: 'transparent', borderDash: [5, 5], tension: 0.4, borderWidth: 2, pointRadius: pointR, pointHoverRadius: pointHoverR
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    interaction: { intersect: false, mode: 'index' },
                    layout: {
                        padding: isMobile ? { top: 4, right: 6, bottom: 0, left: 4 } : { top: 8, right: 12, bottom: 0, left: 8 }
                    },
                    plugins: { legend: { position: 'top', labels: { usePointStyle: true, boxSize: 6, font: { size: legendFontSize } } } },
                    scales: {
                        y: { beginAtZero: true, grid: { color: gridColorY, lineWidth: gridLineWidthY, drawTicks: gridDrawTicks }, ticks: { stepSize: 1, font: { size: axisFontSize } } },
                        x: { grid: { display: true, color: gridColorX, lineWidth: gridLineWidthX, drawTicks: gridDrawTicks }, ticks: { font: { size: axisFontSize }, maxTicksLimit: xMaxTicks, autoSkip: true, maxRotation: 0 } }
                    }
                }
            });

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

                // 需求：切换分析日期时不要刷新多日统计（range revenue 模块），避免曲线丢失/跳变。
                // 这里在局部刷新前先暂存当前模块 DOM，刷新后再恢复。
                let __rangeRevenueSnapshot = null;
                try {
                    const rr = document.getElementById('revenueChartContainer');
                    if (rr && rr.parentNode) {
                        __rangeRevenueSnapshot = rr;
                    }
                } catch (e) {
                    __rangeRevenueSnapshot = null;
                }

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
                    const pendingAsSuccess = (fd.get('pending_as_success') || '1').toString();
                    url.searchParams.set('status', status);
                    url.searchParams.set('sort', sort);
                    url.searchParams.set('pending_as_success', pendingAsSuccess === '0' ? '0' : '1');
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

                url.searchParams.delete('range_chart_h');

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

                    // restore range revenue module (do not refresh)
                    try {
                        if (__rangeRevenueSnapshot) {
                            const newRR = document.getElementById('revenueChartContainer');
                            if (newRR && newRR.parentNode) {
                                newRR.parentNode.replaceChild(__rangeRevenueSnapshot, newRR);
                            }
                        }
                    } catch (e) {}

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
                    // 注意：这里刻意不再调用 initRangeRevenueInteractions / applyRevenueChartHeight / renderPeopleChartFromData。
                    // 因为我们在切换日期时选择“保留原多日统计模块不刷新”。
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

            const isMobile = (window.matchMedia && window.matchMedia('(max-width: 900px)').matches);
            const cfg = (window.__ORDERS3_CHART_CFG && window.__ORDERS3_CHART_CFG.revenue) ? window.__ORDERS3_CHART_CFG.revenue : {};
            const axisFontSize = isMobile ? (cfg.axisFontMobile || 9) : (cfg.axisFontDesktop || 12);
            const legendFontSize = isMobile ? (cfg.legendFontMobile || 9) : (cfg.legendFontDesktop || 12);
            const mobilePointR = isMobile ? (cfg.pointRadiusMobile || 1.5) : (cfg.pointRadiusDesktop || 3);
            const mobilePointHoverR = isMobile ? (cfg.pointHoverRadiusMobile || 2.5) : (cfg.pointHoverRadiusDesktop || 4);
            const mobilePointHitR = isMobile ? (cfg.pointHitRadiusMobile || 8) : (cfg.pointHitRadiusDesktop || 14);
            const xMaxTicks = isMobile ? (cfg.xMaxTicksMobile || 4) : (cfg.xMaxTicksDesktop || 8);
            const gridColorX = cfg.gridColorX || '#e2e8f0';
            const gridColorY = cfg.gridColorY || '#e2e8f0';
            const gridLineWidthX = (typeof cfg.gridLineWidthX === 'number') ? cfg.gridLineWidthX : 2;
            const gridLineWidthY = (typeof cfg.gridLineWidthY === 'number') ? cfg.gridLineWidthY : 2;
            const gridDrawTicks = (typeof cfg.gridDrawTicks === 'boolean') ? cfg.gridDrawTicks : false;

            function shortDateLabel(v) {
                const s = (v == null) ? '' : String(v);
                const m = s.match(/^(\d{4})-(\d{2})-(\d{2})$/);
                if (!m) return s;
                return m[2] + '-' + m[3];
            }

            function syncRevenueAxesVisibility(chart) {
                try {
                    if (!chart || !chart.options || !chart.options.scales) return;
                    const scales = chart.options.scales;
                    const ds = (chart.data && chart.data.datasets) ? chart.data.datasets : [];

                    function isVisibleByIndex(i) {
                        try { return !chart.isDatasetVisible(i); } catch (e) {}
                        return false;
                    }

                    const visible0 = ds[0] ? chart.isDatasetVisible(0) : false; // revenue
                    const visible1 = ds[1] ? chart.isDatasetVisible(1) : false; // conversion
                    const visible2 = ds[2] ? chart.isDatasetVisible(2) : false; // attempts
                    const visible3 = ds[3] ? chart.isDatasetVisible(3) : false; // success orders

                    if (scales.y) scales.y.display = !!visible0;
                    if (scales.y1) scales.y1.display = !!visible1;
                    if (scales.y2) scales.y2.display = !!visible2;
                    if (scales.y3) scales.y3.display = !!visible3;
                } catch (e) {}
            }

            const shouldDeferShow = !!(opts && opts.deferShow);
            try {
                const loadingEl = document.getElementById('revenueChartLoading');
                const contentEl = document.getElementById('revenueChartContent');
                if (shouldDeferShow) {
                    if (loadingEl) loadingEl.style.display = 'flex';
                    if (contentEl) contentEl.style.display = 'none';
                } else {
                    if (loadingEl) loadingEl.style.display = 'none';
                    if (contentEl) contentEl.style.display = 'block';
                }
            } catch (e) {}

            const data = revenueData;
            const showLabel = (data.length <= 5);
            const isPreview = !!(opts && opts.preview);
            const pointR = mobilePointR;
            const pointHoverR = mobilePointHoverR;
            const pointHitR = mobilePointHitR;

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
            const successOrdersSeries = data.map(d => (typeof d.success_orders === 'number' ? d.success_orders : Number(d.success_orders || 0)));
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
                    if (window.revenueChartInstance.data.datasets && window.revenueChartInstance.data.datasets[2]) {
                        window.revenueChartInstance.data.datasets[2].data = attemptsSeries;
                    }
                    if (window.revenueChartInstance.data.datasets && window.revenueChartInstance.data.datasets[3]) {
                        window.revenueChartInstance.data.datasets[3].data = successOrdersSeries;
                    }
                    window.revenueChartInstance.__rawData = data;
                    syncRevenueAxesVisibility(window.revenueChartInstance);
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
                        const isMobileNow = (window.matchMedia && window.matchMedia('(max-width: 900px)').matches);
                        if (isMobileNow) return;
                        const chart = window.revenueChartInstance;
                        if (!chart || !chart.getElementsAtEventForMode) return;
                        const points = chart.getElementsAtEventForMode(evt, 'index', { intersect: false }, true);
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

            if (!window.__orders3MobileTooltipDismissBound) {
                window.__orders3MobileTooltipDismissBound = true;
                document.addEventListener('click', function(ev) {
                    try {
                        const isMobileNow = (window.matchMedia && window.matchMedia('(max-width: 900px)').matches);
                        if (!isMobileNow) return;

                        const t = ev && ev.target ? ev.target : null;
                        const revCanvas = document.getElementById('revenueChart');
                        const pplCanvas = document.getElementById('peopleChart');

                        const clickedInRevenue = !!(revCanvas && t && (revCanvas === t || revCanvas.contains(t)));
                        const clickedInPeople = !!(pplCanvas && t && (pplCanvas === t || pplCanvas.contains(t)));
                        if (clickedInRevenue || clickedInPeople) return;

                        function hideTooltipForChart(ch) {
                            if (!ch || !ch.tooltip) return;
                            try {
                                ch.tooltip.setActiveElements([], { x: 0, y: 0 });
                                ch.update();
                            } catch (e0) {
                                try {
                                    ch.tooltip._active = [];
                                    ch.update();
                                } catch (e1) {}
                            }
                        }

                        hideTooltipForChart(window.revenueChartInstance);
                        hideTooltipForChart(window.peopleChartInstance);
                    } catch (e) {}
                }, true);
            }

            window.revenueChartInstance = new Chart(ctx, {
                type: 'line',
                data: {
                    labels: labels,
                    datasets: [{
                        label: '营收(USD)',
                        data: usdSeries,
                        borderColor: '#ef4444',
                        backgroundColor: 'transparent',
                        fill: false,
                        tension: 0.3,
                        pointRadius: pointR,
                        pointHoverRadius: pointHoverR,
                        pointHitRadius: pointHitR,
                        pointBackgroundColor: labels.map(function(_, i) { return i === focusIdx ? '#b91c1c' : '#ef4444'; }),
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
                    },
                    {
                        label: '尝试次数',
                        data: attemptsSeries,
                        borderColor: '#64748b',
                        backgroundColor: 'rgba(100,116,139,0.06)',
                        fill: false,
                        tension: 0.3,
                        yAxisID: 'y2',
                        pointRadius: pointR,
                        pointHoverRadius: pointHoverR,
                        pointHitRadius: pointHitR,
                        pointBackgroundColor: '#64748b',
                        pointBorderColor: '#fff',
                        borderDash: [6, 4],
                        borderWidth: 2
                    },
                    {
                        label: '成单数量',
                        data: successOrdersSeries,
                        borderColor: '#10b981',
                        backgroundColor: 'rgba(16,185,129,0.06)',
                        fill: false,
                        tension: 0.3,
                        yAxisID: 'y3',
                        pointRadius: pointR,
                        pointHoverRadius: pointHoverR,
                        pointHitRadius: pointHitR,
                        pointBackgroundColor: '#10b981',
                        pointBorderColor: '#fff',
                        borderWidth: 2
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    animation: isPreview ? false : undefined,
                    layout: {
                        padding: isMobile ? { top: 4, right: 6, bottom: 0, left: 4 } : { top: 8, right: 12, bottom: 0, left: 8 }
                    },
                    interaction: {
                        mode: 'index',
                        intersect: false
                    },
                    plugins: {
                        legend: {
                            display: true,
                            position: 'top',
                            labels: { usePointStyle: true, boxSize: 6, font: { size: legendFontSize } },
                            onClick: function(e, legendItem, legend) {
                                try {
                                    const chart = legend && legend.chart ? legend.chart : null;
                                    if (!chart) return;

                                    // 关键：不同 Chart.js 版本对 legendItem / toggle API 的实现不完全一致。
                                    // 这里直接调用 Chart.js 内置的默认 legend 点击处理（等价于“曲线开关”原生行为），
                                    // 然后我们再同步坐标轴显示/隐藏，确保开关一定生效。
                                    const defaultOnClick = (Chart && Chart.defaults && Chart.defaults.plugins && Chart.defaults.plugins.legend && Chart.defaults.plugins.legend.onClick)
                                        ? Chart.defaults.plugins.legend.onClick
                                        : null;
                                    if (typeof defaultOnClick === 'function') {
                                        defaultOnClick.call(this, e, legendItem, legend);
                                    }

                                    syncRevenueAxesVisibility(chart);
                                    chart.update();
                                } catch (err) {}
                            }
                        },
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
                                    if (context.datasetIndex === 2) {
                                        return '尝试次数: ' + context.parsed.y.toLocaleString();
                                    }
                                    if (context.datasetIndex === 3) {
                                        return '成单数量: ' + context.parsed.y.toLocaleString();
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
                        mode: 'index',
                        intersect: false
                    },
                    scales: {
                        y: {
                            beginAtZero: true,
                            grid: { color: gridColorY, lineWidth: gridLineWidthY, drawTicks: gridDrawTicks },
                            ticks: { color: '#ef4444', font: { size: axisFontSize } }
                        },
                        y1: {
                            beginAtZero: true,
                            position: 'right',
                            grid: { drawOnChartArea: false, drawTicks: gridDrawTicks },
                            ticks: {
                                color: '#f59e0b',
                                font: { size: axisFontSize },
                                callback: function(value) { return value + '%'; }
                            }
                        },
                        y2: {
                            beginAtZero: true,
                            position: 'right',
                            grid: { drawOnChartArea: false, drawTicks: gridDrawTicks },
                            ticks: {
                                color: '#64748b',
                                font: { size: axisFontSize },
                                callback: function(value) { return value; }
                            }
                        },
                        y3: {
                            beginAtZero: true,
                            position: 'right',
                            grid: { drawOnChartArea: false, drawTicks: gridDrawTicks },
                            ticks: {
                                color: '#10b981',
                                font: { size: axisFontSize },
                                callback: function(value) { return value; }
                            }
                        },
                        x: {
                            grid: { display: true, color: gridColorX, lineWidth: gridLineWidthX, drawTicks: gridDrawTicks },
                            ticks: {
                                color: '#64748b',
                                font: { size: axisFontSize },
                                maxRotation: isMobile ? 0 : 35,
                                minRotation: 0,
                                autoSkip: true,
                                maxTicksLimit: xMaxTicks,
                                callback: function(value, index, ticks) {
                                    if (!isMobile) return this.getLabelForValue(value);
                                    try {
                                        return shortDateLabel(this.getLabelForValue(value));
                                    } catch (e) {
                                        return this.getLabelForValue(value);
                                    }
                                }
                            }
                        }
                    }
                }
            });

            syncRevenueAxesVisibility(window.revenueChartInstance);
            if (window.revenueChartInstance) window.revenueChartInstance.update();
            if (shouldDeferShow) {
                const reveal = function() {
                    try {
                        const loadingEl = document.getElementById('revenueChartLoading');
                        const contentEl = document.getElementById('revenueChartContent');
                        if (loadingEl) loadingEl.style.display = 'none';
                        if (contentEl) contentEl.style.display = 'block';
                    } catch (e) {}
                };
                // 首屏/刷新加载延迟显示图表，延迟时间
                const revealDelay = 800;
                try {
                    requestAnimationFrame(function() {
                        setTimeout(reveal, revealDelay);
                    });
                } catch (e) {
                    setTimeout(reveal, revealDelay);
                }
            }
        }

        // 人员多日业绩图表（独立于营收图表，避免拥挤）
        function renderPeopleChartFromData(revenueData, opts) {
            const container = document.getElementById('peopleChartContainer');
            const canvas = document.getElementById('peopleChart');
            if (!container || !canvas) return;

            const ctx = canvas.getContext('2d');

            const isMobile = (window.matchMedia && window.matchMedia('(max-width: 900px)').matches);
            const cfg = (window.__ORDERS3_CHART_CFG && window.__ORDERS3_CHART_CFG.revenue) ? window.__ORDERS3_CHART_CFG.revenue : {};
            const axisFontSize = isMobile ? (cfg.axisFontMobile || 9) : (cfg.axisFontDesktop || 12);
            const legendFontSize = isMobile ? (cfg.legendFontMobile || 9) : (cfg.legendFontDesktop || 12);
            const xMaxTicks = isMobile ? (cfg.xMaxTicksMobile || 4) : (cfg.xMaxTicksDesktop || 8);
            const gridColorX = cfg.gridColorX || '#e2e8f0';
            const gridColorY = cfg.gridColorY || '#e2e8f0';
            const gridLineWidthX = (typeof cfg.gridLineWidthX === 'number') ? cfg.gridLineWidthX : 2;
            const gridLineWidthY = (typeof cfg.gridLineWidthY === 'number') ? cfg.gridLineWidthY : 2;
            const gridDrawTicks = (typeof cfg.gridDrawTicks === 'boolean') ? cfg.gridDrawTicks : false;

            function shortDateLabel(s) {
                try {
                    const m = String(s).match(/^(\d{4})-(\d{2})-(\d{2})$/);
                    if (!m) return s;
                    return m[2] + '-' + m[3];
                } catch (e) {
                    return s;
                }
            }

            function formatUsdLocal(v) {
                try {
                    const n = Number(v);
                    if (!isFinite(n)) return '$0';
                    if (typeof Intl !== 'undefined' && Intl.NumberFormat) {
                        return new Intl.NumberFormat('en-US', {
                            style: 'currency',
                            currency: 'USD',
                            maximumFractionDigits: 2
                        }).format(n);
                    }
                    return '$' + n.toFixed(2);
                } catch (e) {
                    try {
                        const n2 = Number(v);
                        return '$' + (isFinite(n2) ? n2.toFixed(2) : '0');
                    } catch (e2) {
                        return '$0';
                    }
                }
            }

            function buildPeopleSeries(rawArr) {
                const peopleSet = {};
                for (const row of (rawArr || [])) {
                    const pm = row && row.people_usd ? row.people_usd : null;
                    if (!pm || typeof pm !== 'object') continue;
                    for (const k in pm) {
                        if (!Object.prototype.hasOwnProperty.call(pm, k)) continue;
                        const name = String(k || '').trim();
                        if (!name) continue;
                        peopleSet[name] = true;
                    }
                }
                const people = Object.keys(peopleSet);
                people.sort(function(a, b) { return a.localeCompare(b, 'zh'); });

                const series = {};
                for (const p of people) {
                    series[p] = (rawArr || []).map(function(row) {
                        const pm = row && row.people_usd ? row.people_usd : null;
                        if (!pm || typeof pm !== 'object') return 0;
                        const v = pm[p];
                        return (typeof v === 'number') ? v : Number(v || 0);
                    });
                }
                return { people: people, series: series };
            }

            function hashInt(name) {
                const s = String(name || '');
                let h = 0;
                for (let i = 0; i < s.length; i++) {
                    h = ((h << 5) - h) + s.charCodeAt(i);
                    h |= 0;
                }
                return h;
            }

            const PALETTE = [
                '#E6194B', // Red
                '#3CB44B', // Green
                '#63625cff', // Yellow
                '#4363D8', // Blue
                '#F58231', // Orange
                '#911EB4', // Purple
                '#42D4F4', // Cyan
                '#F032E6', // Magenta
                '#BFEF45', // Lime
                '#9A6324'  // Brown
            ];
            const DASHES = [
                [],
                [6, 4],
                [2, 4],
                [10, 4],
                [12, 3, 2, 3],
                [3, 3],
                [2, 2],
                [8, 2, 2, 2],
                [1, 3]
            ];
            const POINTS = ['circle', 'rect', 'triangle', 'rectRot', 'cross', 'star', 'line', 'dash'];

            function styleForIndex(i, total) {
                const idx = Math.abs(Number(i || 0)) % PALETTE.length;
                const dense = Number(total || 0) > 6;
                const didx = Math.abs(Number(i || 0)) % DASHES.length;
                const pidx = Math.abs(Number(i || 0)) % POINTS.length;
                return {
                    color: PALETTE[idx],
                    dash: dense ? DASHES[didx] : [],
                    pointStyle: POINTS[pidx]
                };
            }

            function renderPeopleQuickControls(chart, peopleNames) {
                try {
                    const legendWrap = document.getElementById('peopleChartLegend');
                    if (!legendWrap) return;
                    legendWrap.innerHTML = '';

                    const bar = document.createElement('div');
                    bar.style.display = 'flex';
                    bar.style.flexWrap = 'wrap';
                    bar.style.gap = '8px';
                    bar.style.alignItems = 'center';
                    bar.style.margin = '6px 0 10px 0';

                    function mkBtn(text, onClick) {
                        const b = document.createElement('button');
                        b.type = 'button';
                        b.innerText = text;
                        b.style.padding = '6px 10px';
                        b.style.border = '1px solid #e2e8f0';
                        b.style.background = '#fff';
                        b.style.borderRadius = '8px';
                        b.style.cursor = 'pointer';
                        b.addEventListener('click', function(e) {
                            try { e.preventDefault(); } catch (e0) {}
                            try { e.stopPropagation(); } catch (e1) {}
                            try { if (typeof onClick === 'function') onClick(); } catch (e2) {}
                        });
                        return b;
                    }

                    function applyVisibility(mode) {
                        if (!chart) return;
                        const ds = (chart.data && chart.data.datasets) ? chart.data.datasets : [];
                        if (!ds.length) return;
                        for (let i = 0; i < ds.length; i++) {
                            const isVisible = chart.isDatasetVisible(i);
                            if (mode === 'all') {
                                chart.setDatasetVisibility(i, true);
                            } else if (mode === 'none') {
                                chart.setDatasetVisibility(i, false);
                            } else if (mode === 'invert') {
                                chart.setDatasetVisibility(i, !isVisible);
                            }
                        }
                        chart.update();
                    }

                    bar.appendChild(mkBtn('全选', function() { applyVisibility('all'); }));
                    bar.appendChild(mkBtn('全不选', function() { applyVisibility('none'); }));
                    bar.appendChild(mkBtn('反选', function() { applyVisibility('invert'); }));

                    const tip = document.createElement('span');
                    tip.innerText = '提示：可在图例上点选人员曲线进行开关。';
                    tip.style.color = '#64748b';
                    tip.style.fontSize = '12px';
                    tip.style.marginLeft = '6px';
                    bar.appendChild(tip);

                    legendWrap.appendChild(bar);
                } catch (e) {}
            }

            const data = revenueData;
            const labels = data.map(function(d) { return d && d.date ? d.date : ''; });
            const built = buildPeopleSeries(data);
            const peopleNames = built.people;
            const peopleSeriesMap = built.series;

            const hasPeople = !!(peopleNames && peopleNames.length);
            if (!hasPeople) {
                try {
                    const loadingEl = document.getElementById('peopleChartLoading');
                    const contentEl = document.getElementById('peopleChartContent');
                    if (loadingEl) loadingEl.style.display = 'none';
                    if (contentEl) contentEl.style.display = 'none';
                    container.style.display = 'none';
                } catch (e) {}
                if (window.peopleChartInstance) {
                    try { window.peopleChartInstance.destroy(); } catch (e2) {}
                    window.peopleChartInstance = null;
                }
                return;
            }

            const shouldDeferShow = !!(opts && opts.deferShow);
            try {
                container.style.display = 'block';
                const loadingEl = document.getElementById('peopleChartLoading');
                const contentEl = document.getElementById('peopleChartContent');
                if (shouldDeferShow) {
                    if (loadingEl) loadingEl.style.display = 'flex';
                    if (contentEl) contentEl.style.display = 'none';
                } else {
                    if (loadingEl) loadingEl.style.display = 'none';
                    if (contentEl) contentEl.style.display = 'block';
                }
            } catch (e) {}

            if (window.peopleChartInstance) {
                try {
                    window.peopleChartInstance.data.labels = labels;
                    const dsAll = (window.peopleChartInstance.data && window.peopleChartInstance.data.datasets) ? window.peopleChartInstance.data.datasets : [];
                    for (const pname of peopleNames) {
                        const label = '人员:' + pname;
                        const idx = dsAll.findIndex(function(d) { return d && d.label === label; });
                        if (idx >= 0) {
                            dsAll[idx].data = peopleSeriesMap[pname] || [];
                        }
                    }
                    window.peopleChartInstance.update();
                    return;
                } catch (e) {
                    try { window.peopleChartInstance.destroy(); } catch (e2) {}
                    window.peopleChartInstance = null;
                }
            }

            window.peopleChartInstance = new Chart(ctx, {
                type: 'line',
                data: {
                    labels: labels,
                    datasets: (peopleNames || []).map(function(pname, i) {
                        const st = styleForIndex(i, (peopleNames || []).length);
                        return {
                            label: '人员:' + pname,
                            data: peopleSeriesMap[pname] || [],
                            borderColor: st.color,
                            backgroundColor: 'transparent',
                            fill: false,
                            tension: 0.25,
                            borderWidth: 2,
                            borderDash: st.dash,
                            pointStyle: st.pointStyle,
                            pointRadius: 2.6,
                            pointHoverRadius: 5.2,
                            pointHitRadius: 10,
                            pointBackgroundColor: '#ffffff',
                            pointBorderColor: st.color,
                            pointBorderWidth: 2,
                            hidden: false
                        };
                    })
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    animation: (opts && opts.preview) ? false : undefined,
                    layout: {
                        padding: isMobile ? { top: 4, right: 6, bottom: 0, left: 4 } : { top: 8, right: 12, bottom: 0, left: 8 }
                    },
                    interaction: {
                        mode: 'index',
                        intersect: false
                    },
                    // 显式指定事件列表，避免某些情况下（页面局部刷新/覆盖层）导致 tooltip 不触发
                    events: ['mousemove', 'mouseout', 'click', 'touchstart', 'touchmove'],
                    plugins: {
                        legend: {
                            display: true,
                            position: 'top',
                            labels: { usePointStyle: false, boxWidth: 22, boxHeight: 2, font: { size: legendFontSize } },
                            onClick: function(e, legendItem, legend) {
                                try {
                                    const defaultOnClick = (Chart && Chart.defaults && Chart.defaults.plugins && Chart.defaults.plugins.legend && Chart.defaults.plugins.legend.onClick)
                                        ? Chart.defaults.plugins.legend.onClick
                                        : null;
                                    if (typeof defaultOnClick === 'function') {
                                        defaultOnClick.call(this, e, legendItem, legend);
                                    }
                                    const chart = legend && legend.chart ? legend.chart : null;
                                    if (chart) chart.update();
                                } catch (e) {}
                            }
                        },
                        tooltip: {
                            enabled: true,
                            callbacks: {
                                label: function(context) {
                                    const val = context && context.parsed ? context.parsed.y : null;
                                    return (context.dataset && context.dataset.label ? context.dataset.label : '') + ': ' + formatUsdLocal(val);
                                }
                            }
                        }
                    },
                    scales: {
                        y: {
                            beginAtZero: true,
                            grid: { color: gridColorY, lineWidth: gridLineWidthY, drawTicks: gridDrawTicks },
                            ticks: { color: '#64748b', font: { size: axisFontSize } }
                        },
                        x: {
                            grid: { display: true, color: gridColorX, lineWidth: gridLineWidthX, drawTicks: gridDrawTicks },
                            ticks: {
                                color: '#64748b',
                                font: { size: axisFontSize },
                                maxRotation: isMobile ? 0 : 35,
                                minRotation: 0,
                                autoSkip: true,
                                maxTicksLimit: xMaxTicks,
                                callback: function(value, index, ticks) {
                                    if (!isMobile) return this.getLabelForValue(value);
                                    try {
                                        return shortDateLabel(this.getLabelForValue(value));
                                    } catch (e) {
                                        return this.getLabelForValue(value);
                                    }
                                }
                            }
                        }
                    }
                }
            });

            if (shouldDeferShow) {
                const reveal = function() {
                    try {
                        const loadingEl = document.getElementById('peopleChartLoading');
                        const contentEl = document.getElementById('peopleChartContent');
                        if (loadingEl) loadingEl.style.display = 'none';
                        if (contentEl) contentEl.style.display = 'block';
                    } catch (e) {}
                };
                const revealDelay = 800;
                try {
                    requestAnimationFrame(function() {
                        setTimeout(reveal, revealDelay);
                    });
                } catch (e) {
                    setTimeout(reveal, revealDelay);
                }
            }

            try { renderPeopleQuickControls(window.peopleChartInstance, peopleNames || []); } catch (e) {}
        }

        function initRangeRevenueInteractions() {
            const form = document.getElementById('rangeRevenueForm');
            const container = document.getElementById('revenueChartContainer');
            if (!form || !container) return;

            try {
                const loadingEl = document.getElementById('revenueChartLoading');
                const contentEl = document.getElementById('revenueChartContent');
                if (loadingEl) loadingEl.style.display = 'flex';
                if (contentEl) contentEl.style.display = 'none';
            } catch (e) {}

            try {
                const loadingEl2 = document.getElementById('peopleChartLoading');
                const contentEl2 = document.getElementById('peopleChartContent');
                if (loadingEl2) loadingEl2.style.display = 'flex';
                if (contentEl2) contentEl2.style.display = 'none';
            } catch (e) {}

            const startInput = form.querySelector('input[name="range_start"]');
            const endInput = form.querySelector('input[name="range_end"]');
            const startSlider = document.getElementById('rangeStartSlider');
            const endSlider = document.getElementById('rangeEndSlider');

            function getFocusDateStr() {
                try {
                    const u = new URL(location.href);
                    const ds = (u.searchParams.get('date') || '').toString();
                    if (ds) return ds;
                } catch (e) {}
                try {
                    if (window.__ordersFocusDate) return String(window.__ordersFocusDate);
                } catch (e) {}
                return '';
            }

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

            function resetRangeAroundCenter(centerStr) {
                if (!startInput || !endInput) return false;
                const meta = getMeta();
                const minD = parseDate(meta.min_date);
                const maxD = parseDate(meta.max_date);
                const c = parseDate(centerStr);
                if (!minD || !maxD || !c) return false;
                let rs = addDays(c, -5);
                let re = addDays(c, 5);
                rs = clampDate(rs, minD, maxD);
                re = clampDate(re, minD, maxD);
                const rsStr = fmtDate(rs);
                const reStr = fmtDate(re);
                const changed = (startInput.value !== rsStr) || (endInput.value !== reStr);
                startInput.value = rsStr;
                endInput.value = reStr;
                return changed;
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
                        attempts: (typeof d.attempts === 'number') ? d.attempts : Number(d.attempts || 0),
                        // 关键：把 success_orders 也写入缓存。
                        // 否则在拖动区间滑块时（本地预览/基于缓存重建序列），成单数量会一直使用旧值或变成 0，导致曲线“不会跟着区间变化”。
                        success_orders: (typeof d.success_orders === 'number') ? d.success_orders : Number(d.success_orders || 0),
                        people_usd: (d && d.people_usd && typeof d.people_usd === 'object') ? d.people_usd : null
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
                    // 关键：默认值也要包含 success_orders。
                    // 否则缓存缺失日期会导致该序列不连续/不随区间变化。
                    const v = (key in cache) ? cache[key] : { usd: 0, conversion: 0, attempts: 0, success_orders: 0, people_usd: null };
                    out.push({
                        date: key,
                        usd: v.usd || 0,
                        conversion: v.conversion || 0,
                        attempts: v.attempts || 0,
                        success_orders: v.success_orders || 0,
                        people_usd: v.people_usd || null
                    });
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
                        renderPeopleChartFromData(view, { preview: true });
                    } else {
                        renderRevenueChartFromData(window.__rangeRevenueData || [], { preview: true });
                        renderPeopleChartFromData(window.__rangeRevenueData || [], { preview: true });
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
            }

            let controller = null;
            function fetchAndUpdate() {
                try {
                    const loadingEl = document.getElementById('revenueChartLoading');
                    const contentEl = document.getElementById('revenueChartContent');
                    if (loadingEl) loadingEl.style.display = 'flex';
                    if (contentEl) contentEl.style.display = 'none';
                } catch (e) {}

                const url = new URL(location.href);
                const fd = new FormData(form);
                const token = (fd.get('token') || '').toString();
                const mode = (fd.get('mode') || 'analysis').toString();
                const rs = (fd.get('range_start') || '').toString();
                const re = (fd.get('range_end') || '').toString();
                const pendingAsSuccess = (fd.get('pending_as_success') || '1').toString();

                if (token) url.searchParams.set('token', token);
                url.searchParams.set('mode', mode);
                url.searchParams.set('pending_as_success', pendingAsSuccess === '0' ? '0' : '1');
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

                    try {
                        const loadingEl = document.getElementById('revenueChartLoading');
                        const contentEl = document.getElementById('revenueChartContent');
                        if (loadingEl) loadingEl.style.display = 'none';
                        if (contentEl) contentEl.style.display = 'block';
                    } catch (e) {}

                    try {
                        const loadingEl2 = document.getElementById('peopleChartLoading');
                        const contentEl2 = document.getElementById('peopleChartContent');
                        if (loadingEl2) loadingEl2.style.display = 'none';
                        if (contentEl2) contentEl2.style.display = 'block';
                    } catch (e) {}

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
                const pendingAsSuccess = (fd.get('pending_as_success') || '1').toString();
                const mode = (fd.get('mode') || 'analysis').toString();
                const rsStr = (fd.get('range_start') || '').toString();
                const reStr = (fd.get('range_end') || '').toString();

                if (token) url.searchParams.set('token', token);
                url.searchParams.set('pending_as_success', pendingAsSuccess === '0' ? '0' : '1');
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
                resetRangeAroundCenter(getFocusDateStr());
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
                    scheduleEnsureRangeData(true);
                    fetchAndUpdate();
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
                    scheduleEnsureRangeData(true);
                    fetchAndUpdate();
                });
            }

            // 初始渲染 + 初始化联动
            try {
                const f = getFocusDateStr();
                if (f) resetRangeAroundCenter(f);
            } catch (e) {}
            syncSlidersFromInputs();
            renderRevenueChartFromData(window.__rangeRevenueData || [], { deferShow: true });
            renderPeopleChartFromData(window.__rangeRevenueData || [], { deferShow: true });
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