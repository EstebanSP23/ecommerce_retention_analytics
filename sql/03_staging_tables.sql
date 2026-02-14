-- ============================================================
-- 03_staging_tables.sql
-- Purpose: Build cleaned/typed staging tables from raw layer
-- ============================================================

------------ stg_online_sales ------------
DROP TABLE IF EXISTS staging.stg_online_sales;

CREATE TABLE staging.stg_online_sales AS
SELECT
    NULLIF(TRIM(customerid), '')      AS customer_id,
    NULLIF(TRIM(transaction_id), '')  AS transaction_id,

    -- Parse MM/DD/YYYY into DATE
    CASE
        WHEN transaction_date ~ '^\d{1,2}/\d{1,2}/\d{4}$'
            THEN TO_DATE(transaction_date, 'MM/DD/YYYY')
        ELSE NULL
    END                               AS transaction_date,

    NULLIF(TRIM(product_sku), '')         AS product_sku,
    NULLIF(TRIM(product_description), '') AS product_description,
    NULLIF(TRIM(product_category), '')    AS product_category,

    quantity           AS quantity,
    avg_price          AS avg_price,
    delivery_charges   AS delivery_charges,

    -- Normalize coupon_status
    CASE
        WHEN coupon_status IS NULL THEN NULL
        WHEN LOWER(TRIM(coupon_status)) IN ('used', 'yes', 'y') THEN 'Used'
        WHEN LOWER(TRIM(coupon_status)) IN ('clicked')          THEN 'Clicked'
        WHEN LOWER(TRIM(coupon_status)) IN ('not used', 'no', 'n') THEN 'Not Used'
        ELSE TRIM(coupon_status)
    END                               AS coupon_status
FROM raw.online_sales;


------------ stg_customer_data ------------
DROP TABLE IF EXISTS staging.stg_customer_data;

CREATE TABLE staging.stg_customer_data AS
SELECT
    NULLIF(TRIM(customerid), '') AS customer_id,

    CASE
        WHEN gender IS NULL THEN NULL
        ELSE INITCAP(TRIM(gender))
    END AS gender,

    NULLIF(TRIM(location), '') AS location,

    tenure_months::INTEGER AS tenure_months
FROM raw.customer_data;


------------ stg_discount_coupon ------------
DROP TABLE IF EXISTS staging.stg_discount_coupon;

CREATE TABLE staging.stg_discount_coupon AS
SELECT
    NULLIF(TRIM(month), '')            AS month_name,
    NULLIF(TRIM(product_category), '') AS product_category,
    NULLIF(TRIM(coupon_code), '')      AS coupon_code,
    discount_pct::numeric              AS discount_pct
FROM raw.discount_coupon;


------------ stg_tax_amount ------------
DROP TABLE IF EXISTS staging.stg_tax_amount;

CREATE TABLE staging.stg_tax_amount AS
SELECT
    NULLIF(TRIM(product_category), '')        AS product_category,
    (REPLACE(TRIM(gst), '%', '')::numeric) / 100 AS gst_rate
FROM raw.tax_amount;


------------ stg_marketing_spend ------------
DROP TABLE IF EXISTS staging.stg_marketing_spend;

CREATE TABLE staging.stg_marketing_spend AS
SELECT
    CASE
        WHEN "date" ~ '^\d{1,2}/\d{1,2}/\d{4}$'
            THEN TO_DATE("date", 'MM/DD/YYYY')
        ELSE NULL
    END AS spend_date,
    offline_spend::numeric AS offline_spend,
    online_spend::numeric  AS online_spend
FROM raw.marketing_spend;

