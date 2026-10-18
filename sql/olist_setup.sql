-- Olist e-commerce setup for PostgreSQL
-- Run in psql (not the pgAdmin query tool), because \copy and \cd are psql commands.
-- Steps:
--   1. CREATE DATABASE olist_analytics;   then connect:  \c olist_analytics
--   2. \cd 'C:/path/to/extracted/csv/folder'
--   3. \i olist_setup.sql

DROP TABLE IF EXISTS order_reviews, order_payments, order_items, orders,
  customers, products, sellers, geolocation, category_translation CASCADE;

CREATE TABLE customers (
  customer_id              TEXT PRIMARY KEY,   -- changes per order
  customer_unique_id       TEXT NOT NULL,      -- the real customer: use this for retention
  customer_zip_code_prefix INT,
  customer_city            TEXT,
  customer_state           TEXT
);

CREATE TABLE orders (
  order_id                       TEXT PRIMARY KEY,
  customer_id                    TEXT REFERENCES customers(customer_id),
  order_status                   TEXT,
  order_purchase_timestamp       TIMESTAMP,
  order_approved_at              TIMESTAMP,
  order_delivered_carrier_date   TIMESTAMP,
  order_delivered_customer_date  TIMESTAMP,
  order_estimated_delivery_date  TIMESTAMP
);

CREATE TABLE products (
  product_id                 TEXT PRIMARY KEY,
  product_category_name      TEXT,
  product_name_lenght        INT,   -- spelling matches the CSV header
  product_description_lenght INT,
  product_photos_qty         INT,
  product_weight_g           INT,
  product_length_cm          INT,
  product_height_cm          INT,
  product_width_cm           INT
);

CREATE TABLE sellers (
  seller_id              TEXT PRIMARY KEY,
  seller_zip_code_prefix INT,
  seller_city            TEXT,
  seller_state           TEXT
);

CREATE TABLE order_items (
  order_id            TEXT,
  order_item_id       INT,
  product_id          TEXT,
  seller_id           TEXT,
  shipping_limit_date TIMESTAMP,
  price               NUMERIC(10,2),
  freight_value       NUMERIC(10,2),
  PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE order_payments (
  order_id             TEXT,
  payment_sequential   INT,
  payment_type         TEXT,
  payment_installments INT,
  payment_value        NUMERIC(10,2),
  PRIMARY KEY (order_id, payment_sequential)
);

-- review_id is NOT unique in the raw data, so no primary key here
CREATE TABLE order_reviews (
  review_id               TEXT,
  order_id                TEXT,
  review_score            INT,
  review_comment_title    TEXT,
  review_comment_message  TEXT,
  review_creation_date    TIMESTAMP,
  review_answer_timestamp TIMESTAMP
);

-- many duplicate rows per zip prefix, so no primary key
CREATE TABLE geolocation (
  geolocation_zip_code_prefix INT,
  geolocation_lat             DOUBLE PRECISION,
  geolocation_lng             DOUBLE PRECISION,
  geolocation_city            TEXT,
  geolocation_state           TEXT
);

CREATE TABLE category_translation (
  product_category_name         TEXT,
  product_category_name_english TEXT
);

\copy customers            FROM 'olist_customers_dataset.csv'        WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy orders               FROM 'olist_orders_dataset.csv'           WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy products             FROM 'olist_products_dataset.csv'         WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy sellers              FROM 'olist_sellers_dataset.csv'          WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy order_items          FROM 'olist_order_items_dataset.csv'      WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy order_payments       FROM 'olist_order_payments_dataset.csv'   WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy order_reviews        FROM 'olist_order_reviews_dataset.csv'    WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy geolocation          FROM 'olist_geolocation_dataset.csv'      WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy category_translation FROM 'product_category_name_translation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- Sanity checks: expected approx counts in the comments
SELECT 'customers' AS t, COUNT(*) FROM customers             -- ~99,441
UNION ALL SELECT 'orders',      COUNT(*) FROM orders          -- ~99,441
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items     -- ~112,650
UNION ALL SELECT 'payments',    COUNT(*) FROM order_payments  -- ~103,886
UNION ALL SELECT 'reviews',     COUNT(*) FROM order_reviews   -- ~99,224
UNION ALL SELECT 'products',    COUNT(*) FROM products        -- ~32,951
UNION ALL SELECT 'sellers',     COUNT(*) FROM sellers         -- ~3,095
UNION ALL SELECT 'geolocation', COUNT(*) FROM geolocation;    -- ~1,000,163

-- The key number for the whole project: unique customers vs orders
SELECT COUNT(*) AS orders, COUNT(DISTINCT customer_unique_id) AS unique_customers
FROM orders o JOIN customers c USING (customer_id);
