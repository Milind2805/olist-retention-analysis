-- 1. Order status mix
SELECT order_status, COUNT(*) FROM orders GROUP BY 1 ORDER BY 2 DESC;

-- 2. Date range of the data
SELECT MIN(order_purchase_timestamp), MAX(order_purchase_timestamp) FROM orders;

-- 3. How many orders per unique customer?
SELECT orders_per_customer, COUNT(*) AS customers
FROM (
  SELECT c.customer_unique_id, COUNT(*) AS orders_per_customer
  FROM orders o JOIN customers c USING (customer_id)
  GROUP BY 1
) t
GROUP BY 1 ORDER BY 1;

-- 4. Missing delivery dates by status
SELECT order_status,
       COUNT(*) AS orders,
       COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS no_delivery_date
FROM orders GROUP BY 1 ORDER BY 2 DESC;
