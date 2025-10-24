<?php
add_shortcode('dynamic_domain', function () {
    return str_replace(array('https://', 'http://', 'www.', '/'), '', home_url());
    // $domain = parse_url(home_url(), PHP_URL_HOST);
    // dynamic_domain
});

add_shortcode('current_year', function () {
    return date('Y');
});
add_shortcode('site_title', function () {
    return get_bloginfo('name');
});
add_filter('the_content', function($content) {
    // 获取当前站点的域名
    // $domain = parse_url(home_url(), PHP_URL_HOST);
    $domain=str_replace(array('https://', 'http://', 'www.', '/'), '', home_url());

    // 定义要替换的邮箱
    $old_email = 'KennethMiller9195608@gmail.com';
    $new_email = 'info@' . $domain;

    // 替换邮箱
    $content = str_replace($old_email, $new_email, $content);

    return $content;
});