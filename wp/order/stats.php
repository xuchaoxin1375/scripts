<?php

function build_people_stats($analysis_data, $domain_owner_map)
{
    $pending_as_success = true;
    if (isset($_GET['pending_as_success']) && (string)$_GET['pending_as_success'] === '0') {
        $pending_as_success = false;
    }
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
        $is_pending0 = (!empty($item['has_success_log']) && empty($item['is_success']));
        $is_success_effective0 = (!empty($item['is_success']) || ($pending_as_success && $is_pending0));
        if ($is_success_effective0) {
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
