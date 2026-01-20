<?php

function render_order_list_items($analysis_data, $group_by_domain, $order_sort, $status_filter, $owner_filter, $csv_path, $list_view = 'card')
{
    ob_start();
    $order_index = 1;

    $cluster_prefix6_enabled = true;
    if (isset($_GET['cluster_prefix6']) && (string)$_GET['cluster_prefix6'] === '0') {
        $cluster_prefix6_enabled = false;
    }

    $pending_as_success0 = true;
    if (isset($_GET['pending_as_success']) && (string)$_GET['pending_as_success'] === '0') {
        $pending_as_success0 = false;
    }

    $csv_data = load_domain_owner_map_from_csv($csv_path);
    $domain_owner_map = $csv_data['map'] ?? [];
    $has_people = (bool)($csv_data['meta']['has_people'] ?? false);
    $has_country = (bool)($csv_data['meta']['has_country'] ?? false);
    $has_category = (bool)($csv_data['meta']['has_category'] ?? false);
    $has_date = (bool)($csv_data['meta']['has_date'] ?? false);
    $has_server = (bool)($csv_data['meta']['has_server'] ?? false);

    $list_view = trim((string)$list_view);
    if ($list_view !== 'table' && $list_view !== 'card') {
        $list_view = 'card';
    }

    if ($list_view === 'table') {
        $rows = [];
        foreach ($analysis_data as $no => $item) {
            if (!order_matches_status_filter($item, $status_filter)) {
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
            $server = $owner ? trim((string)($owner['server'] ?? '')) : '';
            $server_short = '';
            if ($server !== '' && preg_match('/^\s*(.)/us', $server, $m)) {
                $server_short = $m[1];
            }

            $amt = $item['details']['amt'] ?? 0;
            $cur = (string)($item['details']['cur'] ?? '');
            $usd = $item['details']['usd_amt'] ?? 0;
            $usd_basis = (string)($item['details']['usd_basis'] ?? '');
            $attempts = (int)($item['attempts'] ?? 0);
            $notify_cnt = (int)($item['details']['notify_count'] ?? 0);
            $err = (string)($item['details']['err'] ?? '');
            $time = (string)($item['time'] ?? '');
            $time_short = ($time !== '' && strlen($time) >= 16) ? substr($time, 11, 5) : $time;

            $has_success_log0 = !empty($item['has_success_log']);
            $is_pending0 = ($has_success_log0 && empty($item['is_success']));
            $is_success_effective0 = (!empty($item['is_success']) || ($pending_as_success0 && $is_pending0));
            $group_key0 = $is_success_effective0 ? 'success' : ($has_success_log0 ? 'pending' : 'fail');

            $no0 = (string)$no;
            $cluster_key0 = (strlen($no0) > 2) ? substr($no0, 0, -2) : $no0;
            $rows[] = [
                'no' => $no0,
                'prefix6' => $cluster_key0,
                'time' => $time,
                'time_short' => $time_short,
                'domain' => $dom,
                'is_success' => !empty($item['is_success']),
                'has_success_log' => !empty($item['has_success_log']),
                'group_key' => $group_key0,
                'attempts' => $attempts,
                'notify_cnt' => $notify_cnt,
                'cur' => $cur,
                'amt' => $amt,
                'usd' => $usd,
                'usd_basis' => $usd_basis,
                'people' => $people,
                'server' => $server_short,
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

        $prefix_cnt = [];
        foreach ($rows as $r0) {
            $p0 = (string)($r0['prefix6'] ?? '');
            if ($p0 === '') continue;
            if (($r0['group_key'] ?? '') !== 'fail') continue;
            $prefix_cnt[$p0] = ($prefix_cnt[$p0] ?? 0) + 1;
        }
        if ($cluster_prefix6_enabled && !empty($rows)) {
            $seen_prefix = [];
            $rows2 = [];
            foreach ($rows as $r0) {
                $p0 = (string)($r0['prefix6'] ?? '');
                if ($p0 === '') {
                    $r0['cluster_cnt'] = 1;
                    $rows2[] = $r0;
                    continue;
                }
                if (($r0['group_key'] ?? '') === 'fail') {
                    if (isset($seen_prefix[$p0])) {
                        continue;
                    }
                    $seen_prefix[$p0] = true;
                    $r0['cluster_cnt'] = (int)($prefix_cnt[$p0] ?? 1);
                } else {
                    $r0['cluster_cnt'] = 1;
                }
                $rows2[] = $r0;
            }
            $rows = $rows2;
        } else {
            foreach ($rows as &$r0) {
                $r0['cluster_cnt'] = 1;
            }
            unset($r0);
        }

        echo '<div class="excel-table-wrap">';
        echo '<table class="excel-table" id="ordersExcelTable">';
        echo '<thead><tr>';
        echo '<th style="width:48px;">#</th>';
        echo '<th style="width:60px;">时间</th>';
        echo '<th style="width:130px;">单号</th>';
        echo '<th>域名</th>';
        if ($has_people) echo '<th style="width:90px;">人员</th>';
        if ($has_server) echo '<th style="width:56px;">服务器</th>';
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
            $has_success_log = !empty($r['has_success_log']);
            $is_pending = ($has_success_log && empty($r['is_success']));
            $is_success_effective = (!empty($r['is_success']) || ($pending_as_success0 && $is_pending));
            $st = $is_success_effective ? 'SUCCESS' : ($is_pending ? 'PENDING' : 'INCOMPLETE');
            $st_class = $is_success_effective ? 'row-success' : ($r['err'] !== '' ? 'row-fail' : '');
            echo '<tr class="' . $st_class . '" data-order-no="' . htmlspecialchars($r['no']) . '">';
            echo '<td class="cell-num">' . $i . '</td>';
            echo '<td class="cell-mono">' . htmlspecialchars($r['time_short']) . '</td>';
            $cc0 = (int)($r['cluster_cnt'] ?? 1);
            $is_merged_row0 = ($cluster_prefix6_enabled && ($r['group_key'] ?? '') === 'fail' && $cc0 > 1);
            $order_no_show = (string)($r['no'] ?? '');
            if ($is_merged_row0) {
                $order_no_show = (string)($r['prefix6'] ?? $order_no_show);
            }
            $order_no_html = htmlspecialchars($order_no_show);
            if ($is_merged_row0) {
                $order_no_html = '<span class="order-no-prefix6-merged">' . $order_no_html . '</span>';
            }
            if ($is_merged_row0) {
                $order_no_html .= ' (合并' . (int)$cc0 . '条)';
            }
            echo '<td class="cell-mono">' . $order_no_html . '</td>';
            echo '<td class="cell-domain">';
            echo '<button type="button" class="copy-domain-btn" data-copy-domain="' . htmlspecialchars($r['domain']) . '">复制</button>';
            echo '<span style="margin-left:6px;">' . htmlspecialchars($r['domain']) . '</span>';
            echo '</td>';
            if ($has_people) {
                echo '<td>' . ($r['people'] !== '' ? htmlspecialchars($r['people']) : '<span style="color:#c2410c; font-weight:700;">未匹配</span>') . '</td>';
            }
            if ($has_server) {
                echo '<td class="cell-mono">' . htmlspecialchars((string)($r['server'] ?? '')) . '</td>';
            }
            if ($has_country) echo '<td>' . htmlspecialchars($r['country']) . '</td>';
            if ($has_category) echo '<td class="cell-ellipsis" title="' . htmlspecialchars($r['category']) . '">' . htmlspecialchars($r['category']) . '</td>';
            if ($has_date) echo '<td class="cell-mono">' . htmlspecialchars($r['site_date']) . '</td>';
            echo '<td class="cell-num" style="text-align:right;">' . htmlspecialchars($r['cur']) . ' ' . format_money($r['amt']) . '</td>';
            $usd_basis_title = (string)($r['usd_basis'] ?? '');
            $usd_show = ($r['usd'] > 0 ? ('$' . format_money($r['usd'])) : '');
            if ($usd_show !== '' && $usd_basis_title !== '') {
                $usd_show .= '<div style="font-size:11px; color:#94a3b8; line-height:1.1;" title="' . htmlspecialchars($usd_basis_title) . '">' . htmlspecialchars($usd_basis_title) . '</div>';
            }
            echo '<td class="cell-num" style="text-align:right;">' . $usd_show . '</td>';
            echo '<td class="cell-num" style="text-align:right;">' . (int)$r['attempts'] . '</td>';
            echo '<td class="cell-num" style="text-align:right;">' . (int)$r['notify_cnt'] . '</td>';
            echo '<td><span class="excel-status ' . ($is_success_effective ? 'is-ok' : 'is-warn') . '">' . $st . '</span></td>';
            $err_show = $r['err'];
            if ($is_pending && !$pending_as_success0) {
                $err_show = ($err_show !== '' ? ($err_show . ' | ') : '') . 'success信息存在但未满足最终成功条件(需要forpay_new/forpay/notify/success四个日志都存在)';
            }
            echo '<td class="cell-ellipsis" title="' . htmlspecialchars($err_show) . '">' . htmlspecialchars($err_show) . '</td>';
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

    $sort_orders_inplace($analysis_data);

    $display_orders = [];
    $prefix_cnt = [];
    foreach ($analysis_data as $no => $item) {
        if (!order_matches_status_filter($item, $status_filter)) {
            continue;
        }
        $oi0 = get_owner_info_for_domain($item['domain'] ?? '', $domain_owner_map);
        $ppl0 = $oi0 ? trim((string)($oi0['people'] ?? '')) : '';
        if (!owner_match_filter($ppl0, $owner_filter)) {
            continue;
        }
        $is_pending0 = (!empty($item['has_success_log']) && empty($item['is_success']));
        $is_success_effective0 = (!empty($item['is_success']) || ($pending_as_success0 && $is_pending0));
        $group_key0 = $is_success_effective0 ? 'success' : (!empty($item['has_success_log']) ? 'pending' : 'fail');

        $no0 = (string)$no;
        $p0 = (strlen($no0) > 2) ? substr($no0, 0, -2) : $no0;
        if ($p0 !== '' && $group_key0 === 'fail') {
            $prefix_cnt[$p0] = ($prefix_cnt[$p0] ?? 0) + 1;
        }
        $display_orders[$no] = $item;
    }

    if ($cluster_prefix6_enabled && !empty($display_orders)) {
        $seen_prefix = [];
        $clustered = [];
        foreach ($display_orders as $no => $item) {
            $no0 = (string)$no;
            $p0 = (strlen($no0) > 2) ? substr($no0, 0, -2) : $no0;
            $is_pending0 = (!empty($item['has_success_log']) && empty($item['is_success']));
            $is_success_effective0 = (!empty($item['is_success']) || ($pending_as_success0 && $is_pending0));
            $group_key0 = $is_success_effective0 ? 'success' : (!empty($item['has_success_log']) ? 'pending' : 'fail');

            if ($p0 !== '' && $group_key0 === 'fail' && isset($seen_prefix[$p0])) {
                continue;
            }
            if ($p0 !== '' && $group_key0 === 'fail') {
                $seen_prefix[$p0] = true;
            }
            $item['_cluster_cnt'] = (int)(($p0 !== '' && $group_key0 === 'fail') ? ($prefix_cnt[$p0] ?? 1) : 1);
            $clustered[$no] = $item;
        }
        $display_orders = $clustered;
    } else {
        foreach ($display_orders as $no => &$item) {
            $item['_cluster_cnt'] = 1;
        }
        unset($item);
    }

    if ($group_by_domain) {
        $grouped = [];
        foreach ($display_orders as $no => $item) {
            if (!order_matches_status_filter($item, $status_filter)) {
                continue;
            }

            $dom_key = normalize_domain_key($item['domain'] ?? '');
            $owner = ($dom_key !== '' && isset($domain_owner_map[$dom_key])) ? $domain_owner_map[$dom_key] : null;
            $people = $owner ? trim((string)($owner['people'] ?? '')) : '';
            if (!owner_match_filter($people, $owner_filter)) {
                continue;
            }
            $grouped[$item['domain']][] = ['no' => $no, 'item' => $item];
        }
        $group_index = 1;

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
            if ($has_people || $has_country || $has_category || $has_date || $has_server) {
                $dom_key = normalize_domain_key($domain);
                $owner = ($dom_key !== '' && isset($domain_owner_map[$dom_key])) ? $domain_owner_map[$dom_key] : null;
                $people = $owner ? trim((string)($owner['people'] ?? '')) : '';
                $server = $owner ? trim((string)($owner['server'] ?? '')) : '';
                $server_short = '';
                if ($server !== '' && preg_match('/^\s*(.)/us', $server, $m)) {
                    $server_short = $m[1];
                }
                $country = $owner ? trim((string)($owner['country'] ?? '')) : '';
                $category = $owner ? trim((string)($owner['category'] ?? '')) : '';
                $site_date = $owner ? trim((string)($owner['date'] ?? '')) : '';
                if ($people !== '') {
                    echo '<span class="badge badge-attempts" style="margin-left:10px; background:#eef2ff; color:#4f46e5;">人员:' . htmlspecialchars($people) . '</span>';
                }
                if ($has_server && $server_short !== '') {
                    echo '<span class="badge badge-attempts" style="margin-left:6px; background:#fefce8; color:#a16207;">服务器:' . htmlspecialchars($server_short) . '</span>';
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
                $is_pending = (!empty($item['has_success_log']) && empty($item['is_success']));
                $is_success_effective = (!empty($item['is_success']) || ($pending_as_success0 && $is_pending));
                $st_class = $is_success_effective ? 'is-success' : (!empty($item['details']['err']) ? 'is-fail' : '');
                echo '<div class="order-item ' . $st_class . '" style="margin-bottom:8px;">';
                echo '<div class="order-main" onclick="toggleLog(\'log_' . $no . '\')">';
                echo '<div style="flex:1;">';
                echo '<div class="order-tags" style="display:flex; align-items:center; gap:8px; flex-wrap:wrap;">';
                echo '<span style="font-size:13px; color:#64748b; font-weight:bold; background:#f1f5f9; border-radius:6px; padding:2px 8px; margin-right:6px;">' . $order_index . '</span>';
                $order_index++;
                echo '<strong style="font-size:15px;">' . htmlspecialchars($item['domain']) . '</strong>';
                echo '<button type="button" class="copy-domain-btn" data-copy-domain="' . htmlspecialchars($item['domain']) . '">复制域名</button>';
                if ($has_people || $has_country || $has_category || $has_date || $has_server) {
                    $dom_key = normalize_domain_key($item['domain'] ?? '');
                    $owner = ($dom_key !== '' && isset($domain_owner_map[$dom_key])) ? $domain_owner_map[$dom_key] : null;
                    $people = $owner ? trim((string)($owner['people'] ?? '')) : '';
                    $server = $owner ? trim((string)($owner['server'] ?? '')) : '';
                    $server_short = '';
                    if ($server !== '' && preg_match('/^\s*(.)/us', $server, $m)) {
                        $server_short = $m[1];
                    }
                    $country = $owner ? trim((string)($owner['country'] ?? '')) : '';
                    $category = $owner ? trim((string)($owner['category'] ?? '')) : '';
                    $date = $owner ? trim((string)($owner['date'] ?? '')) : '';
                    if ($people !== '') {
                        echo '<span class="badge badge-attempts" style="background:#eef2ff; color:#4f46e5;">人员:' . htmlspecialchars($people) . '</span>';
                    } else {
                        echo '<span class="badge badge-attempts" style="background:#fff7ed; color:#c2410c;">人员:未匹配</span>';
                    }
                    if ($has_server && $server_short !== '') {
                        echo '<span class="badge badge-attempts" style="background:#fefce8; color:#a16207;">服务器:' . htmlspecialchars($server_short) . '</span>';
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
                $usd_basis0 = trim((string)($item['details']['usd_basis'] ?? ''));
                $usd_basis_show0 = ($usd_basis0 !== '') ? (' (' . htmlspecialchars($usd_basis0) . ')') : '';
                $cc0 = (int)($item['_cluster_cnt'] ?? 1);
                $is_pending1 = (!empty($item['has_success_log']) && empty($item['is_success']));
                $is_success_effective1 = (!empty($item['is_success']) || ($pending_as_success0 && $is_pending1));
                $group_key1 = $is_success_effective1 ? 'success' : (!empty($item['has_success_log']) ? 'pending' : 'fail');
                $cc_show0 = ($cluster_prefix6_enabled && $group_key1 === 'fail' && $cc0 > 1) ? (' · 合并' . $cc0 . '条') : '';
                $no_show0 = (string)$no;
                if ($cluster_prefix6_enabled && $group_key1 === 'fail' && $cc0 > 1) {
                    $no_show0 = (strlen($no_show0) > 2) ? substr($no_show0, 0, -2) : $no_show0;
                }
                $no_show_html0 = htmlspecialchars($no_show0);
                if ($cluster_prefix6_enabled && $group_key1 === 'fail' && $cc0 > 1) {
                    $no_show_html0 = '<span class="order-no-prefix6-merged">' . $no_show_html0 . '</span>';
                }
                echo '<div style="font-size:12px; color:#94a3b8; margin-top:4px;">单号: ' . $no_show_html0 . $cc_show0 . ' · ' . substr($item['time'], 11) . $usd_basis_show0 . '</div>';
                if (!empty($item['details']['err'])) {
                    echo '<div class="error-msg">⚠️ ' . htmlspecialchars($item['details']['err']) . '</div>';
                }
                if (!$pending_as_success0 && empty($item['is_success']) && !empty($item['has_success_log'])) {
                    echo '<div class="error-msg">⚠️ ' . htmlspecialchars('success信息存在但未满足最终成功条件(需要forpay_new/forpay/notify/success四个日志都存在)') . '</div>';
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
                $is_pending = (!empty($item['has_success_log']) && empty($item['is_success']));
                $is_success_effective = (!empty($item['is_success']) || ($pending_as_success0 && $is_pending));
                $st_text = ($is_success_effective ? 'SUCCESS' : ($is_pending ? 'PENDING' : 'INCOMPLETE'));
                echo '<span class="badge" style="background:' . ($is_success_effective ? '#ecfdf5' : '#f8fafc') . '; color:' . ($is_success_effective ? '#059669' : '#64748b') . ';">' . $st_text . '</span>';
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
        $grouped_orders = [
            'success' => [],
            'pending' => [],
            'fail' => []
        ];
        foreach ($display_orders as $no => $item) {
            if (!order_matches_status_filter($item, $status_filter)) {
                continue;
            }
            if (!empty($item['is_success'])) {
                $grouped_orders['success'][$no] = $item;
            } elseif (!empty($item['has_success_log'])) {
                if ($pending_as_success0) {
                    $grouped_orders['success'][$no] = $item;
                } else {
                    $grouped_orders['pending'][$no] = $item;
                }
            } else {
                $grouped_orders['fail'][$no] = $item;
            }
        }

        if ($pending_as_success0) {
            unset($grouped_orders['pending']);
        }

        foreach ($grouped_orders as $k => &$orders_ref) {
            $sort_orders_inplace($orders_ref);
        }
        unset($orders_ref);

        $group_titles = [
            'success' => '✅ 成功订单',
            'pending' => '🟨 待定订单',
            'fail' => '❌ 失败订单'
        ];
        if ($pending_as_success0) {
            unset($group_titles['pending']);
        }
        foreach ($grouped_orders as $group_key => $orders) {
            if (($status_filter === 'success' || $status_filter === 'pending' || $status_filter === 'fail') && $group_key !== $status_filter) {
                continue;
            }
            if (empty($orders)) {
                continue;
            }
            $group_id = 'order_group_' . $group_key;
            $border = ($group_key === 'success' ? '#10b981' : ($group_key === 'pending' ? '#f59e0b' : '#ef4444'));
            $color = ($group_key === 'success' ? '#10b981' : ($group_key === 'pending' ? '#b45309' : '#ef4444'));
            echo '<div class="order-item" id="' . $group_id . '_wrap" data-order-group-wrap="' . $group_key . '" style="border-left:5px solid ' . $border . '; margin-bottom:18px;">';
            echo '<div class="order-main" data-order-group-header="' . $group_key . '" style="cursor:pointer;user-select:none;" onclick="var el=document.getElementById(\'' . $group_id . '\');el.style.display=(el.style.display==\'none\'?\'block\':\'none\');">';
            echo '<span style="font-size:15px; font-weight:bold; color:' . $color . ';">' . $group_titles[$group_key] . '</span>';
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
            $default_open = ($group_key === 'fail' && $status_filter !== 'success' && $status_filter !== 'pending')
                || ($group_key === 'success' && $status_filter === 'success')
                || ($group_key === 'pending' && $status_filter === 'pending');
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
                if ($has_people || $has_country || $has_category || $has_date || $has_server) {
                    $country = $owner ? trim((string)($owner['country'] ?? '')) : '';
                    $category = $owner ? trim((string)($owner['category'] ?? '')) : '';
                    $date = $owner ? trim((string)($owner['date'] ?? '')) : '';
                    $server = $owner ? trim((string)($owner['server'] ?? '')) : '';
                    $server_short = '';
                    if ($server !== '' && preg_match('/^\s*(.)/us', $server, $m)) {
                        $server_short = $m[1];
                    }
                    if ($people !== '') {
                        echo '<span class="badge badge-attempts" style="background:#eef2ff; color:#4f46e5;">人员:' . htmlspecialchars($people) . '</span>';
                    } else {
                        echo '<span class="badge badge-attempts" style="background:#fff7ed; color:#c2410c;">人员:未匹配</span>';
                    }
                    if ($has_server && $server_short !== '') {
                        echo '<span class="badge badge-attempts" style="background:#fefce8; color:#a16207;">服务器:' . htmlspecialchars($server_short) . '</span>';
                    }
                    if ($has_country && $country !== '') {
                        echo '<span class="badge badge-attempts" style="background:#ecfeff; color:#0e7490;">' . htmlspecialchars($country) . '</span>';
                    }
                    if ($has_category && $category !== '') {
                        echo '<span class="badge badge-attempts" style="background:#f0fdf4; color:#166534;">' . htmlspecialchars($category) . '</span>';
                    }
                    if ($has_date && $date !== '') {
                        echo '<span class="badge badge-attempts" style="background:#f1f5f9; color:#334155;">' . htmlspecialchars($date) . '</span>';
                    }
                }
                $notify_cnt = (int)($item['details']['notify_count'] ?? 0);
                echo '<span class="badge badge-attempts">' . $notify_cnt . '条notify</span>';
                echo '</div>';
                $usd_basis0 = trim((string)($item['details']['usd_basis'] ?? ''));
                $usd_basis_show0 = ($usd_basis0 !== '') ? (' (' . htmlspecialchars($usd_basis0) . ')') : '';
                $cc0 = (int)($item['_cluster_cnt'] ?? 1);
                $is_pending1 = (!empty($item['has_success_log']) && empty($item['is_success']));
                $is_success_effective1 = (!empty($item['is_success']) || ($pending_as_success0 && $is_pending1));
                $group_key1 = $is_success_effective1 ? 'success' : (!empty($item['has_success_log']) ? 'pending' : 'fail');
                $cc_show0 = ($cluster_prefix6_enabled && $group_key1 === 'fail' && $cc0 > 1) ? (' · 合并' . $cc0 . '条') : '';
                $no_show0 = (string)$no;
                if ($cluster_prefix6_enabled && $group_key1 === 'fail' && $cc0 > 1) {
                    $no_show0 = (strlen($no_show0) >= 6) ? substr($no_show0, 0, 6) : $no_show0;
                }
                $no_show_html0 = htmlspecialchars($no_show0);
                if ($cluster_prefix6_enabled && $group_key1 === 'fail' && $cc0 > 1) {
                    $no_show_html0 = '<span class="order-no-prefix6-merged">' . $no_show_html0 . '</span>';
                }
                echo '<div style="font-size:12px; color:#94a3b8; margin-top:4px;">单号: ' . $no_show_html0 . $cc_show0 . ' · ' . substr($item['time'], 11) . $usd_basis_show0 . '</div>';
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
                $is_pending = (!empty($item['has_success_log']) && empty($item['is_success']));
                $st_text = (!empty($item['is_success']) ? 'SUCCESS' : ($is_pending ? 'PENDING' : 'INCOMPLETE'));
                echo '<span class="badge" style="background:' . (!empty($item['is_success']) ? '#ecfdf5' : '#f8fafc') . '; color:' . (!empty($item['is_success']) ? '#059669' : '#64748b') . ';">' . $st_text . '</span>';
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
