CREATE OR REPLACE VIEW clean_orders AS
SELECT o.order_id,
       c.customer_unique_id,
       c.customer_state,
       o.order_purchase_timestamp,
       o.order_delivered_customer_date,
       o.order_estimated_delivery_date,
       (o.order_delivered_customer_date::date
          - o.order_estimated_delivery_date::date) AS days_late,
       i.items_value,
       i.freight_value
FROM orders o
JOIN customers c USING (customer_id)
JOIN (
  SELECT order_id,
         SUM(price) AS items_value,
         SUM(freight_value) AS freight_value
  FROM order_items
  GROUP BY order_id
) i USING (order_id)
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL;

  