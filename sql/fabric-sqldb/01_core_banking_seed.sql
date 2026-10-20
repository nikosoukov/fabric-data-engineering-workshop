-- =============================================================================
-- Fabric SQL database: operational core-banking source for the Mirroring demo.
-- Synthetic data only. Tables get primary keys so OneLake mirroring has what it needs.
-- Deterministic: rerunning produces the same rows (tables are truncated first).
-- =============================================================================

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'core') EXEC('CREATE SCHEMA core');
GO

IF OBJECT_ID('core.payments') IS NOT NULL DROP TABLE core.payments;
IF OBJECT_ID('core.accounts') IS NOT NULL DROP TABLE core.accounts;
IF OBJECT_ID('core.customers') IS NOT NULL DROP TABLE core.customers;
GO

CREATE TABLE core.customers
(
    customer_id     INT          NOT NULL CONSTRAINT pk_customers PRIMARY KEY,
    customer_ref    VARCHAR(12)  NOT NULL,
    full_name       VARCHAR(80)  NOT NULL,
    province_code   CHAR(2)      NOT NULL,
    segment         VARCHAR(20)  NOT NULL,
    updated_at      DATETIME2(3) NOT NULL
);
GO

CREATE TABLE core.accounts
(
    account_id      INT          NOT NULL CONSTRAINT pk_accounts PRIMARY KEY,
    customer_id     INT          NOT NULL,
    account_ref     VARCHAR(14)  NOT NULL,
    product_type    VARCHAR(30)  NOT NULL,
    status          VARCHAR(12)  NOT NULL,
    opened_on       DATE         NOT NULL,
    updated_at      DATETIME2(3) NOT NULL
);
GO

CREATE TABLE core.payments
(
    payment_id      BIGINT       NOT NULL CONSTRAINT pk_payments PRIMARY KEY,
    account_id      INT          NOT NULL,
    payment_type    VARCHAR(20)  NOT NULL,
    amount          DECIMAL(18,2) NOT NULL,
    currency        CHAR(3)      NOT NULL,
    payment_status  VARCHAR(12)  NOT NULL,
    created_at      DATETIME2(3) NOT NULL,
    updated_at      DATETIME2(3) NOT NULL
);
GO

-- Seed data ---------------------------------------------------------------------
;WITH n AS (
    SELECT TOP (20000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO core.customers (customer_id, customer_ref, full_name, province_code, segment, updated_at)
SELECT
    i,
    'K' + RIGHT('0000000000' + CAST(i AS VARCHAR(10)), 10),
    'Client ' + CAST(i AS VARCHAR(10)),
    CASE i % 10 WHEN 0 THEN 'ON' WHEN 1 THEN 'ON' WHEN 2 THEN 'QC' WHEN 3 THEN 'QC' WHEN 4 THEN 'BC'
                WHEN 5 THEN 'AB' WHEN 6 THEN 'MB' WHEN 7 THEN 'NS' WHEN 8 THEN 'SK' ELSE 'NB' END,
    CASE i % 4 WHEN 0 THEN 'Retail' WHEN 1 THEN 'Small Business' WHEN 2 THEN 'Commercial' ELSE 'Wealth' END,
    DATEADD(MINUTE, i, '2026-01-01T00:00:00')
FROM n;
GO

;WITH n AS (
    SELECT TOP (30000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO core.accounts (account_id, customer_id, account_ref, product_type, status, opened_on, updated_at)
SELECT
    i,
    ((i - 1) % 20000) + 1,
    'A' + RIGHT('0000000000000' + CAST(i AS VARCHAR(13)), 13),
    CASE i % 5 WHEN 0 THEN 'Chequing' WHEN 1 THEN 'Savings' WHEN 2 THEN 'Mortgage' WHEN 3 THEN 'Credit Card' ELSE 'GIC' END,
    CASE WHEN i % 37 = 0 THEN 'Closed' WHEN i % 11 = 0 THEN 'Dormant' ELSE 'Active' END,
    DATEADD(DAY, i % 2500, '2016-01-01'),
    DATEADD(MINUTE, i, '2026-01-01T00:00:00')
FROM n;
GO

;WITH n AS (
    SELECT TOP (400000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO core.payments (payment_id, account_id, payment_type, amount, currency, payment_status, created_at, updated_at)
SELECT
    CAST(i AS BIGINT),
    ((i * 7) % 30000) + 1,
    CASE i % 5 WHEN 0 THEN 'EFT' WHEN 1 THEN 'Wire' WHEN 2 THEN 'Bill Payment' WHEN 3 THEN 'Interac e-Transfer' ELSE 'Card' END,
    CAST(((i * 37) % 500000) / 100.0 AS DECIMAL(18,2)),
    CASE WHEN i % 10 = 0 THEN 'USD' ELSE 'CAD' END,
    CASE WHEN i % 23 = 0 THEN 'Failed' WHEN i % 17 = 0 THEN 'Pending' ELSE 'Settled' END,
    DATEADD(MINUTE, i * 3, '2026-01-01T00:00:00'),
    DATEADD(MINUTE, i * 3, '2026-01-01T00:00:00')
FROM n;
GO

SELECT 'customers' AS table_name, COUNT_BIG(*) AS row_count FROM core.customers
UNION ALL SELECT 'accounts', COUNT_BIG(*) FROM core.accounts
UNION ALL SELECT 'payments', COUNT_BIG(*) FROM core.payments;
