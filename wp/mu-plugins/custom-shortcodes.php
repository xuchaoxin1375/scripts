<?php
add_shortcode('dynamic_domain', function () {
    return str_replace(array('https://', 'http://', 'www.', '/'), '', home_url());
    // dynamic_domain
});

add_shortcode('current_year', function () {
    return date('Y');
});
add_shortcode('site_title', function () {
    return get_bloginfo('name');
});

/**
 *移除woostify的信任徽章显示
 */
if (!function_exists('woostify_trust_badge_image')) {
    function woostify_trust_badge_image() {
        // 空函数，覆盖原有的
        return;
    }
} else {
    // 如果函数已存在，则重新定义
    remove_action('woocommerce_single_product_summary', 'woostify_trust_badge_image', 50);
}