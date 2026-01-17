<?php

function export_orders_csv_range($access_token, $range_start, $range_end, $status_filter, $owner_filter, $amount_nonzero, $csv_selected)
{
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
        'is_success',
        'attempts',
        'notify_count',
        'amount',
        'currency',
        'usd_amount',
        'usd_basis',
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

        // 解析 forpay_new.log / forpay.log / notify.log
        foreach ($logs['forpay_new'] as $line) {
            if (preg_match('/\|(\d+)\|/', $line, $m)) {
                $no = $m[1];
                if (!isset($analysis_data[$no])) {
                    $analysis_data[$no] = [
                        'no' => $no,
                        'logs' => ['forpay_new' => [], 'forpay' => [], 'notify' => [], 'success' => []],
                        'details' => [
                            'amt' => 0,
                            'cur' => '',
                            'usd_amt' => 0,
                            'usd_basis' => '',
                            'notify_count' => 0,
                            'notify_errors' => [],
                            'err' => '',
                        ],
                        'domain' => '',
                        'time' => '',
                        'hour' => 0,
                        'attempts' => 0,
                        'has_success_log' => false,
                        'is_success' => false,
                    ];
                }
                $analysis_data[$no]['logs']['forpay_new'][] = $line;

                if (preg_match('/\|domain=([^\|\s]+)/', $line, $m2)) {
                    $analysis_data[$no]['domain'] = $m2[1];
                }
                if (preg_match('/(\d{2}:\d{2}:\d{2})/', $line, $m3)) {
                    $analysis_data[$no]['time'] = $m3[1];
                    $analysis_data[$no]['hour'] = intval(substr($m3[1], 0, 2));
                }
            }
        }

        foreach ($logs['forpay'] as $line) {
            if (preg_match('/\|(\d+)\|/', $line, $m)) {
                $no = $m[1];
                if (!isset($analysis_data[$no])) {
                    continue;
                }
                $analysis_data[$no]['attempts']++;
                $stats_stub['hourly_attempts'][$analysis_data[$no]['hour']]++;
                $analysis_data[$no]['logs']['forpay'][] = $line;
                if (empty($analysis_data[$no]['details']['err'])) {
                    if (preg_match('/err=([^\|]+)/', $line, $m2)) {
                        $analysis_data[$no]['details']['err'] = trim((string)$m2[1]);
                    }
                }
            }
        }

        foreach ($logs['notify'] as $line) {
            if (preg_match('/"order_no":"(\d+)"/', $line, $m)) {
                $no = $m[1];
                if (!isset($analysis_data[$no])) {
                    continue;
                }
                $analysis_data[$no]['logs']['notify'][] = $line;
                $analysis_data[$no]['details']['notify_count'] = (int)($analysis_data[$no]['details']['notify_count'] ?? 0) + 1;

                if ($json = strstr($line, '{')) {
                    $d = json_decode($json, true);
                    if (is_array($d)) {
                        if (isset($d['usd_amount']) && is_numeric($d['usd_amount'])) {
                            $analysis_data[$no]['details']['usd_amt'] = floatval($d['usd_amount']);
                            $analysis_data[$no]['details']['usd_basis'] = 'notify.usd_amount';
                        } else {
                            $amt = $d['amount'] ?? 0;
                            $curc = $d['currency'] ?? '';
                            $rfx = convert_to_usd_with_basis($amt, $curc);
                            $analysis_data[$no]['details']['usd_amt'] = (float)($rfx['usd'] ?? 0);
                            $analysis_data[$no]['details']['usd_basis'] = (string)($rfx['basis'] ?? '');
                        }
                        if (isset($d['amount']) && is_numeric($d['amount'])) {
                            $analysis_data[$no]['details']['amt'] = floatval($d['amount']);
                        }
                        if (isset($d['currency'])) {
                            $analysis_data[$no]['details']['cur'] = (string)$d['currency'];
                        }
                        if (!empty($d['error'])) {
                            $analysis_data[$no]['details']['notify_errors'][] = (string)$d['error'];
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
                    $analysis_data[$no]['has_success_log'] = true;
                    $analysis_data[$no]['logs']['success'][] = $line;
                }
            }
        }

        foreach ($analysis_data as $no => &$item_ref) {
            $notify_cnt0 = (int)($item_ref['details']['notify_count'] ?? 0);
            $has_forpay = ((int)($item_ref['attempts'] ?? 0)) > 0;
            $has_success_log = !empty($item_ref['has_success_log']);
            $item_ref['is_success'] = ($has_success_log && $has_forpay && $notify_cnt0 > 0);
            if (!empty($item_ref['is_success'])) {
                $stats_stub['hourly_success'][$item_ref['hour']]++;
            }
        }
        unset($item_ref);

        foreach ($analysis_data as $no => $item) {
            if ($amount_nonzero && (empty($item['details']['amt']) || $item['details']['amt'] == 0)) {
                $is_pending0 = (!empty($item['has_success_log']) && empty($item['is_success']));
                $pending_as_success0 = true;
                if (isset($_GET['pending_as_success']) && (string)$_GET['pending_as_success'] === '0') {
                    $pending_as_success0 = false;
                }
                if ($pending_as_success0 && $is_pending0 && !empty($item['logs']['success'])) {
                    $succ_lines = $item['logs']['success'];
                    if (is_array($succ_lines) && !empty($succ_lines)) {
                        foreach ($succ_lines as $sl) {
                            $parsed = parse_success_log_money($sl);
                            if (!$parsed) continue;
                            $a0 = $parsed['amount'] ?? null;
                            $c0 = $parsed['currency'] ?? null;
                            if ($a0 !== null && is_numeric($a0) && (float)$a0 != 0.0 && $c0 !== null && trim((string)$c0) !== '') {
                                $item['details']['amt'] = (float)$a0;
                                $item['details']['cur'] = (string)$c0;
                                $rfx = convert_to_usd_with_basis($a0, $c0);
                                $item['details']['usd_amt'] = (float)($rfx['usd'] ?? 0);
                                $item['details']['usd_basis'] = (string)($rfx['basis'] ?? '');
                                break;
                            }
                        }
                    }
                }
                if (empty($item['details']['amt']) || $item['details']['amt'] == 0) {
                    continue;
                }
            }
            if (!order_matches_status_filter($item, $status_filter)) {
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
                (string)($item['details']['usd_basis'] ?? ''),
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
