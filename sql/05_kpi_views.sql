-- ============================================================
-- 05_kpi_views.sql
-- Purpose: Business-facing KPI views built on mart tables
-- ============================================================

-- ---------- Monthly revenue + new vs existing customers ----------
DROP VIEW IF EXISTS mart.vw_monthly_revenue_new_vs_existing;

CREATE VIEW mart.vw_monthly_revenue_new_vs_existing AS
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
        TO_CHAR(DATE_TRUNC('month', o.transaction_date)::date, 'Mon YYYY') AS month_label_en,
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
    month_label_en,
    year_month,
    customer_type,
    COUNT(DISTINCT customer_id)    AS customers,
    COUNT(DISTINCT transaction_id) AS orders,
    ROUND(SUM(order_revenue), 2)   AS revenue,
    ROUND(AVG(order_revenue), 2)   AS avg_order_value
FROM orders_enriched
GROUP BY month_start_date, month_label_en, year_month, customer_type
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

-- ---------- Monthly Marketing Efficiency ----------
CREATE OR REPLACE VIEW mart.vw_monthly_marketing_efficiency AS
WITH revenue_monthly AS (
    SELECT
        DATE_TRUNC('month', transaction_date)::date AS month_start_date,
        ROUND(SUM(order_revenue), 2)::numeric(18,2) AS revenue
    FROM mart.fact_orders
    WHERE is_customer_id_conflicted = FALSE
    GROUP BY 1
),
spend_monthly AS (
    SELECT
        DATE_TRUNC('month', spend_date)::date AS month_start_date,
        ROUND(SUM(spend), 2)::numeric(18,2) AS marketing_spend
    FROM mart.fact_marketing_daily
    GROUP BY 1
)
SELECT
    r.month_start_date,
    TO_CHAR(r.month_start_date, 'Mon YYYY') AS month_label_en,
    r.revenue,
    s.marketing_spend,
    ROUND(r.revenue / NULLIF(s.marketing_spend, 0), 2) AS roas
FROM revenue_monthly r
LEFT JOIN spend_monthly s
  ON s.month_start_date = r.month_start_date
ORDER BY r.month_start_date;

-- ---------- Monthly Marketing Summary ----------
CREATE OR REPLACE VIEW mart.vw_marketing_summary AS
SELECT
    ROUND(SUM(revenue), 2) AS total_revenue,
    ROUND(SUM(marketing_spend), 2) AS total_marketing_spend,
    ROUND(
        SUM(revenue) / NULLIF(SUM(marketing_spend), 0),
        2
    ) AS overall_roas
FROM mart.vw_monthly_marketing_efficiency;

-- ---------- Cohort Month 1 ----------
CREATE OR REPLACE VIEW mart.vw_cohort_month_1 AS
SELECT
    cohort_month,
    TO_CHAR(cohort_month, 'Mon YYYY') AS cohort_month_label,
    retention_pct
FROM mart.vw_cohort_retention_rates_1_to_6
WHERE month_index = 1
ORDER BY cohort_month;

-- ---------- Retention Summary Month 1 ----------
CREATE OR REPLACE VIEW mart.vw_month1_retention_summary AS
SELECT
    CASE
        WHEN cohort_month BETWEEN '2019-01-01' AND '2019-06-30'
            THEN 'First Half (Jan–Jun)'
        ELSE 'Second Half (Jul–Nov)'
    END AS period_group,
    ROUND(AVG(retention_pct), 2) AS avg_month1_retention
FROM mart.vw_cohort_month_1
GROUP BY period_group;
