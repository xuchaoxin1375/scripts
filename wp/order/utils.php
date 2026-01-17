<?php

function fx_warn_once($key, $message)
{
    static $warned = [];
    $k = (string)$key;
    if ($k === '') return;
    if (isset($warned[$k])) return;
    $warned[$k] = true;
    error_log((string)$message);
}

function fx_fetch_rate_online($base_currency, $target_currency)
{
    static $cache = [];
    $base = strtoupper(trim((string)$base_currency));
    $target = strtoupper(trim((string)$target_currency));
    if ($base === '' || $target === '' || $base === $target) return 1.0;
    $cache_key = $base . '->' . $target;
    if (isset($cache[$cache_key])) return $cache[$cache_key];

    $url = 'https://hexarate.paikama.co/api/rates/' . rawurlencode($base) . '/' . rawurlencode($target) . '/latest';
    $body = '';
    if (function_exists('curl_init')) {
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 2);
        curl_setopt($ch, CURLOPT_TIMEOUT, 3);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 2);
        curl_setopt($ch, CURLOPT_USERAGENT, 'orders3.php fx');
        $resp = curl_exec($ch);
        if (is_string($resp)) {
            $body = $resp;
        }
        curl_close($ch);
    } else {
        $ctx = stream_context_create([
            'http' => [
                'method' => 'GET',
                'timeout' => 3,
                'header' => "User-Agent: orders3.php fx\r\n",
            ],
        ]);
        $resp = @file_get_contents($url, false, $ctx);
        if (is_string($resp)) {
            $body = $resp;
        }
    }

    if ($body !== '') {
        $j = json_decode($body, true);
        $mid = $j['data']['mid'] ?? null;
        $status_code = $j['status_code'] ?? null;
        if (($status_code === 200 || $status_code === '200') && $mid !== null && is_numeric($mid)) {
            $cache[$cache_key] = (float)$mid;
            return $cache[$cache_key];
        }
    }

    $cache[$cache_key] = null;
    return null;
}

function convert_to_usd_with_basis($amount, $currency = '')
{
    $amt = 0.0;
    if (is_numeric($amount)) {
        $amt = (float)$amount;
    } else {
        $clean = preg_replace('/[^\d\.\-]/', '', (string)$amount);
        $amt = $clean === '' ? 0.0 : floatval($clean);
    }
    $cur = strtoupper(trim((string)$currency));
    $rates = [
        'USD' => 1.0, 'USDT' => 1.0, 'TUSD' => 1.0,
        'CNY' => 0.14, 'RMB' => 0.14,
        'EUR' => 1.08, 'GBP' => 1.25, 'JPY' => 0.0067,
        'AUD' => 0.67, 'CAD' => 0.73, 'SGD' => 0.74,
    ];
    if ($cur === '' || $cur === 'USD') return ['usd' => round($amt, 2), 'basis' => 'original USD'];
    if ($cur === 'USDT' || $cur === 'TUSD') return ['usd' => round($amt, 2), 'basis' => 'stablecoin 1:1'];

    $online = fx_fetch_rate_online($cur, 'USD');
    if ($online !== null && is_numeric($online) && (float)$online > 0) {
        return ['usd' => round($amt * (float)$online, 2), 'basis' => 'online hexarate ' . $cur . '->USD mid=' . (string)$online];
    }

    if (isset($rates[$cur])) {
        fx_warn_once('fx_fallback_' . $cur, '[FX-FALLBACK] online rate unavailable for ' . $cur . '->USD, using built-in estimate rate=' . $rates[$cur]);
        return ['usd' => round($amt * $rates[$cur], 2), 'basis' => 'built-in ' . $cur . '->USD rate=' . (string)$rates[$cur]];
    }

    fx_warn_once('fx_unknown_' . $cur, '[FX-UNKNOWN] unknown currency=' . $cur . ', cannot convert to USD, returning 0');
    return ['usd' => 0.0, 'basis' => 'unknown currency'];
}

function convert_to_usd($amount, $currency = '')
{
    $r = convert_to_usd_with_basis($amount, $currency);
    return (float)($r['usd'] ?? 0.0);
}

function order_matches_status_filter($item, $status_filter)
{
    $sf = (string)$status_filter;
    if ($sf === '' || $sf === 'all') return true;
    $is_success = !empty($item['is_success']);
    $has_success_log = !empty($item['has_success_log']);
    $is_pending = ($has_success_log && !$is_success);
    $pending_as_success = true;
    if (isset($_GET['pending_as_success']) && (string)$_GET['pending_as_success'] === '0') {
        $pending_as_success = false;
    }
    if ($sf === 'success') {
        return $is_success || ($pending_as_success && $is_pending);
    }
    if ($sf === 'pending') {
        return (!$pending_as_success) && $is_pending;
    }
    if ($sf === 'fail') {
        return !$has_success_log;
    }
    return true;
}

function list_csv_files_in_dir($base_dir)
{
    $base_dir = (string)$base_dir;

    $dirs = [];
    if ($base_dir !== '' && is_dir($base_dir)) {
        $dirs[] = $base_dir;
    }
    $parent = ($base_dir !== '') ? dirname($base_dir) : '';
    if ($parent !== '' && is_dir($parent)) {
        $dirs[] = $parent;
    }
    $parent_order = ($parent !== '') ? rtrim($parent, '/\\') . DIRECTORY_SEPARATOR . 'order' : '';
    if ($parent_order !== '' && is_dir($parent_order)) {
        $dirs[] = $parent_order;
    }
    $base_order = ($base_dir !== '') ? rtrim($base_dir, '/\\') . DIRECTORY_SEPARATOR . 'order' : '';
    if ($base_order !== '' && is_dir($base_order)) {
        $dirs[] = $base_order;
    }

    $dirs = array_values(array_unique($dirs));

    $files = [];
    foreach ($dirs as $d) {
        $list = @scandir($d);
        if (!is_array($list)) continue;
        foreach ($list as $f) {
            if ($f === '.' || $f === '..') continue;
            if (!preg_match('/\.csv$/i', $f)) continue;
            $path = rtrim($d, '/\\') . DIRECTORY_SEPARATOR . $f;
            if (is_file($path)) {
                $files[$f] = true;
            }
        }
    }

    $names = array_keys($files);
    sort($names);
    return $names;
}

function resolve_selected_csv_path($base_dir, $csv_selected, $csv_files)
{
    $base_dir = (string)$base_dir;
    $csv_selected = trim((string)$csv_selected);
    if (!is_array($csv_files)) $csv_files = [];

    $candidate = '';
    if ($csv_selected !== '' && in_array($csv_selected, $csv_files, true)) {
        $candidate = $csv_selected;
    } elseif (!empty($csv_files)) {
        $candidate = (string)$csv_files[0];
    }
    if ($candidate === '') return '';

    $dirs = [];
    if ($base_dir !== '' && is_dir($base_dir)) {
        $dirs[] = $base_dir;
    }
    $parent = ($base_dir !== '') ? dirname($base_dir) : '';
    if ($parent !== '' && is_dir($parent)) {
        $dirs[] = $parent;
    }
    $parent_order = ($parent !== '') ? rtrim($parent, '/\\') . DIRECTORY_SEPARATOR . 'order' : '';
    if ($parent_order !== '' && is_dir($parent_order)) {
        $dirs[] = $parent_order;
    }
    $base_order = ($base_dir !== '') ? rtrim($base_dir, '/\\') . DIRECTORY_SEPARATOR . 'order' : '';
    if ($base_order !== '' && is_dir($base_order)) {
        $dirs[] = $base_order;
    }

    $dirs = array_values(array_unique($dirs));
    foreach ($dirs as $d) {
        $path = rtrim($d, '/\\') . DIRECTORY_SEPARATOR . $candidate;
        if (is_file($path)) {
            return $path;
        }
    }

    return '';
}

function normalize_domain_key($domain)
{
    $s = strtolower(trim((string)$domain));
    $s = preg_replace('/^https?:\/\//', '', $s);
    $s = preg_replace('/\/.*/', '', $s);
    $s = preg_replace('/^www\./', '', $s);
    return $s;
}

function detect_csv_encoding_label($s)
{
    if (!is_string($s) || $s === '') return 'unknown';
    if (function_exists('mb_check_encoding') && mb_check_encoding($s, 'UTF-8')) {
        return 'utf-8';
    }
    if (function_exists('mb_check_encoding') && mb_check_encoding($s, 'GBK')) {
        return 'gbk';
    }
    return 'unknown';
}

function normalize_header_key($s)
{
    $s = strtolower(trim((string)$s));
    $s = preg_replace('/[\x{200B}\x{FEFF}\s]+/u', '', $s);
    $s = str_replace(['\uFEFF'], [''], $s);
    $s = preg_replace('/^\xEF\xBB\xBF/', '', $s);
    return $s;
}

function fix_csv_cell_encoding($s)
{
    if (!is_string($s) || $s === '') return $s;
    if (function_exists('mb_check_encoding') && mb_check_encoding($s, 'UTF-8')) {
        return $s;
    }
    if (function_exists('mb_convert_encoding')) {
        $converted = @mb_convert_encoding($s, 'UTF-8', 'GBK,GB2312,BIG5,ISO-8859-1');
        if (is_string($converted) && $converted !== '') {
            return $converted;
        }
    }
    return $s;
}

function find_header_index($headers, $candidates)
{
    $map = [];
    foreach ($headers as $idx => $h) {
        $map[normalize_header_key($h)] = $idx;
    }
    foreach (($candidates ?? []) as $cand) {
        $k = normalize_header_key($cand);
        if ($k !== '' && isset($map[$k])) {
            return $map[$k];
        }
    }
    return null;
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

function format_money($amount)
{
    return number_format((float)$amount, 2, '.', ',');
}

function highlight_log($line)
{
    $line = htmlspecialchars($line);
    $line = preg_replace('/(\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2})/', '<span style="color:#ce9178;">$1</span>', $line);
    $line = preg_replace('/(https?:\/\/[^\s\"\']+)/', '<span style="color:#4fc1ff;">$1</span>', $line);
    return $line;
}

function parse_success_log_money($line)
{
    $s = trim((string)$line);
    if ($s === '') return null;
    if (preg_match('/amount=([\d\.\-]+)/', $s, $m1) && preg_match('/currency=([A-Za-z]+)/', $s, $m2)) {
        $amount = $m1[1];
        $currency = $m2[1];
        return ['amount' => $amount, 'currency' => $currency];
    }
    return null;
}
