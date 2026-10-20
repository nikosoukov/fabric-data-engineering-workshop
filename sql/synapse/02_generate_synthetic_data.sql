-- =============================================================================
-- Synthetic data generator for the Synapse dedicated SQL pool (SYNTHETIC ONLY).
-- Deterministic: the same row count always produces the same data, with no randomness.
-- Tokens filled in by scripts/03-generate-synthetic-data.ps1:
--   {{FACT_ROWS}}  number of rows in dbo.fact_transaction
--   {{BLOCKS}}     ceiling(FACT_ROWS / 1,000,000)
-- =============================================================================

-- 1) Helper sequences ---------------------------------------------------------
IF OBJECT_ID('dbo.seq_digits') IS NOT NULL DROP TABLE dbo.seq_digits;
CREATE TABLE dbo.seq_digits (d INT NOT NULL) WITH (DISTRIBUTION = REPLICATE, HEAP);
INSERT INTO dbo.seq_digits (d)
SELECT 0 UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9;
GO

IF OBJECT_ID('dbo.seq_1m') IS NOT NULL DROP TABLE dbo.seq_1m;
CREATE TABLE dbo.seq_1m WITH (DISTRIBUTION = ROUND_ROBIN, HEAP) AS
SELECT CAST(a.d * 100000 + b.d * 10000 + c.d * 1000 + e.d * 100 + f.d * 10 + g.d AS INT) AS n
FROM dbo.seq_digits a
CROSS JOIN dbo.seq_digits b
CROSS JOIN dbo.seq_digits c
CROSS JOIN dbo.seq_digits e
CROSS JOIN dbo.seq_digits f
CROSS JOIN dbo.seq_digits g;
GO

IF OBJECT_ID('dbo.seq_blocks') IS NOT NULL DROP TABLE dbo.seq_blocks;
CREATE TABLE dbo.seq_blocks WITH (DISTRIBUTION = REPLICATE, HEAP) AS
SELECT CAST(a.d * 100 + b.d * 10 + c.d AS INT) AS blk
FROM dbo.seq_digits a
CROSS JOIN dbo.seq_digits b
CROSS JOIN dbo.seq_digits c
WHERE CAST(a.d * 100 + b.d * 10 + c.d AS INT) < {{BLOCKS}};
GO

-- 2) Dimensions (truncated first so the script is safe to rerun) ----------------
TRUNCATE TABLE dbo.dim_date;
TRUNCATE TABLE dbo.dim_branch;
TRUNCATE TABLE dbo.dim_customer;
TRUNCATE TABLE dbo.dim_account;
GO

INSERT INTO dbo.dim_date (date_key, calendar_date, year_num, quarter_num, month_num, month_name, day_of_week, is_weekend)
SELECT
    CAST(YEAR(d.dt) * 10000 + MONTH(d.dt) * 100 + DAY(d.dt) AS INT),
    d.dt,
    CAST(YEAR(d.dt) AS SMALLINT),
    CAST(DATEPART(QUARTER, d.dt) AS TINYINT),
    CAST(MONTH(d.dt) AS TINYINT),
    DATENAME(MONTH, d.dt),
    CAST(DATEPART(WEEKDAY, d.dt) AS TINYINT),
    CASE WHEN DATEPART(WEEKDAY, d.dt) IN (1, 7) THEN 1 ELSE 0 END
FROM (SELECT DATEADD(DAY, n, CAST('2024-01-01' AS DATE)) AS dt FROM dbo.seq_1m WHERE n < 1096) d;
GO

INSERT INTO dbo.dim_branch (branch_key, branch_code, branch_name, province_code, city)
SELECT
    n + 1,
    'BR' + RIGHT('000' + CAST(n + 1 AS VARCHAR(3)), 3),
    'Branch ' + CAST(n + 1 AS VARCHAR(3)),
    CASE n % 10 WHEN 0 THEN 'ON' WHEN 1 THEN 'ON' WHEN 2 THEN 'QC' WHEN 3 THEN 'QC' WHEN 4 THEN 'BC'
                WHEN 5 THEN 'AB' WHEN 6 THEN 'MB' WHEN 7 THEN 'NS' WHEN 8 THEN 'SK' ELSE 'NB' END,
    CASE n % 10 WHEN 0 THEN 'Toronto' WHEN 1 THEN 'Ottawa' WHEN 2 THEN 'Montreal' WHEN 3 THEN 'Quebec City'
                WHEN 4 THEN 'Vancouver' WHEN 5 THEN 'Calgary' WHEN 6 THEN 'Winnipeg' WHEN 7 THEN 'Halifax'
                WHEN 8 THEN 'Saskatoon' ELSE 'Moncton' END
FROM dbo.seq_1m WHERE n < 200;
GO

INSERT INTO dbo.dim_customer (customer_key, customer_id, segment, province_code, age_band, kyc_risk_rating, onboarding_date)
SELECT
    n + 1,
    'C' + RIGHT('00000000' + CAST(n + 1 AS VARCHAR(8)), 8),
    CASE n % 4 WHEN 0 THEN 'Retail' WHEN 1 THEN 'Small Business' WHEN 2 THEN 'Commercial' ELSE 'Wealth' END,
    CASE n % 10 WHEN 0 THEN 'ON' WHEN 1 THEN 'ON' WHEN 2 THEN 'QC' WHEN 3 THEN 'QC' WHEN 4 THEN 'BC'
                WHEN 5 THEN 'AB' WHEN 6 THEN 'MB' WHEN 7 THEN 'NS' WHEN 8 THEN 'SK' ELSE 'NB' END,
    CASE n % 5 WHEN 0 THEN '18-24' WHEN 1 THEN '25-34' WHEN 2 THEN '35-49' WHEN 3 THEN '50-64' ELSE '65+' END,
    CASE n % 20 WHEN 0 THEN 'High' WHEN 1 THEN 'High' WHEN 2 THEN 'High' WHEN 3 THEN 'Medium' WHEN 4 THEN 'Medium'
                WHEN 5 THEN 'Medium' ELSE 'Low' END,
    DATEADD(DAY, n % 2500, CAST('2015-01-01' AS DATE))
FROM dbo.seq_1m WHERE n < 50000;
GO

INSERT INTO dbo.dim_account (account_key, account_id, customer_key, product_type, open_date, currency)
SELECT
    n + 1,
    'A' + RIGHT('0000000000000' + CAST(n + 1 AS VARCHAR(13)), 13),
    (n % 50000) + 1,
    CASE n % 5 WHEN 0 THEN 'Chequing' WHEN 1 THEN 'Savings' WHEN 2 THEN 'Mortgage' WHEN 3 THEN 'Credit Card' ELSE 'GIC' END,
    DATEADD(DAY, n % 3000, CAST('2014-01-01' AS DATE)),
    CASE WHEN n % 10 = 0 THEN 'USD' ELSE 'CAD' END
FROM dbo.seq_1m WHERE n < 80000;
GO

-- 3) Fact table (CTAS, hash-distributed on account_key) -------------------------
IF OBJECT_ID('dbo.fact_transaction') IS NOT NULL DROP TABLE dbo.fact_transaction;
GO

CREATE TABLE dbo.fact_transaction
WITH (DISTRIBUTION = HASH(account_key), CLUSTERED COLUMNSTORE INDEX)
AS
SELECT
    t.transaction_id,
    t.date_key,
    t.account_key,
    t.branch_key,
    t.channel,
    t.txn_type,
    t.amount,
    t.currency,
    CASE WHEN t.txn_type = 'Cash Deposit' AND t.amount >= 10000 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS is_large_cash_flag
FROM (
    SELECT
        b.transaction_id,
        CAST(YEAR(DATEADD(DAY, b.h_date, CAST('2024-01-01' AS DATE))) * 10000
           + MONTH(DATEADD(DAY, b.h_date, CAST('2024-01-01' AS DATE))) * 100
           + DAY(DATEADD(DAY, b.h_date, CAST('2024-01-01' AS DATE))) AS INT) AS date_key,
        1 + b.h_acct AS account_key,
        1 + b.h_branch AS branch_key,
        CASE b.h_channel WHEN 0 THEN 'Branch' WHEN 1 THEN 'Online' WHEN 2 THEN 'Mobile' ELSE 'ATM' END AS channel,
        CASE WHEN b.transaction_id % 50 = 0 THEN 'Cash Deposit' ELSE
            CASE b.h_type WHEN 0 THEN 'Cash Deposit' WHEN 1 THEN 'Cash Withdrawal' WHEN 2 THEN 'EFT'
                          WHEN 3 THEN 'Wire' WHEN 4 THEN 'Bill Payment' ELSE 'Card Purchase' END END AS txn_type,
        CAST(CASE WHEN b.transaction_id % 50 = 0
                  THEN 10000 + (b.h_amt % 2000000) / 100.0
                  ELSE (b.h_amt % 500000) / 100.0 END AS DECIMAL(18, 2)) AS amount,
        CASE WHEN b.h_ccy % 10 = 0 THEN 'USD' ELSE 'CAD' END AS currency
    FROM (
        SELECT
            x.transaction_id,
            (CHECKSUM(x.transaction_id + 1) & 2147483647) % 1096 AS h_date,
            (CHECKSUM(x.transaction_id + 2) & 2147483647) % 80000 AS h_acct,
            (CHECKSUM(x.transaction_id + 3) & 2147483647) % 200 AS h_branch,
            (CHECKSUM(x.transaction_id + 4) & 2147483647) % 4 AS h_channel,
            (CHECKSUM(x.transaction_id + 5) & 2147483647) % 6 AS h_type,
            (CHECKSUM(x.transaction_id + 6) & 2147483647) AS h_amt,
            (CHECKSUM(x.transaction_id + 7) & 2147483647) AS h_ccy
        FROM (
            SELECT TOP ({{FACT_ROWS}})
                CAST(k.blk AS BIGINT) * 1000000 + s.n + 1 AS transaction_id
            FROM dbo.seq_1m s
            CROSS JOIN dbo.seq_blocks k
        ) x
    ) b
) t;
GO

-- 4) Clean up helper tables ----------------------------------------------------
DROP TABLE dbo.seq_blocks;
DROP TABLE dbo.seq_1m;
DROP TABLE dbo.seq_digits;
GO

-- 5) Quick row-count check -----------------------------------------------------
SELECT 'fact_transaction' AS table_name, COUNT_BIG(*) AS row_count FROM dbo.fact_transaction
UNION ALL SELECT 'dim_account', COUNT_BIG(*) FROM dbo.dim_account
UNION ALL SELECT 'dim_customer', COUNT_BIG(*) FROM dbo.dim_customer
UNION ALL SELECT 'dim_branch', COUNT_BIG(*) FROM dbo.dim_branch
UNION ALL SELECT 'dim_date', COUNT_BIG(*) FROM dbo.dim_date;
