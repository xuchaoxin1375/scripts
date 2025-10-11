SELECT 
    o.id AS order_id,
    -- 日期字段
    o.date_created_gmt,
    o.date_updated_gmt,
    
    -- 金额字段
    os.total_sales,
    os.shipping_total,
    os.net_total,
    o.total_amount,
    
    -- 订单状态信息
    o.status,
    o.customer_id,
    o.currency,
    
    -- 支付信息
    o.payment_method,
    o.payment_method_title,
    
    -- 客户信息（来自地址表）
    ba.first_name AS billing_first_name,
    ba.last_name AS billing_last_name,
    ba.email AS billing_email,
    ba.phone AS billing_phone,
    ba.country AS billing_country,
    
    -- 其他信息
    o.ip_address
    
FROM wp_wc_orders o
LEFT JOIN wp_wc_order_stats os ON o.id = os.order_id
LEFT JOIN wp_wc_order_addresses ba ON (
    o.id = ba.order_id 
    AND ba.address_type = 'billing'
)
ORDER BY o.date_created_gmt DESC;