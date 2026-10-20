-- =============================================================================
-- Target: wh_gold (Fabric Warehouse). Creates the gold schema and star-schema tables.
-- Tables are loaded by gold.usp_load_gold (sql/fabric-warehouse/04_usp_load_gold.sql), which reads silver
-- Delta tables in lh_silver through cross-item queries.
-- =============================================================================

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'gold')
BEGIN
    EXEC('CREATE SCHEMA gold');
END
GO

IF OBJECT_ID('gold.fact_payments_daily') IS NOT NULL DROP TABLE gold.fact_payments_daily;
IF OBJECT_ID('gold.fact_daily_channel_summary') IS NOT NULL DROP TABLE gold.fact_daily_channel_summary;
IF OBJECT_ID('gold.dim_account') IS NOT NULL DROP TABLE gold.dim_account;
IF OBJECT_ID('gold.dim_customer') IS NOT NULL DROP TABLE gold.dim_customer;
IF OBJECT_ID('gold.dim_branch') IS NOT NULL DROP TABLE gold.dim_branch;
IF OBJECT_ID('gold.dim_date') IS NOT NULL DROP TABLE gold.dim_date;
GO

CREATE TABLE gold.dim_date
(
    date_key      INT         NOT NULL,
    calendar_date DATE        NOT NULL,
    year_num      SMALLINT    NOT NULL,
    quarter_num   SMALLINT    NOT NULL,
    month_num     SMALLINT    NOT NULL,
    month_name    VARCHAR(12) NOT NULL,
    day_of_week   SMALLINT    NOT NULL,
    is_weekend    BIT         NOT NULL
);
GO

CREATE TABLE gold.dim_branch
(
    branch_key    INT          NOT NULL,
    branch_code   VARCHAR(10)  NOT NULL,
    branch_name   VARCHAR(100) NOT NULL,
    province_code CHAR(2)      NOT NULL,
    city          VARCHAR(60)  NOT NULL
);
GO

CREATE TABLE gold.dim_customer
(
    customer_key    INT         NOT NULL,
    customer_id     VARCHAR(12) NOT NULL,
    segment         VARCHAR(20) NOT NULL,
    province_code   CHAR(2)     NOT NULL,
    age_band        VARCHAR(10) NOT NULL,
    kyc_risk_rating VARCHAR(10) NOT NULL,
    onboarding_date DATE        NOT NULL
);
GO

CREATE TABLE gold.dim_account
(
    account_key  INT         NOT NULL,
    account_id   VARCHAR(14) NOT NULL,
    customer_key INT         NOT NULL,
    product_type VARCHAR(30) NOT NULL,
    open_date    DATE        NOT NULL,
    currency     CHAR(3)     NOT NULL
);
GO

CREATE TABLE gold.fact_daily_channel_summary
(
    date_key               INT           NOT NULL,
    branch_key             INT           NOT NULL,
    channel                VARCHAR(12)   NOT NULL,
    currency               CHAR(3)       NOT NULL,
    txn_count              BIGINT        NOT NULL,
    total_amount           DECIMAL(18,2) NOT NULL,
    large_cash_flag_count  BIGINT        NOT NULL
);
GO

CREATE TABLE gold.fact_payments_daily
(
    payment_date   DATE          NOT NULL,
    payment_type   VARCHAR(20)   NOT NULL,
    payment_status VARCHAR(12)   NOT NULL,
    currency       CHAR(3)       NOT NULL,
    payment_count  BIGINT        NOT NULL,
    amount_total   DECIMAL(18,2) NOT NULL
);
GO
