-- ============================================================
-- 05_business_analysis.sql
-- Retail Sales & Demand Analytics - PostgreSQL Portfolio
-- Purpose: Basic / Intermediate / Advanced business queries
-- ============================================================

-- =============================================
-- PHASE 8: BASIC SQL
-- =============================================

-- 8.1 SELECT + ORDER BY - Top 10 highest orders
SELECT transaction_id, date, time, payment_method, final_amount
FROM analytics.vw_transaction_base
ORDER BY final_amount DESC, transaction_id
LIMIT 10;

-- 8.2 WHERE - filter one month (January 2026)
SELECT *
FROM analytics.vw_transaction_base
WHERE date >= DATE '2026-01-01'
  AND date < DATE '2026-02-01'
ORDER BY date, time;

-- 8.3 Core order KPI query
SELECT
    SUM(final_amount)                                AS total_revenue,
    COUNT(DISTINCT transaction_id)                   AS total_orders,
    SUM(final_amount) / COUNT(DISTINCT transaction_id) AS average_order_value,
    MAX(final_amount)                                AS maximum_order_value,
    MIN(final_amount)                                AS minimum_order_value
FROM analytics.vw_transaction_base;

-- 8.4 GROUP BY - payment-method performance
SELECT
    payment_method,
    COUNT(*) AS order_count,
    SUM(final_amount) AS revenue,
    SUM(final_amount) / COUNT(*) AS average_order_value,
    SUM(final_amount) / SUM(SUM(final_amount)) OVER () AS revenue_share_pct
FROM analytics.vw_transaction_base
GROUP BY payment_method
ORDER BY revenue DESC;

-- 8.5 GROUP BY product/category - quantity sold
SELECT
    category,
    SUM(quantity) AS quantity_sold
FROM analytics.vw_sales_line_base
GROUP BY category
ORDER BY quantity_sold DESC;

-- 8.6 HAVING - categories above Rp500,000 revenue
SELECT
    category,
    SUM(subtotal) AS category_revenue
FROM analytics.vw_sales_line_base
GROUP BY category
HAVING SUM(subtotal) >= 500000
ORDER BY category_revenue DESC;

-- 8.7 CASE - label order value bands
SELECT
    CASE
        WHEN final_amount < 5000  THEN 'Low <5k'
        WHEN final_amount < 15000 THEN 'Medium 5k-<15k'
        ELSE 'High >=15k'
    END AS order_value_band,
    COUNT(*) AS orders,
    SUM(final_amount) AS revenue
FROM analytics.vw_transaction_base
GROUP BY 1
ORDER BY revenue DESC;

-- =============================================
-- PHASE 9: INTERMEDIATE SQL
-- =============================================

-- 9.1 Monthly revenue, orders, AOV
SELECT
    month_start,
    SUM(final_amount) AS revenue,
    COUNT(*) AS orders,
    SUM(final_amount) / COUNT(*) AS aov
FROM analytics.vw_transaction_base
GROUP BY month_start
ORDER BY month_start;

-- 9.2 Product revenue + quantity + gross profit
SELECT
    product_id,
    product_name,
    category,
    SUM(quantity) AS quantity_sold,
    SUM(subtotal) AS revenue,
    SUM(line_cost) AS line_cost,
    SUM(gross_profit) AS gross_profit,
    SUM(gross_profit) / NULLIF(SUM(subtotal),0) AS gross_margin_pct
FROM analytics.vw_sales_line_base
GROUP BY product_id, product_name, category
ORDER BY revenue DESC;

-- 9.3 Category revenue vs gross profit
SELECT
    category,
    SUM(quantity) AS quantity_sold,
    SUM(subtotal) AS revenue,
    SUM(gross_profit) AS gross_profit,
    SUM(gross_profit) / NULLIF(SUM(subtotal),0) AS gross_margin_pct
FROM analytics.vw_sales_line_base
GROUP BY category
ORDER BY revenue DESC;

-- 9.4 Service vs Product profitability
SELECT
    type,
    SUM(quantity) AS quantity_sold,
    SUM(subtotal) AS revenue,
    SUM(gross_profit) AS gross_profit,
    SUM(gross_profit) / NULLIF(SUM(subtotal),0) AS gross_margin_pct
FROM analytics.vw_sales_line_base
GROUP BY type
ORDER BY revenue DESC;

-- 9.5 Hourly demand
SELECT
    hour,
    COUNT(*) AS orders,
    SUM(final_amount) AS revenue,
    SUM(final_amount) / COUNT(*) AS aov
FROM analytics.vw_transaction_base
GROUP BY hour
ORDER BY hour;

-- 9.6 Day-of-week demand
SELECT
    iso_weekday,
    day_of_week,
    COUNT(*) AS orders,
    SUM(final_amount) AS revenue
FROM analytics.vw_transaction_base
GROUP BY iso_weekday, day_of_week
ORDER BY iso_weekday;

-- 9.7 Zero-sales days from the complete calendar
SELECT date, order_count, revenue
FROM analytics.vw_daily_kpi
WHERE is_zero_sales_day
ORDER BY date;

-- =============================================
-- PHASE 10: ADVANCED SQL
-- =============================================

-- 10.1 Month-over-month revenue change with LAG
WITH monthly AS (
    SELECT
        month_start,
        SUM(final_amount) AS revenue,
        COUNT(*) AS orders
    FROM analytics.vw_transaction_base
    GROUP BY month_start
), x AS (
    SELECT
        *,
        LAG(revenue) OVER (ORDER BY month_start) AS previous_month_revenue
    FROM monthly
)
SELECT
    month_start,
    revenue,
    orders,
    previous_month_revenue,
    revenue - previous_month_revenue AS mom_change,
    (revenue - previous_month_revenue)
        / NULLIF(previous_month_revenue,0) AS mom_change_pct
FROM x
ORDER BY month_start;

-- 10.2 Monthly top product by revenue (DENSE_RANK)
SELECT
    month_start,
    product_id,
    product_name,
    category,
    product_revenue,
    revenue_rank_month
FROM analytics.vw_monthly_product_performance
WHERE revenue_rank_month = 1
ORDER BY month_start, product_id;

-- 10.3 Monthly top product by quantity
SELECT
    month_start,
    product_id,
    product_name,
    category,
    quantity_sold,
    quantity_rank_month
FROM analytics.vw_monthly_product_performance
WHERE quantity_rank_month = 1
ORDER BY month_start, product_id;

-- 10.4 Overall product revenue contribution
WITH product AS (
    SELECT
        product_id,
        product_name,
        SUM(subtotal) AS revenue
    FROM analytics.vw_sales_line_base
    GROUP BY product_id, product_name
)
SELECT
    product_id,
    product_name,
    revenue,
    revenue / SUM(revenue) OVER () AS revenue_contribution_pct
FROM product
ORDER BY revenue DESC;

-- 10.5 Pareto / cumulative product revenue contribution
WITH product AS (
    SELECT
        product_id,
        product_name,
        SUM(subtotal) AS revenue
    FROM analytics.vw_sales_line_base
    GROUP BY product_id, product_name
), ranked AS (
    SELECT
        *,
        SUM(revenue) OVER (
            ORDER BY revenue DESC, product_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / SUM(revenue) OVER () AS cumulative_revenue_pct
    FROM product
)
SELECT *
FROM ranked
ORDER BY revenue DESC, product_id;

-- 10.6 Rolling 7-day revenue and orders
SELECT
    date,
    order_count,
    revenue,
    SUM(order_count) OVER (
        ORDER BY date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS rolling_7d_orders,
    SUM(revenue) OVER (
        ORDER BY date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS rolling_7d_revenue,
    AVG(revenue) OVER (
        ORDER BY date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS rolling_7d_avg_revenue
FROM analytics.vw_daily_kpi
ORDER BY date;

-- =============================================
-- PHASE 11: TOP 3 BUSINESS PROBLEMS
-- =============================================

-- Problem 1: Revenue volatility and January concentration
WITH monthly AS (
    SELECT month_start, SUM(revenue) AS revenue
    FROM analytics.vw_daily_kpi
    GROUP BY month_start
)
SELECT
    month_start,
    revenue,
    revenue / SUM(revenue) OVER () AS share_of_period_revenue
FROM monthly
ORDER BY month_start;

-- Problem 2: Revenue and profit tell different stories (Service vs Product)
SELECT
    type,
    SUM(subtotal) AS revenue,
    SUM(gross_profit) AS gross_profit,
    SUM(gross_profit) / SUM(subtotal) AS gross_margin_pct,
    SUM(subtotal) / SUM(SUM(subtotal)) OVER () AS revenue_share,
    SUM(gross_profit) / SUM(SUM(gross_profit)) OVER () AS gross_profit_share
FROM analytics.vw_sales_line_base
GROUP BY type
ORDER BY revenue DESC;

-- Problem 3: Demand is concentrated in narrow operating windows
WITH hourly AS (
    SELECT hour, COUNT(*) AS orders, SUM(final_amount) AS revenue
    FROM analytics.vw_transaction_base
    GROUP BY hour
)
SELECT
    SUM(orders) FILTER (WHERE hour IN (7,8,9,16,17)) AS peak_window_orders,
    SUM(orders) AS total_orders,
    SUM(orders) FILTER (WHERE hour IN (7,8,9,16,17))::numeric / SUM(orders) AS peak_order_share,
    SUM(revenue) FILTER (WHERE hour IN (7,8,9,16,17)) AS peak_window_revenue,
    SUM(revenue) FILTER (WHERE hour IN (7,8,9,16,17)) / SUM(revenue) AS peak_revenue_share
FROM hourly;
