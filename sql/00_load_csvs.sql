-- ============================================================
-- 00_load_csvs.sql
-- Purpose:
--   Load source CSVs from the repo's /data folder into the raw
--   schema. Run AFTER 01_create_schemas.sql and 02_raw_tables.sql.
--
-- Two options below — pick the one that matches your workflow.
-- ============================================================


-- ============================================================
-- OPTION A — psql CLI (recommended)
-- ============================================================
-- \COPY is a psql client-side meta-command that reads files from
-- the machine running psql (not the server). Paths are relative
-- to the directory you launched psql from. Run psql from the repo
-- root and the relative paths below resolve correctly.
--
-- Example:
--   cd /path/to/ecommerce_retention_analytics
--   psql -U <user> -d ecommerce_retention_analytics -f sql/00_load_csvs.sql
--
-- This block does NOT work in pgAdmin's Query Tool — pgAdmin runs
-- standard SQL only, and \COPY has a leading backslash that the
-- SQL parser rejects. Use OPTION B if you're on pgAdmin.
-- ============================================================

\COPY raw.online_sales(customerid, transaction_id, transaction_date, product_sku, product_description, product_category, quantity, avg_price, delivery_charges, coupon_status) FROM 'data/online_sales.csv' WITH (FORMAT csv, HEADER true);

\COPY raw.customer_data(customerid, gender, location, tenure_months) FROM 'data/customer_data.csv' WITH (FORMAT csv, HEADER true);

\COPY raw.discount_coupon(month, product_category, coupon_code, discount_pct) FROM 'data/discount_coupon.csv' WITH (FORMAT csv, HEADER true);

\COPY raw.tax_amount(product_category, gst) FROM 'data/tax_amount.csv' WITH (FORMAT csv, HEADER true);

\COPY raw.marketing_spend(date, offline_spend, online_spend) FROM 'data/marketing_spend.csv' WITH (FORMAT csv, HEADER true);


-- ============================================================
-- OPTION B — pgAdmin Query Tool (or any standard SQL client)
-- ============================================================
-- The plain (server-side) COPY command is standard SQL and works
-- in pgAdmin, but it reads files from the SERVER's filesystem and
-- requires absolute paths.
--
-- To use this block:
--   1) Comment out OPTION A above (lines starting with \COPY).
--   2) Uncomment the COPY statements below.
--   3) Replace REPO_ABS_PATH with the absolute path to your local
--      checkout. On Windows, use forward slashes or doubled
--      backslashes (e.g. 'C:/Users/.../ecommerce_retention_analytics'
--      or 'C:\\Users\\...\\ecommerce_retention_analytics').
--   4) Make sure the postgres service user has read access to the
--      /data folder (usually fine on local installs).
-- ============================================================

-- COPY raw.online_sales(customerid, transaction_id, transaction_date, product_sku, product_description, product_category, quantity, avg_price, delivery_charges, coupon_status) FROM 'REPO_ABS_PATH/data/online_sales.csv' WITH (FORMAT csv, HEADER true);

-- COPY raw.customer_data(customerid, gender, location, tenure_months) FROM 'REPO_ABS_PATH/data/customer_data.csv' WITH (FORMAT csv, HEADER true);

-- COPY raw.discount_coupon(month, product_category, coupon_code, discount_pct) FROM 'REPO_ABS_PATH/data/discount_coupon.csv' WITH (FORMAT csv, HEADER true);

-- COPY raw.tax_amount(product_category, gst) FROM 'REPO_ABS_PATH/data/tax_amount.csv' WITH (FORMAT csv, HEADER true);

-- COPY raw.marketing_spend(date, offline_spend, online_spend) FROM 'REPO_ABS_PATH/data/marketing_spend.csv' WITH (FORMAT csv, HEADER true);


-- ============================================================
-- Sanity check (works in either tool)
-- ============================================================
SELECT 'raw.online_sales'    AS table_name, COUNT(*) AS row_count FROM raw.online_sales
UNION ALL SELECT 'raw.customer_data',    COUNT(*) FROM raw.customer_data
UNION ALL SELECT 'raw.discount_coupon',  COUNT(*) FROM raw.discount_coupon
UNION ALL SELECT 'raw.tax_amount',       COUNT(*) FROM raw.tax_amount
UNION ALL SELECT 'raw.marketing_spend',  COUNT(*) FROM raw.marketing_spend
ORDER BY table_name;
