-- ============================================================
-- 02_create_tables.sql
-- Retail Sales & Demand Analytics - PostgreSQL Portfolio
-- Purpose: DDL, primary/foreign keys, check constraints, indexes
-- ============================================================

-- ---- Products ----
CREATE TABLE staging.products (
    product_id      text            PRIMARY KEY,
    product_name    text            NOT NULL,
    category        text            NOT NULL,
    type            text            NOT NULL CHECK (type IN ('Product','Service')),
    selling_price   numeric(14,2)   NOT NULL CHECK (selling_price >= 0),
    cost_price      numeric(14,2)   NOT NULL CHECK (cost_price >= 0),
    unit            text            NOT NULL
);

-- ---- Transactions ----
CREATE TABLE staging.transactions (
    transaction_id  text            PRIMARY KEY,
    date            date            NOT NULL,
    time            time            NOT NULL,
    payment_method  text            NOT NULL CHECK (payment_method IN ('Cash','QRIS','Transfer')),
    total_amount    numeric(14,2)   NOT NULL CHECK (total_amount >= 0),
    discount        numeric(14,2)   NOT NULL CHECK (discount >= 0),
    final_amount    numeric(14,2)   NOT NULL CHECK (final_amount >= 0),
    CONSTRAINT chk_transaction_amount
        CHECK (final_amount = total_amount - discount)
);

-- ---- Transaction Details ----
CREATE TABLE staging.transaction_details (
    transaction_line_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transaction_id  text            NOT NULL,
    product_id      text            NOT NULL,
    quantity        integer         NOT NULL CHECK (quantity > 0),
    unit_price      numeric(14,2)   NOT NULL CHECK (unit_price >= 0),
    unit_cost       numeric(14,2)   NOT NULL CHECK (unit_cost >= 0),
    discount        numeric(14,2)   NOT NULL CHECK (discount >= 0),
    subtotal        numeric(14,2)   NOT NULL CHECK (subtotal >= 0),
    CONSTRAINT fk_detail_transaction
        FOREIGN KEY (transaction_id)
        REFERENCES staging.transactions(transaction_id),
    CONSTRAINT fk_detail_product
        FOREIGN KEY (product_id)
        REFERENCES staging.products(product_id),
    CONSTRAINT chk_detail_subtotal
        CHECK (subtotal = quantity * unit_price - discount)
);

-- ---- Indexes ----
CREATE INDEX idx_transactions_date
    ON staging.transactions(date);

CREATE INDEX idx_details_transaction_id
    ON staging.transaction_details(transaction_id);

CREATE INDEX idx_details_product_id
    ON staging.transaction_details(product_id);
