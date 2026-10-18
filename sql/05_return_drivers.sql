-- Question: does the customer's FIRST experience affect whether they come back within 90 days?
-- Cohorts: first orders Feb 2017 - May 2018 (all have a full 90 days of follow-up).

CREATE OR REPLACE VIEW first_order_outcomes AS
WITH ranked AS (
  SELECT co.*,
         ROW_NUMBER() OVER (
           PARTITION BY customer_unique_id
           ORDER BY order_purchase_timestamp, order_id
         ) AS order_seq
  FROM clean_orders co
),
first_orders AS (
  SELECT * FROM ranked WHERE order_seq = 1
),
returned AS (
  SELECT DISTINCT f.customer_unique_id
  FROM first_orders f
  JOIN clean_orders o
    ON o.customer_unique_id = f.customer_unique_id
   AND o.order_purchase_timestamp::date - f.order_purchase_timestamp::date BETWEEN 1 AND 90
)
SELECT f.customer_unique_id,
       f.order_id,
       f.order_purchase_timestamp AS first_at,
       f.days_late,
       f.items_value,
       f.freight_value,
       f.customer_state,
       (r.customer_unique_id IS NOT NULL) AS returned_90d
FROM first_orders f
LEFT JOIN returned r USING (customer_unique_id)
WHERE f.order_purchase_timestamp >= DATE '2017-02-01'
  AND f.order_purchase_timestamp <  DATE '2018-06-01';

  SELECT COUNT(*) AS customers, SUM(returned_90d::int) AS returned
FROM first_order_outcomes;

-- 1. Return rate by first-order delivery performance
-- Finding: Late first deliveries cut 90-day return only slightly (1.0% vs 1.33%) and affect just 7.6% of customers, so delivery isn’t the main lever.
SELECT CASE
         WHEN days_late <= 0 THEN '1. On time or early'
         WHEN days_late <= 3 THEN '2. 1-3 days late'
         WHEN days_late <= 7 THEN '3. 4-7 days late'
         ELSE '4. 8+ days late'
       END AS delivery,
       COUNT(*) AS customers,
       SUM(returned_90d::int) AS returned,
       ROUND(100.0 * SUM(returned_90d::int) / COUNT(*), 2) AS return_rate_pct
FROM first_order_outcomes
GROUP BY 1
ORDER BY 1;

-- 2. Return rate by first-order review score
-- Finding: Return rate rises with review score (0.99% → 1.45%), but even 5-star customers rarely return.
WITH review AS (
  SELECT order_id, ROUND(AVG(review_score))::int AS score
  FROM order_reviews
  GROUP BY order_id
)
SELECT r.score AS review_score,
       COUNT(*) AS customers,
       SUM(f.returned_90d::int) AS returned,
       ROUND(100.0 * SUM(f.returned_90d::int) / COUNT(*), 2) AS return_rate_pct
FROM first_order_outcomes f
LEFT JOIN review r USING (order_id)
GROUP BY 1
ORDER BY 1;

-- 3. Return rate by category of the first order's most expensive item
-- Only categories with at least 500 customers, to avoid noisy small samples.
-- Finding:First-purchase category drives return rates from 0.58% to 2.29%; household and lifestyle categories retain best, electronics and office goods worst.
WITH top_item AS (
  SELECT DISTINCT ON (order_id) order_id, product_id
  FROM order_items
  ORDER BY order_id, price DESC
),
cat AS (
  SELECT ti.order_id,
         COALESCE(t.product_category_name_english,
                  p.product_category_name,
                  'unknown') AS category
  FROM top_item ti
  JOIN products p USING (product_id)
  LEFT JOIN category_translation t USING (product_category_name)
)
SELECT c.category,
       COUNT(*) AS customers,
       SUM(f.returned_90d::int) AS returned,
       ROUND(100.0 * SUM(f.returned_90d::int) / COUNT(*), 2) AS return_rate_pct
FROM first_order_outcomes f
JOIN cat c USING (order_id)
GROUP BY 1
HAVING COUNT(*) >= 500
ORDER BY return_rate_pct DESC;
 