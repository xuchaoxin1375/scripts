<?php

function export_orders_csv_range($access_token, $range_start, $range_end, $status_filter, $owner_filter, $amount_nonzero, $csv_selected)
{
    require_once __DIR__ . '/parser.php';
    require_once __DIR__ . '/utils.php';
    require_once __DIR__ . '/csv.php';
    require_once __DIR__ . '/range.php';

    [$min_date0, $max_date0] = find_available_log_date_range();
    $range_error0 = validate_date_range($range_start, $range_end, $min_date0, $max_date0);
    if ($range_error0 !== '') {
        header('Content-Type: text/plain; charset=UTF-8');
        echo $range_error0;
        return;
    }

    $csv_files = list_csv_files_in_dir(dirname(__DIR__));
    $csv_path = resolve_selected_csv_path(dirname(__DIR__), $csv_selected, $csv_files);
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
        'pay_no',
        'status',
        'is_success',
        'has_success_log',
        'is_pending',
        'attempts',
        'notify_count',
        'amount',
        'currency',
        'usd_amount',
        'usd_basis',
        'error',
        'notify_errors',
        'people',
        'server',
        'country',
        'category',
        'site_date',
        'csv_file',
        'forpay_new_lines',
        'forpay_lines',
        'notify_lines',
        'success_lines',
    ];
    fputcsv($out, $headers);

    $csv_files = list_csv_files_in_dir(dirname(__DIR__));
    $csv_path = resolve_selected_csv_path(dirname(__DIR__), $csv_selected, $csv_files);
    $csv_data = load_domain_owner_map_from_csv($csv_path);
    $domain_owner_map = $csv_data['map'] ?? [];

    $pending_as_success = true;
    if (isset($_GET['pending_as_success']) && (string)$_GET['pending_as_success'] === '0') {
        $pending_as_success = false;
    }

    $cur = strtotime($range_start);
    $end = strtotime($range_end);
    while ($cur <= $end) {
        $date = date('Y-m-d', $cur);

        $log_files = [
            'forpay_new' => $date . 'forpay_new.log',
            'forpay' => $date . 'forpay.log',
            'notify' => $date . 'notify.log',
            'success' => $date . 'success.log',
        ];

        [$analysis_data, $_stats] = orders3_build_analysis_data_and_stats($log_files, $pending_as_success, (bool)$amount_nonzero);

        foreach (($analysis_data ?? []) as $no => $item) {
            if (!is_array($item)) continue;
            if (!order_matches_status_filter($item, $status_filter)) continue;

            $pay_no = '';
            try {
                $logs0 = is_array($item['logs'] ?? null) ? $item['logs'] : [];
                $scanTypes = ['forpay', 'notify', 'success', 'forpay_new'];
                foreach ($scanTypes as $tp) {
                    $arr = $logs0[$tp] ?? null;
                    if (!is_array($arr) || empty($arr)) continue;
                    foreach ($arr as $line0) {
                        if (!is_string($line0) || $line0 === '') continue;
                        if (preg_match('/(?:^|[?&])pay_no=([^&\s]+)/', $line0, $mPay)) {
                            $pay_no = (string)($mPay[1] ?? '');
                            break 2;
                        }
                    }
                }
            } catch (Throwable $e) {
                $pay_no = '';
            }

            $oi = get_owner_info_for_domain($item['domain'] ?? '', $domain_owner_map);
            $people = $oi ? trim((string)($oi['people'] ?? '')) : '';
            if (!owner_match_filter($people, $owner_filter)) continue;

            $country = $oi ? trim((string)($oi['country'] ?? '')) : '';
            $category = $oi ? trim((string)($oi['category'] ?? '')) : '';
            $site_date = $oi ? trim((string)($oi['date'] ?? '')) : '';
            $server = $oi ? trim((string)($oi['server'] ?? '')) : '';

            $server_short = '';
            if ($server !== '' && preg_match('/^\s*(.)/us', $server, $m)) {
                $server_short = $m[1];
            }

            $has_success_log = !empty($item['has_success_log']);
            $is_success = !empty($item['is_success']);
            $is_pending = ($has_success_log && !$is_success);
            $is_success_effective = ($is_success || ($pending_as_success && $is_pending));
            $status = $is_success_effective ? 'SUCCESS' : ($is_pending ? 'PENDING' : 'INCOMPLETE');

            $notify_errors = '';
            if (is_array($item['details']['notify_errors'] ?? null)) {
                $notify_errors = implode(' | ', $item['details']['notify_errors']);
            }

            $logs0 = is_array($item['logs'] ?? null) ? $item['logs'] : [];
            $forpay_new_lines = is_array($logs0['forpay_new'] ?? null) ? count($logs0['forpay_new']) : 0;
            $forpay_lines = is_array($logs0['forpay'] ?? null) ? count($logs0['forpay']) : 0;
            $notify_lines = is_array($logs0['notify'] ?? null) ? count($logs0['notify']) : 0;
            $success_lines = is_array($logs0['success'] ?? null) ? count($logs0['success']) : 0;

            $row = [
                $date,
                (string)$no,
                (string)($item['time'] ?? ''),
                (string)($item['hour'] ?? ''),
                (string)($item['domain'] ?? ''),
                (string)$pay_no,
                (string)$status,
                ($is_success ? '1' : '0'),
                ($has_success_log ? '1' : '0'),
                ($is_pending ? '1' : '0'),
                (string)($item['attempts'] ?? 0),
                (string)($item['details']['notify_count'] ?? 0),
                (string)($item['details']['amt'] ?? 0),
                (string)($item['details']['cur'] ?? ''),
                (string)($item['details']['usd_amt'] ?? 0),
                (string)($item['details']['usd_basis'] ?? ''),
                (string)($item['details']['err'] ?? ''),
                (string)$notify_errors,
                (string)$people,
                (string)$server_short,
                (string)$country,
                (string)$category,
                (string)$site_date,
                ($csv_path ? basename($csv_path) : ''),
                (string)$forpay_new_lines,
                (string)$forpay_lines,
                (string)$notify_lines,
                (string)$success_lines,
            ];
            fputcsv($out, $row);
        }

        $cur = strtotime('+1 day', $cur);
    }

    fclose($out);
}
