# Customer Retention & Revenue Sustainability Analysis  
### Production-Style SQL Analytics Pipeline (PostgreSQL + Power BI)

---

## 1. Business Problem

E-commerce companies must balance **customer acquisition and retention** to achieve sustainable revenue growth.

While acquisition drives short-term revenue spikes, long-term profitability depends on:

- Customer retention
- Repeat purchase behavior
- Sustainable lifetime value
- Efficient marketing spend

This project analyzes customer behavior using a production-style SQL architecture to answer:

- How much revenue comes from new vs existing customers?
- How strong is month-over-month retention?
- How do cohorts behave over time?
- Are discounts contributing to sustainable revenue?
- Is marketing spend proportionate to revenue?

The objective is to simulate how analytics systems are built in real production environments — not just create dashboards.

---

## 2. Architecture Overview

The project follows a layered data architecture using PostgreSQL.

### Raw Layer (`raw` schema)
- Exact copy of source CSV/Excel files
- No transformations applied
- Full traceability to source data

### Staging Layer (`staging` schema)
- Data type normalization
- Date parsing (MM/DD/YYYY → DATE)
- Text cleaning and trimming
- GST percentage normalization
- Discount percentage normalization
- Month number standardization for joins

### Mart Layer (`mart` schema)
Dimensional star schema designed for analytical consumption.

#### Dimensions
- `dim_date`
- `dim_customer`
- `dim_product`

#### Fact Tables
- `fact_sales_line`
  - Grain: 1 row = 1 SKU within a transaction
  - Invoice value computed at line level
  - Explicit numeric precision (`numeric(18,2)`)

- `fact_orders`
  - Grain: 1 row = 1 transaction_id
  - Aggregated from line-level fact
  - Deterministic revenue rollups
  - Includes `is_customer_id_conflicted` flag for data integrity handling

- `fact_marketing_daily`
  - Grain: 1 row = 1 day per channel (Online/Offline)
  - Long-format marketing spend (`spend` + `channel`) for BI flexibility
  - Explicit numeric precision (`numeric(18,2)`)

### KPI Layer (SQL Views)
Business-facing views built on top of mart tables (KPI logic centralized in SQL to avoid duplication in Power BI):

- `vw_exec_kpis` *(operational executive KPIs)*
- `vw_monthly_revenue_new_vs_existing` *(includes `month_start_date` + English `month_label_en`)*
- `vw_cohort_retention`
- `vw_cohort_retention_rates` *(0–6 month window)*
- `vw_month1_retention_trend` *(English month label + proper sorting)*
- `vw_monthly_marketing_efficiency` *(monthly revenue vs spend + ROAS)*
- `vw_marketing_summary` *(overall ROAS = total revenue / total spend)*

---

## 3. Dataset Description

Source: Kaggle  
[Marketing Insights for E-Commerce Company](https://www.kaggle.com/datasets/rishikumarrajvansh/marketing-insights-for-e-commerce-company/data)

Transaction period:  
**2019-01-01 to 2019-12-31**

Dataset scale:

- 52,924 line items
- 25,061 distinct transactions
- 1,468 distinct customers
- 20 product categories
- 365 marketing spend records (daily online + offline)

---

## 4. Data Grain & Modeling Decisions

Primary fact table:

> 1 row = 1 product SKU within a transaction

Secondary aggregation:

> 1 row = 1 transaction_id

This ensures:

- No revenue double counting
- Product-level flexibility
- Correct order-level rollups
- Scalable dimensional modeling

Marketing spend modeling:

> 1 row = 1 day per channel (Online/Offline)

This ensures:

- Traceability to source daily spend
- Clean monthly rollups for ROAS and efficiency trending

---

## 5. Invoice Value Logic (Centralized in SQL)

Invoice value is calculated at the line-item level:

`Invoice Value = ((Quantity × Avg_Price) × (1 - Discount_pct) × (1 + GST)) + Delivery_Charges`

Business rules enforced:

- Discounts apply only when coupon status indicates usage.
- GST is applied at product category level.
- Numeric precision explicitly controlled (`numeric(18,2)`).
- Null-safe calculations ensure deterministic revenue.

Revenue totals reconciled after mart rebuild:

**Total Revenue: 4,877,837.47**

---

## 6. Data Quality Handling

During modeling, it was discovered that some `transaction_id` values mapped to multiple `customer_id`s in the raw data.

To preserve order-level grain:

- A deterministic rule was applied: `MIN(customer_id)`
- A flag `is_customer_id_conflicted` identifies affected transactions
- KPI views exclude conflicted transactions where necessary (especially customer-behavior metrics)

Conflict counts (transactions):

- `TRUE`: 1,319
- `FALSE`: 23,742

This mirrors real-world production issue handling (flagging, isolating, and controlling downstream impact).

---

## 7. Implemented KPI Views

### 1. Executive Operational KPIs
- Total Revenue
- Total Orders
- Unique Customers
- AOV  
All sourced from `vw_exec_kpis` and **exclude conflicted transactions**.

### 2. Monthly Revenue (New vs Existing)
- Customer classification based on first purchase month
- Revenue split by acquisition vs retention
- Order count and AOV included
- Uses `month_start_date` and an English month label for BI-friendly axes

### 3. Cohort Retention
- Cohort defined by first purchase month
- Retention measured as % of active customers
- Window capped at 6 months for comparability
- Month 1 retention trend view built for executive-level monitoring

### 4. Marketing Efficiency (ROAS)
- Daily spend modeled in mart (`fact_marketing_daily`)
- Monthly revenue vs spend with ROAS (`vw_monthly_marketing_efficiency`)
- Overall ROAS calculated correctly as **total revenue / total spend** (`vw_marketing_summary`)

---

## 8. Power BI Integration

Power BI connects directly to PostgreSQL (Import mode).

- No business logic reimplemented in DAX (KPI logic centralized in SQL)
- SQL views used for KPI consumption
- Star schema relationships maintained
- Numeric precision issues resolved at database layer
- Month label sorting handled using “Sort by Column” (label sorted by date)

This separation ensures:

- Maintainability
- Performance
- Architectural clarity
- Minimal BI-layer computation

---

## 9. Dashboard Design (MVP)

### Executive Summary Page (CEO-level)
- KPI Cards: Revenue, Orders, Customers, AOV (`vw_exec_kpis`)
- Revenue Trend: New vs Existing (2-line chart) (`vw_monthly_revenue_new_vs_existing`)
- Retention Health: Month 1 retention trend (`vw_month1_retention_trend`)

### Marketing Efficiency Page
- KPI Card: Overall ROAS (`vw_marketing_summary`)
- ROAS Trend (`vw_monthly_marketing_efficiency`)
- Revenue vs Marketing Spend (combo chart) (`vw_monthly_marketing_efficiency`)

---

## 10. Design Principles

This project emphasizes:

- Clear separation of layers
- Explicit grain declaration
- Deterministic revenue logic
- Centralized business rules in SQL
- Minimal BI over-computation
- Reproducibility
- Production-aware modeling

The goal is to demonstrate systems thinking, not just query writing.

---

## 11. Tools Used

- PostgreSQL 18
- pgAdmin 4
- Power BI Desktop (Import mode)
- GitHub

---

## 12. Project Status

✅ Raw ingestion completed  
✅ Staging layer implemented  
✅ Mart star schema implemented  
✅ Marketing mart fact implemented (`fact_marketing_daily`)  
✅ KPI views implemented (revenue, retention, marketing efficiency)  
✅ Power BI connected to PostgreSQL  
✅ MVP dashboard pages drafted (Executive Summary + Marketing Efficiency)  
🔄 Additional analytical pages in progress  

---

## 13. Future Enhancements

- Predictive CLV modeling
- Churn probability modeling
- Marketing attribution modeling
- Indexing & performance simulation
- Automated data validation checks

---

*Project by [EstebanSP23](https://github.com/EstebanSP23) – Building a production-ready data analytics portfolio*
