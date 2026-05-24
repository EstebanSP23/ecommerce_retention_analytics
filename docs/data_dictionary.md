# Data Dictionary

This document describes every table and view in the pipeline, organized by layer.

---

## Raw Layer (`raw` schema)

Exact copy of the source CSVs from Kaggle. Dates are stored as TEXT to avoid DateStyle issues; parsing happens in the staging layer.

### `raw.online_sales`
Source: `data/online_sales.csv` — line-item transaction records.

| Column | Type | Notes |
|---|---|---|
| customerid | TEXT | Source customer identifier |
| transaction_id | TEXT | Source transaction identifier |
| transaction_date | TEXT | Format MM/DD/YYYY |
| product_sku | TEXT | Product identifier |
| product_description | TEXT | Free-text product description |
| product_category | TEXT | Product category label |
| quantity | INTEGER | Units sold |
| avg_price | NUMERIC | Average unit price |
| delivery_charges | NUMERIC | Per-line delivery cost |
| coupon_status | TEXT | `Used` / `Clicked` / `Not Used` (raw variants normalized in staging) |

### `raw.customer_data`
Source: `data/customer_data.csv` — customer attribute table.

| Column | Type | Notes |
|---|---|---|
| customerid | TEXT | Source customer identifier |
| gender | TEXT | `M` / `F` / variants |
| location | TEXT | Customer city/region |
| tenure_months | INTEGER | Customer tenure at observation time |

### `raw.discount_coupon`
Source: `data/discount_coupon.csv` — coupon catalog by month and category.

| Column | Type | Notes |
|---|---|---|
| month | TEXT | Three-letter month code (`JAN`, `FEB`, ...) |
| product_category | TEXT | Category the coupon applies to |
| coupon_code | TEXT | Coupon identifier |
| discount_pct | NUMERIC | Discount expressed as a percentage (e.g. `10` = 10%) |

### `raw.tax_amount`
Source: `data/tax_amount.csv` — GST rate per product category.

| Column | Type | Notes |
|---|---|---|
| product_category | TEXT | Category the GST applies to |
| gst | TEXT | GST as string with `%` (e.g. `10%`); normalized to a rate in staging |

### `raw.marketing_spend`
Source: `data/marketing_spend.csv` — daily marketing spend by channel.

| Column | Type | Notes |
|---|---|---|
| date | TEXT | Format MM/DD/YYYY |
| offline_spend | NUMERIC | Spend in offline channels for the day |
| online_spend | NUMERIC | Spend in online channels for the day |

---

## Staging Layer (`staging` schema)

Cleaned and typed versions of the raw tables. Adds: date parsing, text trimming, NULL-empty-string handling, GST/discount normalization, month-number standardization.

### `staging.stg_online_sales`
Same grain as raw with `customer_id`/`transaction_id` cleaned, `transaction_date` parsed to DATE, and `coupon_status` normalized to `Used` / `Clicked` / `Not Used`.

### `staging.stg_customer_data`
Customer attributes with `gender` cased consistently (`Initcap`) and types enforced.

### `staging.stg_discount_coupon`
Adds `month_num` (1–12) derived from the three-letter month code so the table joins cleanly to dated fact rows.

### `staging.stg_tax_amount`
Converts the textual `gst` (e.g. `10%`) into a numeric `gst_rate` in `[0, 1]`.

### `staging.stg_marketing_spend`
Renames `date` → `spend_date` and parses it to DATE.

---

## Mart Layer (`mart` schema) — Dimensions

Star-schema dimensions used as filter/grouping anchors in Power BI.

### `mart.dim_date`
One row per distinct transaction date. Columns: `date`, `year`, `month_num`, `month_name`, `year_month`, `month_start_date`.

### `mart.dim_customer`
One row per `customer_id`. Columns: `customer_id`, `gender`, `location`, `tenure_months`. Primary key: `customer_id`.

### `mart.dim_product`
One row per `product_sku`. Columns: `product_sku`, `product_description`, `product_category`. Primary key: `product_sku`.

---

## Mart Layer — Facts

### `mart.fact_sales_line`
**Grain:** 1 row = 1 product SKU within a transaction.
Primary key: `(transaction_id, product_sku)`.

| Column | Type | Notes |
|---|---|---|
| transaction_id | TEXT | Order identifier |
| product_sku | TEXT | Product identifier |
| customer_id | TEXT | Customer identifier (may differ across lines of the same order — see `fact_orders.is_customer_id_conflicted`) |
| transaction_date | DATE | Order date |
| quantity | INTEGER | Units sold on this line |
| avg_price | NUMERIC | Unit price |
| delivery_charges | NUMERIC | Per-line delivery cost |
| gst_rate | NUMERIC | Applied tax rate (from `dim_product`'s category) |
| discount_rate_applied | NUMERIC(10,4) | Effective discount on the line, in `[0, 1]` |
| invoice_value | NUMERIC(18,2) | `((quantity * avg_price) * (1 - discount_rate_applied) * (1 + gst_rate)) + delivery_charges` |

### `mart.fact_orders`
**Grain:** 1 row = 1 transaction_id (line-level fact rolled up).
Primary key: `transaction_id`.

| Column | Type | Notes |
|---|---|---|
| transaction_id | TEXT | Order identifier |
| customer_id | TEXT | Resolved via `MIN(customer_id)` when multiple customer_ids exist for one transaction |
| transaction_date | DATE | Order date |
| order_revenue | NUMERIC(18,2) | `ROUND(SUM(invoice_value), 2)` over the line-level fact |
| items_qty | INTEGER | `SUM(quantity)` |
| distinct_skus | INTEGER | `COUNT(DISTINCT product_sku)` |
| customer_variants | INTEGER | Number of distinct customer_ids that appeared for this transaction in raw data |
| is_customer_id_conflicted | BOOLEAN | `TRUE` when `customer_variants > 1`; behavioral KPIs exclude these rows |

### `mart.fact_marketing_daily`
**Grain:** 1 row = 1 day per channel (`Online` / `Offline`). Long-format unpivot of the raw daily spend.
Primary key: `(spend_date, channel)`.

| Column | Type | Notes |
|---|---|---|
| spend_date | DATE | Day of spend |
| channel | TEXT | `Online` or `Offline` |
| spend | NUMERIC(18,2) | Daily spend amount in the channel |

---

## KPI Views (`mart` schema)

Business-facing views built on top of the mart tables. All KPI logic lives in SQL so Power BI consumes pre-computed metrics.

| View | Purpose |
|---|---|
| `mart.vw_exec_kpis` | Headline executive KPIs (revenue, orders, customers, AOV). |
| `mart.vw_monthly_revenue_new_vs_existing` | Monthly revenue split between newly-acquired and returning customers. |
| `mart.vw_cohort_retention` | Cohort customer counts retained at each month-since-signup. |
| `mart.vw_cohort_retention_rates` | The above expressed as retention rates (% of cohort base). |
| `mart.vw_month1_retention_trend` | Month-1 retention rate over time (acquisition-month trend). |
| `mart.vw_month1_retention_summary` | Month-1 retention averaged across First-Half vs Second-Half cohorts of the year. |
| `mart.vw_monthly_marketing_efficiency` | Monthly ROAS: revenue ÷ marketing spend. |
| `mart.vw_marketing_summary` | Aggregate marketing-spend totals and overall efficiency. |
| `mart.vw_customer_lifetime_stats` | Per-customer lifetime aggregates (orders, revenue). |
| `mart.vw_customer_order_buckets` | Customers grouped into order-frequency buckets with share of customers and share of revenue per bucket. |
| `mart.vw_customer_repeat_summary` | Customer counts and % split between one-time vs repeat buyers. |
| `mart.vw_repeat_revenue_split` | Revenue split between one-time and repeat buyers. |
| `mart.vw_repeat_revenue_summary` | Single-row: share of total revenue coming from repeat buyers. |
| `mart.vw_customer_avg_orders` | Single-row: average orders per customer across the dataset. |
