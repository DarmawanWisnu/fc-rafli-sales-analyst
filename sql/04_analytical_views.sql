-- ============================================================
-- 04_analytical_views.sql
-- Retail Sales & Demand Analytics - PostgreSQL Portfolio
-- Purpose: Reusable analytics views for BI/forecasting
-- ============================================================

-- =============================================
-- Phase 6: Reconciliation & Control Totals
-- =============================================

-- 6.1 Reconciliation summary
WITH detail_totals AS (
    SELECT transaction_id, SUM(subtotal) AS detail_revenue
    FROM staging.transaction_details
    GROUP BY transaction_id
), recon AS (
    SELECT
        t.transaction_id,
        t.final_amount,
        COALESCE(d.detail_revenue,0) AS detail_revenue,
        t.final_amount - COALESCE(d.detail_revenue,0) AS diff
    FROM staging.transactions t
    LEFT JOIN detail_totals d USING (transaction_id)
)
SELECT
    COUNT(*) AS transaction_count,
    COUNT(*) FILTER (WHERE diff = 0) AS reconciled_transactions,
    COUNT(*) FILTER (WHERE diff <> 0) AS failed_transactions,
    SUM(ABS(diff)) AS total_absolute_difference
FROM recon;

-- 6.2 Core order KPIs
SELECT
    SUM(final_amount)                                AS total_revenue,
    COUNT(DISTINCT transaction_id)                   AS total_orders,
    SUM(final_amount) / COUNT(DISTINCT transaction_id) AS average_order_value,
    MAX(final_amount)                                AS maximum_order_value,
    MIN(final_amount)                                AS minimum_order_value,
    SUM(discount)                                    AS total_transaction_discount
FROM staging.transactions;

-- 6.3 Max and min transaction lookup
SELECT transaction_id, date, time, payment_method, final_amount
FROM staging.transactions
WHERE final_amount = (SELECT MAX(final_amount) FROM staging.transactions);

SELECT transaction_id, date, time, payment_method, final_amount
FROM staging.transactions
WHERE final_amount = (SELECT MIN(final_amount) FROM staging.transactions);

-- 6.4 Product-line controls
SELECT
    SUM(d.quantity)                                         AS total_quantity,
    SUM(d.subtotal)                                        AS product_revenue,
    SUM(d.quantity * d.unit_cost)                           AS line_cost,
    SUM(d.subtotal - d.quantity * d.unit_cost)              AS gross_profit,
    SUM(d.subtotal - d.quantity * d.unit_cost)
        / NULLIF(SUM(d.subtotal),0)                        AS gross_margin_pct
FROM staging.transaction_details d;

-- =============================================
-- Phase 7: Analytical Views
-- =============================================

-- 7.1 vw_transaction_base (grain: 1 transaction)
CREATE OR REPLACE VIEW analytics.vw_transaction_base AS
SELECT
    transaction_id,
    date,
    time,
    EXTRACT(HOUR FROM time)::integer       AS hour,
    payment_method,
    total_amount,
    discount,
    final_amount,
    DATE_TRUNC('month', date)::date        AS month_start,
    TO_CHAR(date, 'YYYY-MM')              AS year_month,
    EXTRACT(ISODOW FROM date)::integer     AS iso_weekday,
    TO_CHAR(date, 'FMDay')                AS day_of_week
FROM staging.transactions;

-- 7.2 vw_sales_line_base (grain: 1 detail line)
CREATE OR REPLACE VIEW analytics.vw_sales_line_base AS
SELECT
    d.transaction_line_id,
    d.transaction_id,
    t.date,
    t.time,
    EXTRACT(HOUR FROM t.time)::integer     AS hour,
    t.payment_method,
    d.product_id,
    p.product_name,
    p.category,
    p.type,
    p.unit,
    d.quantity,
    d.unit_price,
    d.unit_cost,
    d.discount                             AS line_discount,
    d.subtotal,
    d.quantity * d.unit_cost               AS line_cost,
    d.subtotal - d.quantity * d.unit_cost  AS gross_profit,
    CASE WHEN d.subtotal = 0 THEN NULL
         ELSE (d.subtotal - d.quantity * d.unit_cost) / d.subtotal
    END                                    AS gross_margin_pct,
    DATE_TRUNC('month', t.date)::date      AS month_start,
    TO_CHAR(t.date,'YYYY-MM')             AS year_month
FROM staging.transaction_details d
JOIN staging.transactions t USING (transaction_id)
JOIN staging.products p USING (product_id);

-- 7.3 vw_daily_kpi (grain: 1 calendar date, with date spine)
CREATE OR REPLACE VIEW analytics.vw_daily_kpi AS
WITH bounds AS (
    SELECT MIN(date) AS min_date, MAX(date) AS max_date
    FROM staging.transactions
), calendar AS (
    SELECT GENERATE_SERIES(min_date, max_date, INTERVAL '1 day')::date AS date
    FROM bounds
), daily AS (
    SELECT
        date,
        COUNT(*)           AS order_count,
        SUM(final_amount)  AS revenue,
        SUM(discount)      AS total_discount
    FROM staging.transactions
    GROUP BY date
)
SELECT
    c.date,
    COALESCE(d.order_count,0)::bigint               AS order_count,
    COALESCE(d.revenue,0)::numeric(14,2)            AS revenue,
    CASE WHEN COALESCE(d.order_count,0)=0 THEN 0::numeric
         ELSE d.revenue / d.order_count
    END                                              AS average_order_value,
    COALESCE(d.total_discount,0)::numeric(14,2)     AS total_discount,
    EXTRACT(ISODOW FROM c.date)::integer             AS iso_weekday,
    TO_CHAR(c.date,'FMDay')                         AS day_of_week,
    DATE_TRUNC('month',c.date)::date                AS month_start,
    (COALESCE(d.order_count,0)=0)                   AS is_zero_sales_day
FROM calendar c
LEFT JOIN daily d USING (date)
ORDER BY c.date;

-- 7.4 vw_monthly_product_performance (grain: 1 month x product)
CREATE OR REPLACE VIEW analytics.vw_monthly_product_performance AS
WITH agg AS (
    SELECT
        month_start,
        product_id,
        product_name,
        category,
        SUM(quantity)      AS quantity_sold,
        SUM(subtotal)      AS product_revenue,
        SUM(line_cost)     AS line_cost,
        SUM(gross_profit)  AS gross_profit
    FROM analytics.vw_sales_line_base
    GROUP BY month_start, product_id, product_name, category
)
SELECT
    *,
    CASE WHEN product_revenue=0 THEN NULL
         ELSE gross_profit/product_revenue END  AS gross_margin_pct,
    DENSE_RANK() OVER (
        PARTITION BY month_start ORDER BY product_revenue DESC
    ) AS revenue_rank_month,
    DENSE_RANK() OVER (
        PARTITION BY month_start ORDER BY quantity_sold DESC
    ) AS quantity_rank_month
FROM agg;

-- =============================================
-- 7.5 Validate all views
-- =============================================
SELECT COUNT(*) AS vw_transaction_base_rows FROM analytics.vw_transaction_base;
SELECT COUNT(*) AS vw_sales_line_base_rows FROM analytics.vw_sales_line_base;
SELECT COUNT(*) AS vw_daily_kpi_rows FROM analytics.vw_daily_kpi;

SELECT
    SUM(final_amount) AS transaction_view_revenue
FROM analytics.vw_transaction_base;

SELECT
    SUM(subtotal) AS sales_line_view_revenue,
    SUM(gross_profit) AS gross_profit
FROM analytics.vw_sales_line_base;

SELECT COUNT(*) AS zero_sales_days
FROM analytics.vw_daily_kpi
WHERE is_zero_sales_day;
