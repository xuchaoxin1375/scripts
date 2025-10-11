/* 查询woocommerce订单数据 （相对丰富的信息）*/
SELECT 
    o.id AS order_id,
    o.status AS order_status,
    DATE_FORMAT(o.date_created_gmt, '%Y-%m-%d %H:%i:%s') AS order_date,
    o.total_amount AS order_total,
    o.currency,
    o.payment_method,
    o.payment_method_title,
    
    -- Customer information
    o.billing_email,
    CONCAT(ba.first_name, ' ', ba.last_name) AS billing_name,
    ba.company AS billing_company,
    ba.address_1 AS billing_address_1,
    ba.address_2 AS billing_address_2,
    ba.city AS billing_city,
    ba.state AS billing_state,
    ba.postcode AS billing_postcode,
    ba.country AS billing_country,
    ba.phone AS billing_phone,
    
    -- Shipping information
    CONCAT(sa.first_name, ' ', sa.last_name) AS shipping_name,
    sa.company AS shipping_company,
    sa.address_1 AS shipping_address_1,
    sa.address_2 AS shipping_address_2,
    sa.city AS shipping_city,
    sa.state AS shipping_state,
    sa.postcode AS shipping_postcode,
    sa.country AS shipping_country,
    
    -- Order details
    os.num_items_sold AS items_count,
    os.total_sales AS subtotal,
    os.tax_total,
    os.shipping_total,
    os.net_total,
    od.shipping_tax_amount,
    od.shipping_total_amount,
    od.discount_total_amount,
    
    -- Product details (aggregated)
    (
        SELECT GROUP_CONCAT(
            CONCAT(oi.order_item_name, ' (Qty: ', oim_qty.meta_value, ')') 
            SEPARATOR ' | '
        )
        FROM wp_woocommerce_order_items oi
        LEFT JOIN wp_woocommerce_order_itemmeta oim_qty ON (
            oim_qty.order_item_id = oi.order_item_id 
            AND oim_qty.meta_key = '_qty'
        )
        WHERE oi.order_id = o.id AND oi.order_item_type = 'line_item'
    ) AS products,
    
    -- Shipping method
    (
        SELECT GROUP_CONCAT(oi.order_item_name SEPARATOR ' | ')
        FROM wp_woocommerce_order_items oi
        WHERE oi.order_id = o.id AND oi.order_item_type = 'shipping'
    ) AS shipping_method,
    
    -- Operational data
    od.woocommerce_version,
    od.cart_hash,
    od.date_paid_gmt,
    od.date_completed_gmt,
    
    -- Attribution data
    MAX(om_source.meta_value) AS traffic_source,
    MAX(om_referrer.meta_value) AS referrer,
    MAX(om_device.meta_value) AS device_type,
    MAX(om_session_pages.meta_value) AS session_pages,
    MAX(om_session_count.meta_value) AS session_count
    
FROM wp_wc_orders o
LEFT JOIN wp_wc_order_stats os ON o.id = os.order_id
LEFT JOIN wp_wc_order_operational_data od ON o.id = od.order_id
LEFT JOIN wp_wc_order_addresses ba ON (
    o.id = ba.order_id 
    AND ba.address_type = 'billing'
)
LEFT JOIN wp_wc_order_addresses sa ON (
    o.id = sa.order_id 
    AND sa.address_type = 'shipping'
)
LEFT JOIN wp_wc_orders_meta om_source ON (
    o.id = om_source.order_id 
    AND om_source.meta_key = '_wc_order_attribution_source_type'
)
LEFT JOIN wp_wc_orders_meta om_referrer ON (
    o.id = om_referrer.order_id 
    AND om_referrer.meta_key = '_wc_order_attribution_referrer'
)
LEFT JOIN wp_wc_orders_meta om_device ON (
    o.id = om_device.order_id 
    AND om_device.meta_key = '_wc_order_attribution_device_type'
)
LEFT JOIN wp_wc_orders_meta om_session_pages ON (
    o.id = om_session_pages.order_id 
    AND om_session_pages.meta_key = '_wc_order_attribution_session_pages'
)
LEFT JOIN wp_wc_orders_meta om_session_count ON (
    o.id = om_session_count.order_id 
    AND om_session_count.meta_key = '_wc_order_attribution_session_count'
)
GROUP BY o.id  -- 关键去重逻辑
ORDER BY o.date_created_gmt DESC;