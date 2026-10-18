SELECT COUNT(*) AS orders, COUNT(DISTINCT customer_unique_id) AS customers
FROM clean_orders;

SELECT date_trunc('month', order_purchase_timestamp)::date AS month,
       COUNT(*) AS orders
FROM clean_orders
GROUP BY 1 ORDER BY 1;
