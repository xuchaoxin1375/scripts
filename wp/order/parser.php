<?php

function orders3_build_analysis_data_and_stats($log_files, $pending_as_success, $amount_nonzero)
{
    $analysis_data = [];
    $stats = [
        'total_orders' => 0,
        'total_attempts' => 0,
        'total_success' => 0,
        'total_pending' => 0,
        'total_usd_sum' => 0,
        'revenue_by_currency' => ['USD' => 0, 'EUR' => 0, 'GBP' => 0],
        'unique_domains' => 0,
        'active_sites' => 0,
        'total_visitors' => 0,
        'visitor_success' => 0,
        'visitor_fail_only' => 0,
        'domain_amount' => [],
        'domain_usd_sum' => [],
        'domain_success_orders' => [],
        'hourly_attempts' => array_fill(0, 24, 0),
        'hourly_success' => array_fill(0, 24, 0),
    ];

    $logs = [];
    foreach ($log_files as $type => $file) {
        $lines = file_exists($file) ? file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) : [];
        if ($type === 'success' && !empty($lines)) {
            $lines = array_values(array_unique($lines));
        }

        $logs[$type] = $lines;
    }

    foreach (($logs['forpay_new'] ?? []) as $line) {
        if (preg_match('/^(\d{4}-\d{2}-\d{2}\s(\d{2}):\d{2}:\d{2})\|(.*?)\|(\d+)\|/', $line, $m)) {
            $order_no = $m[4];
            $hour = (int)$m[2];
            $analysis_data[$order_no] = [
                'time' => $m[1],
                'hour' => $hour,
                'domain' => $m[3],
                'attempts' => 0,
                'is_success' => false,
                'has_success_log' => false,
                'logs' => ['forpay_new' => [$line]],
                'details' => ['amt' => 0, 'cur' => '', 'usd_amt' => 0, 'usd_basis' => '', 'err' => '', 'notify_count' => 0, 'notify_errors' => []]
            ];
        }
    }
    $visitor_prefix_set = [];
    $active_domain_set = [];
    foreach (($logs['forpay'] ?? []) as $line) {
        $domain_raw0 = '';
        if (preg_match('/^\\d{4}-\\d{2}-\\d{2}\\s\\d{2}:\\d{2}:\\d{2}\\|([^|]+)\\|/', $line, $mDom)) {
            $domain_raw0 = (string)($mDom[1] ?? '');
        }
        $dom0 = ($domain_raw0 !== '') ? normalize_domain_key($domain_raw0) : '';
        $domain_invalid0 = ($dom0 === '' || strpos($domain_raw0, '接口参数错误') !== false);
        if ($domain_invalid0) {
            if (preg_match('/\|(\d+)\|/', $line, $mBad)) {
                $no_bad = (string)($mBad[1] ?? '');
                if ($no_bad !== '' && isset($analysis_data[$no_bad])) {
                    unset($analysis_data[$no_bad]);
                }
            }
            continue;
        }
        $active_domain_set[$dom0] = true;
        if (preg_match('/\|(\d+)\|/', $line, $m)) {
            $no = $m[1];
            $prefix0 = (strlen((string)$no) > 2) ? substr((string)$no, 0, -2) : (string)$no;
            if ($prefix0 !== '') {
                $visitor_prefix_set[$prefix0] = true;
            }
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

    foreach (($logs['notify'] ?? []) as $line) {
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
                    $analysis_data[$no]['details']['usd_basis'] = 'notify.usd_amount';
                } else {
                    $rfx = convert_to_usd_with_basis($analysis_data[$no]['details']['amt'], $analysis_data[$no]['details']['cur']);
                    $analysis_data[$no]['details']['usd_amt'] = (float)($rfx['usd'] ?? 0);
                    $analysis_data[$no]['details']['usd_basis'] = (string)($rfx['basis'] ?? '');
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

    foreach (($logs['success'] ?? []) as $line) {
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
        $needs_money = ($notify_cnt0 <= 0);
        if ($needs_money) {
            $cur0 = (string)($item_ref['details']['cur'] ?? '');
            $amt0 = $item_ref['details']['amt'] ?? 0;
            $usd0 = $item_ref['details']['usd_amt'] ?? 0;
            $has_cur = trim($cur0) !== '';
            $has_amt = (is_numeric($amt0) && (float)$amt0 != 0.0);
            $has_usd = (is_numeric($usd0) && (float)$usd0 > 0.0);
            if (!$has_cur || !$has_amt || !$has_usd) {
                $success_lines = $item_ref['logs']['success'] ?? [];
                if (!empty($success_lines) && is_array($success_lines)) {
                    foreach ($success_lines as $sl) {
                        $parsed = parse_success_log_money($sl);
                        if (!$parsed) continue;
                        if (!$has_amt && isset($parsed['amount']) && $parsed['amount'] !== null) {
                            $item_ref['details']['amt'] = (float)$parsed['amount'];
                            $has_amt = true;
                        }
                        if (!$has_cur && isset($parsed['currency']) && $parsed['currency'] !== null) {
                            $item_ref['details']['cur'] = (string)$parsed['currency'];
                            $has_cur = true;
                        }
                        if ($has_amt && $has_cur) {
                            // keep scanning: later logs may contain updated values
                        }
                    }
                }
                $amt1 = $item_ref['details']['amt'] ?? 0;
                $cur1 = (string)($item_ref['details']['cur'] ?? '');
                $usd1 = $item_ref['details']['usd_amt'] ?? 0;
                if ((!is_numeric($usd1) || (float)$usd1 <= 0.0) && is_numeric($amt1) && trim($cur1) !== '') {
                    $rfx = convert_to_usd_with_basis($amt1, $cur1);
                    $item_ref['details']['usd_amt'] = (float)($rfx['usd'] ?? 0);
                    $item_ref['details']['usd_basis'] = (string)($rfx['basis'] ?? '');
                }
            }
        }
    }
    unset($item_ref);

    foreach ($analysis_data as $no => &$item_ref) {
        $notify_cnt0 = (int)($item_ref['details']['notify_count'] ?? 0);
        $has_forpay = ((int)($item_ref['attempts'] ?? 0)) > 0;
        $has_success_log = !empty($item_ref['has_success_log']);
        $item_ref['is_success'] = ($has_success_log && $has_forpay && $notify_cnt0 > 0);
    }
    unset($item_ref);

    $stats['total_orders'] = count($analysis_data);
    foreach ($analysis_data as $no => $item) {
        $is_pending0 = (!empty($item['has_success_log']) && empty($item['is_success']));
        $is_success_effective0 = (!empty($item['is_success']) || ($pending_as_success && $is_pending0));
        if ($is_success_effective0) {
            $stats['total_success']++;
            $stats['total_usd_sum'] += (float)$item['details']['usd_amt'];
            $stats['hourly_success'][(int)($item['hour'] ?? 0)]++;
            $cur = $item['details']['cur'] ?: 'UNK';
            $stats['domain_amount'][$item['domain']][$cur] = ($stats['domain_amount'][$item['domain']][$cur] ?? 0) + ($item['details']['amt'] ?? 0);

            $dom_key = (string)($item['domain'] ?? '');
            $stats['domain_usd_sum'][$dom_key] = ($stats['domain_usd_sum'][$dom_key] ?? 0) + (float)($item['details']['usd_amt'] ?? 0);
            $stats['domain_success_orders'][$dom_key][] = [
                'order_no' => (string)$no,
                'time' => (string)($item['time'] ?? ''),
                'amt' => (float)($item['details']['amt'] ?? 0),
                'cur' => (string)($item['details']['cur'] ?? ''),
                'usd_amt' => (float)($item['details']['usd_amt'] ?? 0),
                'usd_basis' => (string)($item['details']['usd_basis'] ?? ''),
            ];

            $cur_upper = strtoupper((string)($item['details']['cur'] ?? ''));
            if (isset($stats['revenue_by_currency'][$cur_upper])) {
                $stats['revenue_by_currency'][$cur_upper] += (float)($item['details']['amt'] ?? 0);
            }
        }
        if ($is_pending0) {
            $stats['total_pending']++;
        }
        if ($amount_nonzero && (empty($item['details']['amt']) || $item['details']['amt'] == 0)) {
            if ($pending_as_success && $is_pending0 && !empty($item['logs']['success'])) {
                $succ_lines = $item['logs']['success'];
                if (is_array($succ_lines) && !empty($succ_lines)) {
                    foreach ($succ_lines as $sl) {
                        $parsed = parse_success_log_money($sl);
                        if (!$parsed) continue;
                        $a0 = $parsed['amount'] ?? null;
                        $c0 = $parsed['currency'] ?? null;
                        if ($a0 !== null && is_numeric($a0) && (float)$a0 != 0.0 && $c0 !== null && trim((string)$c0) !== '') {
                            $analysis_data[$no]['details']['amt'] = (float)$a0;
                            $analysis_data[$no]['details']['cur'] = (string)$c0;
                            $analysis_data[$no]['details']['usd_amt'] = convert_to_usd($a0, $c0);
                            break;
                        }
                    }
                }
            }
            if (empty($analysis_data[$no]['details']['amt']) || $analysis_data[$no]['details']['amt'] == 0) {
                unset($analysis_data[$no]);
                continue;
            }
        }
    }

    $visitor_success_set = [];
    foreach ($analysis_data as $no => $item) {
        $is_pending0 = (!empty($item['has_success_log']) && empty($item['is_success']));
        $is_success_effective0 = (!empty($item['is_success']) || ($pending_as_success && $is_pending0));
        if (!$is_success_effective0) continue;
        $no0 = (string)$no;
        $prefix0 = (strlen($no0) > 2) ? substr($no0, 0, -2) : $no0;
        if ($prefix0 !== '' && isset($visitor_prefix_set[$prefix0])) {
            $visitor_success_set[$prefix0] = true;
        }
    }
    $stats['total_visitors'] = count($visitor_prefix_set);
    $stats['visitor_success'] = count($visitor_success_set);
    $stats['visitor_fail_only'] = max(0, $stats['total_visitors'] - $stats['visitor_success']);
    $stats['active_sites'] = count($active_domain_set);

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

    uasort($analysis_data, function ($a, $b) use ($pending_as_success) {
        $a_pending = (!empty($a['has_success_log']) && empty($a['is_success']));
        $b_pending = (!empty($b['has_success_log']) && empty($b['is_success']));
        $a_eff = (!empty($a['is_success']) || ($pending_as_success && $a_pending));
        $b_eff = (!empty($b['is_success']) || ($pending_as_success && $b_pending));
        if ($a_eff !== $b_eff) return $b_eff <=> $a_eff;
        return strcmp($b['time'], $a['time']);
    });

    return [$analysis_data, $stats];
}
