<?php

$APP_VERSION = $APP_VERSION ?? 'v2.0.20260203';
$access_token = $access_token ?? 'cxxu';

$CSV_HEADER_CANDIDATES = $CSV_HEADER_CANDIDATES ?? [
    'domain' => ['域名', '网站', '站点', 'domain', 'site'],
    'people' => ['数据采集员', '数据采集人员', '人员', '归属人员', '名字', '姓名', '采集员'],
    'country' => ['国家', '语言', '网站语言', '站点语言', 'lang', 'country'],
    'category' => ['内容', '产品类别', '产品分类', '品类', '类目', '类别', '产品', 'category', 'productcategory'],
    'date' => ['完成日期', '建站日期', '申请日期', '域名申请日期', '日期', '创建日期', '上线日期', '完成时间', '时间', 'date', 'createdate', 'created_at', 'updated_at'],
    'server' => ['服务器', 'server'],
];

$ORDERS3_LOG_CSV_FIELDS = $ORDERS3_LOG_CSV_FIELDS ?? false;
$ORDERS3_CSV_FIELDS_LOG_PATH = $ORDERS3_CSV_FIELDS_LOG_PATH ?? (__DIR__ . '/../orders3_csv_fields.log');
