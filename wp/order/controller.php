<?php

function orders3_handle_partials_and_exports(
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
) {
    $is_partial_order_list = ($view_mode === 'analysis' && (($_GET['partial'] ?? '') === 'order_list'));
    if ($is_partial_order_list) {
        header('Content-Type: text/html; charset=UTF-8');
        $csv_files = list_csv_files_in_dir(dirname(__DIR__));
        $csv_path = resolve_selected_csv_path(dirname(__DIR__), $csv_selected, $csv_files);
        echo render_order_list_items($analysis_data, $group_by_domain, $order_sort, $status_filter, $owner_filter, $csv_path, $list_view);
        return true;
    }

    $is_partial_range_revenue_json = ($view_mode === 'analysis' && (($_GET['partial'] ?? '') === 'range_revenue_json'));
    if ($is_partial_range_revenue_json) {
        header('Content-Type: application/json; charset=UTF-8');
        [$min_date0, $max_date0] = find_available_log_date_range();
        $rs0 = (string)($_GET['range_start'] ?? '');
        $re0 = (string)($_GET['range_end'] ?? '');
        $range_error0 = validate_date_range($rs0, $re0, $min_date0, $max_date0);
        $rev_days0 = [];
        if ($range_error0 === '') {
            $csv_files0 = list_csv_files_in_dir(dirname(__DIR__));
            $csv_path0 = resolve_selected_csv_path(dirname(__DIR__), $csv_selected, $csv_files0);
            $csv_data0 = load_domain_owner_map_from_csv($csv_path0);
            $GLOBALS['ORDERS3_RANGE_CSV_DOMAIN_OWNER_MAP'] = (
                !empty($csv_data0['meta']['has_people'])
                && !empty($csv_data0['map'])
                && is_array($csv_data0['map'])
            ) ? $csv_data0['map'] : null;
            $rev_days0 = compute_range_revenue_days($rs0, $re0, $pending_as_success);
        }
        echo json_encode([
            'meta' => [
                'min_date' => $min_date0,
                'max_date' => $max_date0,
                'range_start' => $rs0,
                'range_end' => $re0,
                'range_error' => $range_error0,
            ],
            'data' => $rev_days0,
        ], JSON_UNESCAPED_UNICODE);
        return true;
    }

    $is_partial_range_revenue = ($view_mode === 'analysis' && (($_GET['partial'] ?? '') === 'range_revenue'));
    if ($is_partial_range_revenue) {
        header('Content-Type: text/html; charset=UTF-8');
        [$min_date0, $max_date0] = find_available_log_date_range();
        $rs0 = (string)($_GET['range_start'] ?? '');
        $re0 = (string)($_GET['range_end'] ?? '');
        $range_error0 = validate_date_range($rs0, $re0, $min_date0, $max_date0);
        $rev_days0 = [];
        if ($range_error0 === '') {
            $rev_days0 = compute_range_revenue_days($rs0, $re0, $pending_as_success);
        }
        echo render_range_revenue_module($access_token, $view_mode, $rs0, $re0, $min_date0, $max_date0, $rev_days0, $range_error0);
        return true;
    }

    $is_export_orders_csv = ($view_mode === 'analysis' && (($_GET['export'] ?? '') === 'orders_csv'));
    if ($is_export_orders_csv) {
        $rs0 = (string)($_GET['export_start'] ?? ($_GET['range_start'] ?? ''));
        $re0 = (string)($_GET['export_end'] ?? ($_GET['range_end'] ?? ''));
        export_orders_csv_range($access_token, $rs0, $re0, $status_filter, $owner_filter, $amount_nonzero, $csv_selected);
        return true;
    }

    $is_partial_analysis = ($view_mode === 'analysis' && (($_GET['partial'] ?? '') === 'analysis'));
    if ($is_partial_analysis) {
        header('Content-Type: text/html; charset=UTF-8');
        echo render_analysis_content($access_token, $view_mode, $log_date, $stats, $analysis_data, $group_by_domain, $order_sort, $status_filter, $owner_filter, $csv_selected);
        return true;
    }

    return false;
}
