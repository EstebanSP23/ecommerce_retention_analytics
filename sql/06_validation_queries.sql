-- ============================================================
-- 06_validation_queries.sql
-- Purpose:
--   PASS/FAIL reconciliation suite for the e-commerce analytics
--   pipeline. Each block returns a check_status column so the suite
--   can be re-run after any change to the data or logic.
--
-- Expected: every check returns 'PASS'.
-- ============================================================

-- ============================================================
-- (1) Row-count parity: raw -> staging
--   Every staging table must have the same row count as its raw
--   source. Any non-zero diff indicates loss or duplication during
--   the staging build.
-- ============================================================
WITH counts AS (
    SELECT 'online_sales'    AS table_name,
           (SELECT COUNT(*) FROM raw.online_sales)         AS raw_rows,
           (SELECT COUNT(*) FROM staging.stg_online_sales) AS staging_rows
    UNION ALL
    SELECT 'customer_data',
           (SELECT COUNT(*) FROM raw.customer_data),
           (SELECT COUNT(*) FROM staging.stg_customer_data)
    UNION ALL
    SELECT 'discount_coupon',
           (SELECT COUNT(*) FROM raw.discount_coupon),
           (SELECT COUNT(*) FROM staging.stg_discount_coupon)
    UNION ALL
    SELECT 'tax_amount',
           (SELECT COUNT(*) FROM raw.tax_amount),
           (SELECT COUNT(*) FROM staging.stg_tax_amount)
    UNION ALL
    SELECT 'marketing_spend',
           (SELECT COUNT(*) FROM raw.marketing_spend),
           (SELECT COUNT(*) FROM staging.stg_marketing_spend)
)
SELECT
    table_name,
    raw_rows,
    staging_rows,
    (staging_rows - raw_rows) AS diff,
    CASE WHEN staging_rows = raw_rows THEN 'PASS' ELSE 'FAIL' END AS check_status
FROM counts
ORDER BY table_name;

-- ============================================================
-- (2) Sales-line vs orders reconciliation
--   For every transaction_id, SUM(invoice_value) from
--   fact_sales_line must equal order_revenue from fact_orders.
--   This is the central financial reconciliation: the order grain
--   must roll up cleanly from the line grain.
-- ============================================================
WITH line_rollup AS (
    SELECT
        transaction_id,
        ROUND(SUM(invoice_value), 2)::numeric(18,2) AS line_revenue
    FROM mart.fact_sales_line
    GROUP BY transaction_id
),
comparison AS (
    SELECT
        o.transaction_id,
        o.order_revenue,
        l.line_revenue,
        (o.order_revenue - l.line_revenue) AS diff
    FROM mart.fact_orders o
    JOIN line_rollup     l ON l.transaction_id = o.transaction_id
)
SELECT
    COUNT(*)                                                AS total_transactions,
    SUM(CASE WHEN ABS(diff) >= 0.01 THEN 1 ELSE 0 END)       AS bad_transactions,
    MAX(ABS(diff))                                           AS max_abs_diff,
    CASE
        WHEN SUM(CASE WHEN ABS(diff) >= 0.01 THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END                                                      AS check_status
FROM comparison;

-- ============================================================
-- (3) Referential integrity on facts
--   Every foreign key in the fact tables must resolve to its
--   dimension. Orphan keys break Power BI slicers silently.
-- ============================================================
SELECT
    'fact_sales_line: product_sku missing in dim_product' AS check_name,
    COUNT(*)                                              AS orphan_rows,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END    AS check_status
FROM mart.fact_sales_line f
LEFT JOIN mart.dim_product d ON d.product_sku = f.product_sku
WHERE f.product_sku IS NOT NULL
  AND d.product_sku IS NULL

UNION ALL

SELECT 'fact_sales_line: transaction_date missing in dim_date',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM mart.fact_sales_line f
LEFT JOIN mart.dim_date d ON d.date = f.transaction_date
WHERE d.date IS NULL

UNION ALL

-- Note: conflicted transactions are excluded because fact_orders
-- collapses multiple customer_ids into MIN(customer_id) by design.
SELECT 'fact_orders: customer_id missing in dim_customer (non-conflicted)',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM mart.fact_orders o
LEFT JOIN mart.dim_customer d ON d.customer_id = o.customer_id
WHERE o.is_customer_id_conflicted = FALSE
  AND o.customer_id IS NOT NULL
  AND d.customer_id IS NULL

UNION ALL

SELECT 'fact_orders: transaction_date missing in dim_date',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM mart.fact_orders o
LEFT JOIN mart.dim_date d ON d.date = o.transaction_date
WHERE d.date IS NULL

UNION ALL

SELECT 'fact_marketing_daily: spend_date missing in dim_date',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM mart.fact_marketing_daily m
LEFT JOIN mart.dim_date d ON d.date = m.spend_date
WHERE d.date IS NULL;

-- ============================================================
-- (4) NULLs and primary-key uniqueness
--   Critical keys must be populated and composite primary keys
--   must be unique.
-- ============================================================
SELECT
    'fact_sales_line: NULL transaction_id'              AS check_name,
    COUNT(*)                                             AS bad_rows,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END   AS check_status
FROM mart.fact_sales_line
WHERE transaction_id IS NULL

UNION ALL

SELECT 'fact_sales_line: NULL product_sku',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM mart.fact_sales_line
WHERE product_sku IS NULL

UNION ALL

SELECT 'fact_sales_line: duplicate (transaction_id, product_sku)',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (
    SELECT transaction_id, product_sku, COUNT(*) c
    FROM mart.fact_sales_line
    GROUP BY transaction_id, product_sku
    HAVING COUNT(*) > 1
) dup

UNION ALL

SELECT 'fact_orders: duplicate transaction_id',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (
    SELECT transaction_id, COUNT(*) c
    FROM mart.fact_orders
    GROUP BY transaction_id
    HAVING COUNT(*) > 1
) dup

UNION ALL

SELECT 'fact_marketing_daily: duplicate (spend_date, channel)',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (
    SELECT spend_date, channel, COUNT(*) c
    FROM mart.fact_marketing_daily
    GROUP BY spend_date, channel
    HAVING COUNT(*) > 1
) dup

UNION ALL

SELECT 'dim_customer: duplicate customer_id',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (
    SELECT customer_id, COUNT(*) c
    FROM mart.dim_customer
    GROUP BY customer_id
    HAVING COUNT(*) > 1
) dup;

-- ============================================================
-- (5) Invoice-value and quantity sanity
--   Business invariants: no negative revenue, no zero/negative
--   quantities, no negative marketing spend.
-- ============================================================
SELECT
    'fact_sales_line: invoice_value < 0'                AS check_name,
    COUNT(*)                                             AS bad_rows,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END   AS check_status
FROM mart.fact_sales_line
WHERE invoice_value < 0

UNION ALL

SELECT 'fact_sales_line: quantity <= 0',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM mart.fact_sales_line
WHERE quantity IS NULL OR quantity <= 0

UNION ALL

SELECT 'fact_sales_line: avg_price < 0',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM mart.fact_sales_line
WHERE avg_price < 0

UNION ALL

SELECT 'fact_sales_line: discount_rate_applied outside [0, 1]',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM mart.fact_sales_line
WHERE discount_rate_applied IS NOT NULL
  AND (discount_rate_applied < 0 OR discount_rate_applied > 1)

UNION ALL

SELECT 'fact_orders: order_revenue < 0',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM mart.fact_orders
WHERE order_revenue < 0

UNION ALL

SELECT 'fact_marketing_daily: spend < 0',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM mart.fact_marketing_daily
WHERE spend < 0;

-- ============================================================
-- (6) Marketing-daily completeness
--   Every spend_date in fact_marketing_daily must have exactly
--   2 rows (one Online, one Offline) and channel must be one
--   of those two values.
-- ============================================================
SELECT
    'fact_marketing_daily: spend_date missing Online or Offline'  AS check_name,
    COUNT(*)                                                       AS bad_rows,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END             AS check_status
FROM (
    SELECT spend_date, COUNT(DISTINCT channel) AS distinct_channels
    FROM mart.fact_marketing_daily
    GROUP BY spend_date
    HAVING COUNT(DISTINCT channel) <> 2
) missing

UNION ALL

SELECT 'fact_marketing_daily: unknown channel value',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM mart.fact_marketing_daily
WHERE channel NOT IN ('Online', 'Offline');
