<?php

function orders3_require_token($access_token)
{
    $current_token = $_GET['token'] ?? '';
    if ($current_token !== $access_token) {
        http_response_code(403);
        die('403 Forbidden');
    }
}
