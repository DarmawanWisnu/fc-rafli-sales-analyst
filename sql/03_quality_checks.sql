-- ============================================================
-- 03_quality_checks.sql
-- Retail Sales & Demand Analytics - PostgreSQL Portfolio
-- Purpose: QA-01 to QA-15 + Reconciliation + One-Query Summary
-- ============================================================

-- =============================================
-- QA-01: Product ID unique and non-null
-- =============================================
SELECT COUNT(*) AS invalid_rows
FROM staging.products
WHERE product_id IS NULL;

SELECT product_id, COUNT(*) AS row_count
FROM staging.products
GROUP BY product_id
HAVING COUNT(*) > 1;

-- =============================================
-- QA-02: Transaction ID unique and non-null
-- =============================================
SELECT COUNT(*) AS invalid_rows
FROM staging.transactions
WHERE transaction_id IS NULL;

SELECT transaction_id, COUNT(*) AS row_count
FROM staging.transactions
GROUP BY transaction_id
HAVING COUNT(*) > 1;

-- =============================================
-- QA-03: Every detail transaction exists in Transactions
-- =============================================
SELECT d.transaction_id
FROM staging.transaction_details d
LEFT JOIN staging.transactions t
    ON t.transaction_id = d.transaction_id
WHERE t.transaction_id IS NULL;

-- =============================================
-- QA-04: Every detail product exists in Products
-- =============================================
SELECT d.product_id
FROM staging.transaction_details d
LEFT JOIN staging.products p
    ON p.product_id = d.product_id
WHERE p.product_id IS NULL;

-- =============================================
-- QA-05: Quantity > 0
-- =============================================
SELECT COUNT(*) AS invalid_quantity_rows
FROM staging.transaction_details
WHERE quantity <= 0;

-- =============================================
-- QA-06: Detail subtotal arithmetic
-- =============================================
SELECT COUNT(*) AS subtotal_mismatch_rows
FROM staging.transaction_details
WHERE subtotal <> quantity * unit_price - discount;

-- =============================================
-- QA-07: Transaction arithmetic
-- =============================================
SELECT COUNT(*) AS transaction_amount_mismatch_rows
FROM staging.transactions
WHERE final_amount <> total_amount - discount;

-- =============================================
-- QA-08: Transaction-to-detail revenue reconciliation
-- =============================================
WITH detail_totals AS (
    SELECT transaction_id, SUM(subtotal) AS detail_revenue
    FROM staging.transaction_details
    GROUP BY transaction_id
)
SELECT
    t.transaction_id,
    t.final_amount,
    COALESCE(d.detail_revenue, 0) AS detail_revenue,
    t.final_amount - COALESCE(d.detail_revenue, 0) AS reconciliation_diff
FROM staging.transactions t
LEFT JOIN detail_totals d
    ON d.transaction_id = t.transaction_id
WHERE t.final_amount <> COALESCE(d.detail_revenue, 0)
ORDER BY ABS(t.final_amount - COALESCE(d.detail_revenue, 0)) DESC;

-- =============================================
-- QA-09: Price match vs master
-- =============================================
SELECT COUNT(*) AS price_mismatch_rows
FROM staging.transaction_details d
JOIN staging.products p USING (product_id)
WHERE d.unit_price <> p.selling_price;

-- =============================================
-- QA-10: Cost match vs master
-- =============================================
SELECT COUNT(*) AS cost_mismatch_rows
FROM staging.transaction_details d
JOIN staging.products p USING (product_id)
WHERE d.unit_cost <> p.cost_price;

-- =============================================
-- QA-11: Non-negative master prices
-- =============================================
SELECT COUNT(*) AS invalid_master_price_cost
FROM staging.products
WHERE selling_price < 0 OR cost_price < 0;

-- =============================================
-- QA-12: Payment method cardinality
-- =============================================
SELECT payment_method, COUNT(*) AS row_count
FROM staging.transactions
GROUP BY payment_method
ORDER BY payment_method;

-- =============================================
-- QA-13: Date range coverage
-- =============================================
SELECT
    MIN(date) AS min_date,
    MAX(date) AS max_date,
    COUNT(*) FILTER (
        WHERE date < DATE '2025-09-01'
           OR date > DATE '2026-01-31'
    ) AS outside_expected_range
FROM staging.transactions;

-- =============================================
-- QA-14: Duplicate product-name investigation
-- =============================================
SELECT
    product_name,
    COUNT(*) AS rows_with_name,
    STRING_AGG(product_id, ', ' ORDER BY product_id) AS product_ids
FROM staging.products
GROUP BY product_name
HAVING COUNT(*) > 1
ORDER BY rows_with_name DESC, product_name;

-- =============================================
-- QA-15: Documentation mismatch
-- (This is a documentation note, not a SQL calc)
-- The source README mentions stock, but the actual
-- Products table has no stock field.
-- ACTION: Record as DATA DOCUMENTATION ISSUE.
-- =============================================

-- =============================================
-- QA SUMMARY: One-query portfolio evidence
-- =============================================
WITH recon AS (
    SELECT t.transaction_id,
           t.final_amount - COALESCE(SUM(d.subtotal),0) AS diff
    FROM staging.transactions t
    LEFT JOIN staging.transaction_details d USING (transaction_id)
    GROUP BY t.transaction_id, t.final_amount
)
SELECT 'QA-01' AS test_id, 'Products unique/non-null product_id' AS rule,
       (SELECT COUNT(*) FROM staging.products WHERE product_id IS NULL) AS invalid_rows
UNION ALL
SELECT 'QA-02', 'Transactions unique/non-null transaction_id',
       (SELECT COUNT(*) FROM staging.transactions WHERE transaction_id IS NULL)
UNION ALL
SELECT 'QA-03', 'Detail transaction_id orphan',
       (SELECT COUNT(*) FROM staging.transaction_details d
        LEFT JOIN staging.transactions t USING (transaction_id)
        WHERE t.transaction_id IS NULL)
UNION ALL
SELECT 'QA-04', 'Detail product_id orphan',
       (SELECT COUNT(*) FROM staging.transaction_details d
        LEFT JOIN staging.products p USING (product_id)
        WHERE p.product_id IS NULL)
UNION ALL
SELECT 'QA-05', 'quantity > 0',
       (SELECT COUNT(*) FROM staging.transaction_details WHERE quantity <= 0)
UNION ALL
SELECT 'QA-06', 'detail subtotal arithmetic',
       (SELECT COUNT(*) FROM staging.transaction_details
        WHERE subtotal <> quantity * unit_price - discount)
UNION ALL
SELECT 'QA-07', 'transaction final arithmetic',
       (SELECT COUNT(*) FROM staging.transactions
        WHERE final_amount <> total_amount - discount)
UNION ALL
SELECT 'QA-08', 'transaction vs detail reconciliation',
       (SELECT COUNT(*) FROM recon WHERE diff <> 0)
UNION ALL
SELECT 'QA-09', 'detail unit_price vs master',
       (SELECT COUNT(*) FROM staging.transaction_details d
        JOIN staging.products p USING (product_id)
        WHERE d.unit_price <> p.selling_price)
UNION ALL
SELECT 'QA-10', 'detail unit_cost vs master',
       (SELECT COUNT(*) FROM staging.transaction_details d
        JOIN staging.products p USING (product_id)
        WHERE d.unit_cost <> p.cost_price)
UNION ALL
SELECT 'QA-11', 'master non-negative prices',
       (SELECT COUNT(*) FROM staging.products
        WHERE selling_price < 0 OR cost_price < 0)
UNION ALL
SELECT 'QA-12', 'payment method cardinality check (manual)',
       (SELECT COUNT(DISTINCT payment_method) FROM staging.transactions)
UNION ALL
SELECT 'QA-13', 'dates outside expected range',
       (SELECT COUNT(*) FROM staging.transactions
        WHERE date < DATE '2025-09-01' OR date > DATE '2026-01-31')
ORDER BY test_id;
