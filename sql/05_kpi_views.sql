-- ============================================================
-- 05_kpi_views.sql
-- Purpose: Business-facing KPI views built on mart tables
-- ============================================================

-- ---------- Monthly revenue + new vs existing customers ----------
CREATE OR REPLACE VIEW mart.vw_monthly_revenue_new_vs_existing AS
WITH first_purchase AS (
    SELECT
        customer_id,
        MIN(transaction_date) AS first_purchase_date
    FROM mart.fact_orders
    WHERE is_customer_id_conflicted = FALSE
    GROUP BY customer_id
),
orders_enriched AS (
    SELECT
        o.transaction_id,
        o.customer_id,
        o.transaction_date,
        o.order_revenue,
        DATE_TRUNC('month', o.transaction_date)::date AS month_start_date,
        TO_CHAR(o.transaction_date, 'YYYY-MM') AS year_month,
        CASE
            WHEN DATE_TRUNC('month', o.transaction_date) = DATE_TRUNC('month', fp.first_purchase_date)
                THEN 'New'
            ELSE 'Existing'
        END AS customer_type
    FROM mart.fact_orders o
    JOIN first_purchase fp
        ON fp.customer_id = o.customer_id
    WHERE o.is_customer_id_conflicted = FALSE
)
SELECT
    month_start_date,
    year_month,
    customer_type,
    COUNT(DISTINCT customer_id)    AS customers,
    COUNT(DISTINCT transaction_id) AS orders,
    ROUND(SUM(order_revenue), 2) AS revenue,
    ROUND(AVG(order_revenue), 2) AS avg_order_value
FROM orders_enriched
GROUP BY month_start_date, year_month, customer_type
ORDER BY month_start_date, customer_type;

-- ---------- Cohort retention (customer-based) ----------
CREATE OR REPLACE VIEW mart.vw_cohort_retention AS
WITH first_purchase AS (
    SELECT
        customer_id,
        DATE_TRUNC('month', MIN(transaction_date))::date AS cohort_month
    FROM mart.fact_orders
    WHERE is_customer_id_conflicted = FALSE
    GROUP BY customer_id
),
orders_by_month AS (
    SELECT
        o.customer_id,
        DATE_TRUNC('month', o.transaction_date)::date AS activity_month
    FROM mart.fact_orders o
    WHERE o.is_customer_id_conflicted = FALSE
    GROUP BY o.customer_id, DATE_TRUNC('month', o.transaction_date)::date
),
cohort_activity AS (
    SELECT
        fp.customer_id,
        fp.cohort_month,
        obm.activity_month,
        (
            (EXTRACT(YEAR FROM obm.activity_month) - EXTRACT(YEAR FROM fp.cohort_month)) * 12
          + (EXTRACT(MONTH FROM obm.activity_month) - EXTRACT(MONTH FROM fp.cohort_month))
        )::int AS month_index
    FROM first_purchase fp
    JOIN orders_by_month obm
      ON obm.customer_id = fp.customer_id
)
SELECT
    cohort_month,
    month_index,
    COUNT(DISTINCT customer_id) AS active_customers
FROM cohort_activity
GROUP BY cohort_month, month_index
ORDER BY cohort_month, month_index;

-- ---------- Cohort retention rates (0–6 months window) ----------
CREATE OR REPLACE VIEW mart.vw_cohort_retention_rates AS
WITH base AS (
    SELECT
        cohort_month,
        month_index,
        active_customers
    FROM mart.vw_cohort_retention
    WHERE month_index BETWEEN 0 AND 6
),
cohort_size AS (
    SELECT
        cohort_month,
        active_customers AS cohort_customers
    FROM base
    WHERE month_index = 0
)
SELECT
    b.cohort_month,
    b.month_index,
    b.active_customers,
    cs.cohort_customers,
    ROUND((b.active_customers::numeric / cs.cohort_customers) * 100, 2) AS retention_pct
FROM base b
JOIN cohort_size cs
  ON cs.cohort_month = b.cohort_month
ORDER BY b.cohort_month, b.month_index;

-- ---------- Execuitve KPIs ----------
CREATE OR REPLACE VIEW mart.vw_exec_kpis AS
SELECT
    COUNT(DISTINCT transaction_id) AS total_orders,
    COUNT(DISTINCT customer_id) AS unique_customers,
    ROUND(SUM(order_revenue), 2) AS total_revenue,
    ROUND(AVG(order_revenue), 2) AS avg_order_value
FROM mart.fact_orders
WHERE is_customer_id_conflicted = FALSE;

-- ---------- Retention Trend ----------
DROP VIEW IF EXISTS mart.vw_month1_retention_trend;

CREATE VIEW mart.vw_month1_retention_trend AS
SELECT
    cohort_month,
    TO_CHAR(cohort_month, 'Mon YYYY') AS cohort_month_label,
    retention_pct
FROM mart.vw_cohort_retention_rates
WHERE month_index = 1
ORDER BY cohort_month;


