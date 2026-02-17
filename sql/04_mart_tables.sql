-- ============================================================
-- 04_mart_tables.sql
-- Purpose: Create star schema tables (MVP dimensional model)
-- ============================================================

-- ---------- dim_date ----------
DROP TABLE IF EXISTS mart.dim_date;

CREATE TABLE mart.dim_date AS
SELECT DISTINCT
    transaction_date                              AS date,
    EXTRACT(YEAR FROM transaction_date)::INT      AS year,
    EXTRACT(MONTH FROM transaction_date)::INT     AS month_num,
    TO_CHAR(transaction_date, 'Mon')              AS month_name,
    TO_CHAR(transaction_date, 'YYYY-MM')          AS year_month,
    DATE_TRUNC('month', transaction_date)::DATE   AS month_start_date
FROM staging.stg_online_sales
ORDER BY date;

-- ---------- dim_customer ----------
DROP TABLE IF EXISTS mart.dim_customer;

CREATE TABLE mart.dim_customer AS
SELECT
    customer_id,
    gender,
    location,
    tenure_months
FROM staging.stg_customers_data;

-- Optional: enforce uniqueness at the model level
-- (useful recruiter signal, low effort)
ALTER TABLE mart.dim_customer
ADD CONSTRAINT pk_dim_customer PRIMARY KEY (customer_id);

-- ---------- dim_product ----------
DROP TABLE IF EXISTS mart.dim_product;

CREATE TABLE mart.dim_product AS
SELECT DISTINCT
    product_sku,
    product_description,
    product_category
FROM staging.stg_online_sales
WHERE product_sku IS NOT NULL;

ALTER TABLE mart.dim_product
ADD CONSTRAINT pk_dim_product PRIMARY KEY (product_sku);

-- ---------- fact_sales_line ----------
DROP TABLE IF EXISTS mart.fact_sales_line;

CREATE TABLE mart.fact_sales_line AS
WITH base AS (
    SELECT
        s.transaction_id,
        s.product_sku,
        s.customer_id,
        s.transaction_date,
        s.product_category,
        s.quantity,
        s.avg_price,
        s.delivery_charges,
        s.coupon_status,
        EXTRACT(MONTH FROM s.transaction_date)::INT AS month_num
    FROM staging.stg_online_sales s
)
SELECT
    b.transaction_id,
    b.product_sku,
    b.customer_id,
    b.transaction_date,

    b.quantity,
    b.avg_price,
    b.delivery_charges,

    t.gst_rate,

    CASE
        WHEN b.coupon_status IN ('Used', 'Clicked')
            THEN (COALESCE(dc.discount_pct, 0) / 100)::numeric(10,4)
        ELSE 0::numeric(10,4)
    END AS discount_rate_applied,

    ROUND(
        (
            (b.quantity * b.avg_price)
            * (1 - CASE
                    WHEN b.coupon_status IN ('Used', 'Clicked')
                        THEN COALESCE(dc.discount_pct, 0) / 100
                    ELSE 0
                  END)
            * (1 + COALESCE(t.gst_rate, 0))
        ) + COALESCE(b.delivery_charges, 0),
        2
    )::numeric(18,2) AS invoice_value

FROM base b
LEFT JOIN staging.stg_tax_amount t
    ON t.product_category = b.product_category
LEFT JOIN staging.stg_discount_coupon dc
    ON dc.product_category = b.product_category
   AND dc.month_num = b.month_num;

ALTER TABLE mart.fact_sales_line
ADD CONSTRAINT pk_fact_sales_line
PRIMARY KEY (transaction_id, product_sku);



-- ---------- fact_orders ----------
DROP TABLE IF EXISTS mart.fact_orders CASCADE;

CREATE TABLE mart.fact_orders AS
SELECT
    transaction_id,

    MIN(customer_id) AS customer_id,
    MIN(transaction_date) AS transaction_date,

    ROUND(SUM(invoice_value), 2)::numeric(18,2) AS order_revenue,
    SUM(quantity) AS items_qty,
    COUNT(DISTINCT product_sku) AS distinct_skus,

    COUNT(DISTINCT customer_id) AS customer_variants,
    CASE
        WHEN COUNT(DISTINCT customer_id) > 1 THEN TRUE
        ELSE FALSE
    END AS is_customer_id_conflicted

FROM mart.fact_sales_line
GROUP BY transaction_id;

ALTER TABLE mart.fact_orders
ADD CONSTRAINT pk_fact_orders
PRIMARY KEY (transaction_id);
