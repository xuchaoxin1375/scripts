<?php

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

function compute_range_revenue_days($range_start, $range_end, $pending_as_success = true)
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
        $people_usd_sum = [];
        $success_orders_map = [];
        $success_orders_usd_fallback = [];
        $total_orders = 0;
        $attempts_cnt = 0;
        $visitor_prefix_set = [];
        $active_domain_set = [];
        // 以 forpay_new 中的唯一订单号作为当日订单总量
        $order_set = [];
        $order_domain_map = [];
        if (file_exists($forpay_new_file)) {
            $lines = file($forpay_new_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            foreach ($lines as $line) {
                if (preg_match('/\\|(\\d+)\\|/', $line, $m)) {
                    $order_set[$m[1]] = true;
                }
                if (preg_match('/^(\\d{4}-\\d{2}-\\d{2}\\s\\d{2}:\\d{2}:\\d{2})\\|([^|]+)\\|(\\d+)\\|/', $line, $m2)) {
                    $dom = (string)($m2[2] ?? '');
                    $ono2 = (string)($m2[3] ?? '');
                    if ($ono2 !== '') {
                        $order_domain_map[$ono2] = $dom;
                    }
                }
            }
            $total_orders = count($order_set);
        }

        // forpay.log：统计当日总尝试次数（仅统计属于当日订单集合的记录）
        $forpay_orders = [];
        if (file_exists($forpay_file)) {
            $lines = file($forpay_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            foreach ($lines as $line) {
                if (!preg_match('/^\\d{4}-\\d{2}-\\d{2}\\s\\d{2}:\\d{2}:\\d{2}\\|([^|]+)\\|/', $line, $mDom)) {
                    continue;
                }
                $dom0 = normalize_domain_key((string)($mDom[1] ?? ''));
                if ($dom0 === '') {
                    continue;
                }
                $active_domain_set[$dom0] = true;
                if (preg_match('/\|(\d+)\|/', $line, $m)) {
                    $no0 = (string)$m[1];
                    $prefix0 = (strlen($no0) > 2) ? substr($no0, 0, -2) : $no0;
                    if ($prefix0 !== '') {
                        $visitor_prefix_set[$prefix0] = true;
                    }
                    if (isset($order_set[$m[1]])) {
                        $attempts_cnt++;
                        $forpay_orders[$m[1]] = true;
                    }
                }
            }
        }

        $notify_orders_usd = [];
        $notify_orders_set = [];
        if (file_exists($notify_file) && !empty($order_set)) {
            $lines = file($notify_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            foreach ($lines as $line) {
                if (preg_match('/"order_no":"(\\d+)"/', $line, $m)) {
                    $ono = $m[1];
                    if (!isset($order_set[$ono])) continue;
                    $notify_orders_set[$ono] = true;
                    if ($json = strstr($line, '{')) {
                        $d = json_decode($json, true);
                        if (isset($d['usd_amount']) && is_numeric($d['usd_amount'])) {
                            $notify_orders_usd[$ono] = floatval($d['usd_amount']);
                        } else {
                            $amt = $d['amount'] ?? 0;
                            $curc = $d['currency'] ?? '';
                            $notify_orders_usd[$ono] = convert_to_usd($amt, $curc);
                        }
                    }
                }
            }
        }

        if (file_exists($success_file)) {
            $lines = file($success_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            if (!empty($lines)) $lines = array_values(array_unique($lines));
            foreach ($lines as $line) {
                if (preg_match('/order_no=(\d+)/', $line, $m)) {
                    $ono = $m[1];
                    $success_orders_map[$ono] = true;
                    if ($pending_as_success && isset($order_set[$ono])) {
                        $parsed = parse_success_log_money($line);
                        if ($parsed && isset($parsed['amount']) && isset($parsed['currency']) && $parsed['amount'] !== null && $parsed['currency'] !== null) {
                            $success_orders_usd_fallback[$ono] = convert_to_usd($parsed['amount'], $parsed['currency']);
                        }
                    }
                }
            }
        }

        $success_cnt = 0;
        foreach ($success_orders_map as $ono => $_v) {
            if (!isset($order_set[$ono])) continue;
            $has_forpay = !empty($forpay_orders[$ono]);
            $has_notify = !empty($notify_orders_set[$ono]);
            $is_real_success = ($has_forpay && $has_notify);
            $is_pending = !$is_real_success;
            if (!$pending_as_success && $is_pending) {
                continue;
            }
            $success_cnt++;
            $usd_val = 0.0;
            if (isset($notify_orders_usd[$ono])) {
                $usd_val = (float)$notify_orders_usd[$ono];
            } elseif (isset($success_orders_usd_fallback[$ono])) {
                $usd_val = (float)$success_orders_usd_fallback[$ono];
            }
            $usd_sum += $usd_val;

            $people_name = '';
            if (isset($GLOBALS['ORDERS3_RANGE_CSV_DOMAIN_OWNER_MAP']) && is_array($GLOBALS['ORDERS3_RANGE_CSV_DOMAIN_OWNER_MAP'])) {
                $dom0 = (string)($order_domain_map[$ono] ?? '');
                $dom_key0 = normalize_domain_key($dom0);
                $owner0 = ($dom_key0 !== '' && isset($GLOBALS['ORDERS3_RANGE_CSV_DOMAIN_OWNER_MAP'][$dom_key0])) ? $GLOBALS['ORDERS3_RANGE_CSV_DOMAIN_OWNER_MAP'][$dom_key0] : null;
                $people_name = $owner0 ? trim((string)($owner0['people'] ?? '')) : '';
            }
            if ($people_name !== '') {
                $people_usd_sum[$people_name] = ($people_usd_sum[$people_name] ?? 0) + $usd_val;
            }
        }
        $conv = ($total_orders > 0) ? round(($success_cnt / $total_orders) * 100, 2) : 0;
        $revenue_days[] = [
            'date' => $date,
            'usd' => round($usd_sum, 2),
            'conversion' => $conv,
            'total_orders' => $total_orders,
            'success_orders' => $success_cnt,
            'attempts' => $attempts_cnt,
            'visitors' => count($visitor_prefix_set),
            'active_sites' => count($active_domain_set),
            'people_usd' => !empty($people_usd_sum) ? $people_usd_sum : null,
        ];
        $cur = strtotime('+1 day', $cur);
    }
    return $revenue_days;
}
