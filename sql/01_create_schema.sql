-- ============================================================
-- 01_create_schema.sql
-- Retail Sales & Demand Analytics - PostgreSQL Portfolio
-- Purpose: Create staging and analytics schemas
-- ============================================================

-- Verify connection context
SELECT
    current_database()  AS database_name,
    current_user        AS login_role,
    current_setting('TimeZone') AS timezone;

-- Create schemas
CREATE SCHEMA IF NOT EXISTS staging    AUTHORIZATION retail_analyst;
CREATE SCHEMA IF NOT EXISTS analytics  AUTHORIZATION retail_analyst;

COMMENT ON SCHEMA staging IS
    'Validated relational source tables loaded from Excel/CSV.';
COMMENT ON SCHEMA analytics IS
    'Reusable analytical views and output datasets for BI/forecasting.';
