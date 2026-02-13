-- ============================================================
-- 02_raw_tables.sql
-- Purpose: Create raw landing tables (no transformations)
-- Note: Dates are kept as TEXT in raw to avoid DateStyle issues.
-- ============================================================

------------ online_sales ------------
DROP TABLE IF EXISTS raw.online_sales;
CREATE TABLE raw.online_sales (
    customerid           TEXT,
    transaction_id       TEXT,
    transaction_date     TEXT,   -- raw is text (e.g., 1/13/2019)
    product_sku          TEXT,
    product_description  TEXT,
    product_category     TEXT,
    quantity             INTEGER,
    avg_price            NUMERIC,
    delivery_charges     NUMERIC,
    coupon_status        TEXT
);

------------ customer_data ------------
DROP TABLE IF EXISTS raw.customer_data;
CREATE TABLE raw.customer_data (
    customerid      TEXT,
    gender          TEXT,
    location        TEXT,
    tenure_months   INTEGER
);

------------ discount_coupon ------------
DROP TABLE IF EXISTS raw.discount_coupon;
CREATE TABLE raw.discount_coupon (
    month            TEXT,
    product_category TEXT,
    coupon_code      TEXT,
    discount_pct     NUMERIC
);

------------ tax_amount ------------
DROP TABLE IF EXISTS raw.tax_amount;
CREATE TABLE raw.tax_amount (
    product_category TEXT,
    gst              TEXT  -- raw is text (e.g., 10%, 18%)
);

------------ marketing_spend ------------
DROP TABLE IF EXISTS raw.marketing_spend;
CREATE TABLE raw.marketing_spend (
    date           TEXT,   -- raw is text (e.g., 01/01/2019)
    offline_spend  NUMERIC,
    online_spend   NUMERIC
);
