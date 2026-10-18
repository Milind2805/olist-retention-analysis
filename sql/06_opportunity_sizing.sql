-- Question: how much is a repeat customer worth, and what would a small
-- improvement in the return rate add?

-- 1. First orders vs repeat orders: volume, value, share of GMV
-- Finding: First orders make up 97.1% of GMV (R$12.84M); repeat orders are only 2.9% (R$0.38M) and are 11% smaller on average.
WITH ranked AS (
  SELECT customer_unique_id,
         order_id,
         items_value,
         ROW_NUMBER() OVER (
           PARTITION BY customer_unique_id
           ORDER BY order_purchase_timestamp, order_id
         ) AS order_seq
  FROM clean_orders
)
SELECT CASE WHEN order_seq = 1 THEN 'First order' ELSE 'Repeat order' END AS order_type,
       COUNT(*)                                   AS orders,
       ROUND(SUM(items_value), 0)                 AS gmv,
       ROUND(AVG(items_value), 2)                 AS avg_order_value,
       ROUND(100.0 * SUM(items_value) / SUM(SUM(items_value)) OVER (), 1) AS pct_of_gmv
FROM ranked
GROUP BY 1
ORDER BY 1;


-- ---------------------------------------------------------------
-- 2. Scenario: what if the 90-day return rate improved?
-- Finding: Raising the 90-day return rate by 1 percentage point would add about 744 returners and R$91k GMV, under 1% of cohort GMV (lower-bound estimate).
-- ---------------------------------------------------------------
WITH ranked AS (
  SELECT items_value,
         ROW_NUMBER() OVER (
           PARTITION BY customer_unique_id
           ORDER BY order_purchase_timestamp, order_id
         ) AS order_seq
  FROM clean_orders
),
repeat_value AS (
  SELECT AVG(items_value) AS repeat_aov
  FROM ranked
  WHERE order_seq >= 2
),
base AS (
  SELECT COUNT(*) AS customers,
         SUM(returned_90d::int) AS returned
  FROM first_order_outcomes
)
SELECT b.customers,
       b.returned                                        AS returners_now,
       ROUND(100.0 * b.returned / b.customers, 2)        AS return_rate_now_pct,
       ROUND(v.repeat_aov, 2)                            AS avg_repeat_order_value,
       s.uplift_pts                                      AS uplift_pct_points,
       ROUND(b.customers * s.uplift_pts / 100.0)         AS extra_returners,
       ROUND(b.customers * s.uplift_pts / 100.0 * v.repeat_aov) AS extra_gmv
FROM base b
CROSS JOIN repeat_value v
CROSS JOIN (VALUES (0.5), (1.0), (2.0)) AS s(uplift_pts)
ORDER BY s.uplift_pts;