<?php
$css_file = __DIR__ . '/orders3.css';
if (!is_file($css_file) || !is_readable($css_file)) {
    http_response_code(404);
    header('Content-Type: text/plain; charset=UTF-8');
    echo 'CSS not found';
    exit;
}

header('Content-Type: text/css; charset=UTF-8');
header('Cache-Control: no-cache, no-store, must-revalidate');
header('Pragma: no-cache');
header('Expires: 0');

readfile($css_file);
