-- ============================================================
-- 06_forecast_export.sql
-- Retail Sales & Demand Analytics - PostgreSQL Portfolio
-- Purpose: Daily time-series source, export checks, ANALYZE
-- ============================================================

-- =============================================
-- 12.2 Final database reconciliation before Power BI
-- =============================================
SELECT
    (SELECT SUM(final_amount) FROM analytics.vw_transaction_base) AS order_revenue,
    (SELECT SUM(subtotal) FROM analytics.vw_sales_line_base)      AS product_revenue,
    (SELECT SUM(gross_profit) FROM analytics.vw_sales_line_base)  AS gross_profit,
    (SELECT COUNT(*) FROM analytics.vw_transaction_base)          AS order_rows,
    (SELECT COUNT(*) FROM analytics.vw_sales_line_base)           AS line_rows,
    (SELECT COUNT(*) FROM analytics.vw_daily_kpi)                 AS calendar_rows;

-- =============================================
-- 12.3 Export the daily forecasting dataset
-- =============================================
SELECT
    date,
    order_count,
    revenue,
    average_order_value,
    total_discount,
    day_of_week,
    month_start,
    is_zero_sales_day
FROM analytics.vw_daily_kpi
ORDER BY date;

-- =============================================
-- 13.2 ANALYZE table statistics after load
-- =============================================
ANALYZE staging.products;
ANALYZE staging.transactions;
ANALYZE staging.transaction_details;

-- =============================================
-- 13.3 Optional EXPLAIN ANALYZE practice
-- =============================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    t.date,
    SUM(d.subtotal) AS revenue
FROM staging.transactions t
JOIN staging.transaction_details d USING (transaction_id)
WHERE t.date >= DATE '2026-01-01'
  AND t.date < DATE '2026-02-01'
GROUP BY t.date
ORDER BY t.date;
