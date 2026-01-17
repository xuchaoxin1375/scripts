<?php

function load_domain_owner_map_from_csv($csv_file)
{
    global $CSV_HEADER_CANDIDATES;
    global $ORDERS3_LOG_CSV_FIELDS, $ORDERS3_CSV_FIELDS_LOG_PATH;

    static $cache = [];
    static $logged_csv = [];
    $cache_key = is_string($csv_file) ? (string)$csv_file : '';
    if ($cache_key !== '') {
        $rp = @realpath($cache_key);
        if (is_string($rp) && $rp !== '') {
            $cache_key = $rp;
        }
    }
    if ($cache_key !== '' && isset($cache[$cache_key])) {
        return $cache[$cache_key];
    }

    $res = [
        'map' => [],
        'meta' => [
            'csv' => (string)$csv_file,
            'has_people' => false,
            'has_country' => false,
            'has_category' => false,
            'has_date' => false,
            'has_server' => false,
            'headers' => [],
            'matched_fields' => [],
            'matched_headers' => [],
            'encoding' => '',
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

    $encoding_label = '';
    foreach ($headers as $h0) {
        $enc0 = detect_csv_encoding_label($h0);
        if ($enc0 !== 'unknown') {
            $encoding_label = $enc0;
            break;
        }
    }
    if ($encoding_label === '') $encoding_label = 'unknown';
    $res['meta']['encoding'] = $encoding_label;

    foreach ($headers as $i => $h) {
        $headers[$i] = fix_csv_cell_encoding($h);
    }
    $res['meta']['headers'] = $headers;

    $domain_idx = find_header_index($headers, $CSV_HEADER_CANDIDATES['domain'] ?? ['域名', '网站', '站点', 'domain', 'site']);
    $people_idx = find_header_index($headers, $CSV_HEADER_CANDIDATES['people'] ?? ['数据采集员', '数据采集人员', '人员', '归属人员', '名字', '姓名', '采集员']);
    $country_idx = find_header_index($headers, $CSV_HEADER_CANDIDATES['country'] ?? ['国家', '语言', '网站语言', '站点语言', 'lang', 'country']);
    $category_idx = find_header_index($headers, $CSV_HEADER_CANDIDATES['category'] ?? ['内容', '产品类别', '产品分类', '品类', '类目', '类别', '产品', 'category', 'productcategory']);
    $date_idx = find_header_index($headers, $CSV_HEADER_CANDIDATES['date'] ?? ['完成日期', '建站日期', '申请日期', '域名申请日期', '日期', '创建日期', '上线日期', '完成时间', '时间', 'date', 'createdate', 'created_at', 'updated_at']);
    $server_idx = find_header_index($headers, $CSV_HEADER_CANDIDATES['server'] ?? ['服务器', 'server']);

    $matched_fields = [];
    $matched_headers = [];
    if ($domain_idx !== null) {
        $matched_fields[] = 'domain';
        $matched_headers['domain'] = (string)($headers[$domain_idx] ?? '');
    }
    if ($people_idx !== null) {
        $matched_fields[] = 'people';
        $matched_headers['people'] = (string)($headers[$people_idx] ?? '');
    }
    if ($country_idx !== null) {
        $matched_fields[] = 'country';
        $matched_headers['country'] = (string)($headers[$country_idx] ?? '');
    }
    if ($category_idx !== null) {
        $matched_fields[] = 'category';
        $matched_headers['category'] = (string)($headers[$category_idx] ?? '');
    }
    if ($date_idx !== null) {
        $matched_fields[] = 'date';
        $matched_headers['date'] = (string)($headers[$date_idx] ?? '');
    }
    if ($server_idx !== null) {
        $matched_fields[] = 'server';
        $matched_headers['server'] = (string)($headers[$server_idx] ?? '');
    }
    $res['meta']['matched_fields'] = $matched_fields;
    $res['meta']['matched_headers'] = $matched_headers;

    if (!empty($ORDERS3_LOG_CSV_FIELDS) && $cache_key !== '' && empty($logged_csv[$cache_key])) {
        $logged_csv[$cache_key] = true;
        $log_fields = !empty($matched_fields) ? implode(',', $matched_fields) : 'none';
        $ts = date('Y-m-d H:i:s');
        if ($log_fields === 'none') {
            $preview = [];
            foreach ($headers as $hv) {
                $hv = trim((string)$hv);
                if ($hv !== '') $preview[] = $hv;
            }
            $preview_s = implode('|', array_slice($preview, 0, 20));
            error_log('[' . $ts . '] [orders3] csv_fields csv=' . basename((string)$csv_file) . ' matched=' . $log_fields . ' headers=' . $preview_s . "\n", 3, (string)$ORDERS3_CSV_FIELDS_LOG_PATH);
        } else {
            error_log('[' . $ts . '] [orders3] csv_fields csv=' . basename((string)$csv_file) . ' matched=' . $log_fields . "\n", 3, (string)$ORDERS3_CSV_FIELDS_LOG_PATH);
        }
    }

    $res['meta']['has_people'] = ($people_idx !== null);
    $res['meta']['has_country'] = ($country_idx !== null);
    $res['meta']['has_category'] = ($category_idx !== null);
    $res['meta']['has_date'] = ($date_idx !== null);
    $res['meta']['has_server'] = ($server_idx !== null);

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
        $server = $server_idx !== null ? trim((string)($row[$server_idx] ?? '')) : '';

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
            if (($res['map'][$domain_key]['server'] ?? '') === '' && $server !== '') {
                $res['map'][$domain_key]['server'] = $server;
            }
            continue;
        }

        $res['map'][$domain_key] = [
            'people' => $people,
            'country' => $country,
            'category' => $category,
            'date' => $date,
            'server' => $server,
            'raw_domain' => (string)$domain_raw,
        ];
        $res['meta']['ok_rows']++;
    }
    fclose($fh);

    if ($cache_key !== '') {
        $cache[$cache_key] = $res;
    }
    return $res;
}
