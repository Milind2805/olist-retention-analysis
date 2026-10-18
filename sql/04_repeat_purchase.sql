-- Question: of the few customers who come back, how quickly do they return,
-- and is the "return" real or just a same-day split order?
-- All queries read from the clean_orders view (see 02_clean_view.sql).
-- Run each query separately (highlight it, then F5).

-- ---------------------------------------------------------------
-- 1. Overall repeat rate on the clean base
-- Finding: 3.0% of customers (2,801 of 93,350) placed more than one order.
-- ---------------------------------------------------------------
WITH per_customer AS (
  SELECT customer_unique_id, COUNT(*) AS n_orders
  FROM clean_orders
  GROUP BY 1
)
SELECT COUNT(*)                                        AS customers,
       COUNT(*) FILTER (WHERE n_orders >= 2)           AS repeat_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE n_orders >= 2) / COUNT(*), 2) AS repeat_pct
FROM per_customer;


-- ---------------------------------------------------------------
-- 2. Gap between first and second order, bucketed
-- 'Same day' rows are probably split carts, not real returns.
-- Finding: 29.6% of repeat customers ordered again the same day, so true returners are about 2.1%.
-- ---------------------------------------------------------------
WITH ranked AS (
  SELECT customer_unique_id,
         order_purchase_timestamp,
         ROW_NUMBER() OVER (
           PARTITION BY customer_unique_id
           ORDER BY order_purchase_timestamp, order_id
         ) AS order_seq
  FROM clean_orders
),
pairs AS (
  SELECT a.customer_unique_id,
         (b.order_purchase_timestamp::date - a.order_purchase_timestamp::date) AS gap_days
  FROM ranked a
  JOIN ranked b
    ON a.customer_unique_id = b.customer_unique_id
   AND a.order_seq = 1
   AND b.order_seq = 2
)
SELECT CASE
         WHEN gap_days = 0   THEN '1. Same day'
         WHEN gap_days <= 7  THEN '2. 1-7 days'
         WHEN gap_days <= 30 THEN '3. 8-30 days'
         WHEN gap_days <= 90 THEN '4. 31-90 days'
         WHEN gap_days <= 180 THEN '5. 91-180 days'
         ELSE '6. 181+ days'
       END AS gap_bucket,
       COUNT(*) AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM pairs
GROUP BY 1
ORDER BY 1;


-- ---------------------------------------------------------------
-- 3. Median days to return, excluding same-day orders
-- Finding: Median time to a real second order is 75 days.
-- ---------------------------------------------------------------
WITH ranked AS (
  SELECT customer_unique_id,
         order_purchase_timestamp,
         ROW_NUMBER() OVER (
           PARTITION BY customer_unique_id
           ORDER BY order_purchase_timestamp, order_id
         ) AS order_seq
  FROM clean_orders
),
pairs AS (
  SELECT a.customer_unique_id,
         (b.order_purchase_timestamp::date - a.order_purchase_timestamp::date) AS gap_days
  FROM ranked a
  JOIN ranked b
    ON a.customer_unique_id = b.customer_unique_id
   AND a.order_seq = 1
   AND b.order_seq = 2
)
SELECT COUNT(*) AS true_returners,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gap_days) AS median_gap_days,
       ROUND(AVG(gap_days), 1) AS mean_gap_days
FROM pairs
WHERE gap_days >= 1;


-- ---------------------------------------------------------------
-- 4. 90-day return rate by first-order month (cohorts Feb 2017 - May 2018)
-- Cohorts after May 2018 are excluded: they have less than 90 days
-- of data after their first order, which would understate their return rate.
-- A 'return' = another order 1-90 days after the first (same-day excluded).
-- Finding: 90-day return rate is about 1.3% and flat across all monthly cohorts from Feb 2017 to May 2018.
-- ---------------------------------------------------------------
WITH ranked AS (
  SELECT customer_unique_id,
         order_purchase_timestamp,
         ROW_NUMBER() OVER (
           PARTITION BY customer_unique_id
           ORDER BY order_purchase_timestamp, order_id
         ) AS order_seq
  FROM clean_orders
),
first_orders AS (
  SELECT customer_unique_id,
         order_purchase_timestamp AS first_at
  FROM ranked
  WHERE order_seq = 1
),
returned AS (
  SELECT DISTINCT f.customer_unique_id
  FROM first_orders f
  JOIN clean_orders o
    ON o.customer_unique_id = f.customer_unique_id
   AND o.order_purchase_timestamp::date - f.first_at::date BETWEEN 1 AND 90
)
SELECT date_trunc('month', f.first_at)::date AS cohort_month,
       COUNT(*) AS new_customers,
       COUNT(r.customer_unique_id) AS returned_within_90d,
       ROUND(100.0 * COUNT(r.customer_unique_id) / COUNT(*), 2) AS return_rate_pct
FROM first_orders f
LEFT JOIN returned r USING (customer_unique_id)
WHERE f.first_at >= DATE '2017-02-01'
  AND f.first_at <  DATE '2018-06-01'
GROUP BY 1
ORDER BY 1;