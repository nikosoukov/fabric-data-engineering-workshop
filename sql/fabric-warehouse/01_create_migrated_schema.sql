-- =============================================================================
-- Target: wh_migrated_synapse (Fabric Warehouse)
-- Converted from sql/synapse/01_create_source_schema.sql.
-- Conversion rules applied:
--   1. DISTRIBUTION = ... and CLUSTERED COLUMNSTORE INDEX are removed. Fabric manages data layout.
--   2. PRIMARY KEY is not allowed in CREATE TABLE in Fabric Warehouse. It is added with ALTER TABLE
--      as NONCLUSTERED ... NOT ENFORCED. Keys are informational, which matches the Synapse behaviour.
--   3. Data types are mapped where Fabric Warehouse lacks a type: TINYINT becomes SMALLINT.
--      DECIMAL, VARCHAR, CHAR, DATE, BIT, BIGINT, and INT are unchanged.
-- =============================================================================

IF OBJECT_ID('dbo.fact_transaction') IS NOT NULL DROP TABLE dbo.fact_transaction;
IF OBJECT_ID('dbo.dim_account') IS NOT NULL DROP TABLE dbo.dim_account;
IF OBJECT_ID('dbo.dim_customer') IS NOT NULL DROP TABLE dbo.dim_customer;
IF OBJECT_ID('dbo.dim_branch') IS NOT NULL DROP TABLE dbo.dim_branch;
IF OBJECT_ID('dbo.dim_date') IS NOT NULL DROP TABLE dbo.dim_date;
GO

CREATE TABLE dbo.dim_date
(
    date_key      INT          NOT NULL,
    calendar_date DATE         NOT NULL,
    year_num      SMALLINT     NOT NULL,
    quarter_num   SMALLINT     NOT NULL,
    month_num     SMALLINT     NOT NULL,
    month_name    VARCHAR(12)  NOT NULL,
    day_of_week   SMALLINT     NOT NULL,
    is_weekend    BIT          NOT NULL
);
GO

CREATE TABLE dbo.dim_branch
(
    branch_key    INT          NOT NULL,
    branch_code   VARCHAR(10)  NOT NULL,
    branch_name   VARCHAR(100) NOT NULL,
    province_code CHAR(2)      NOT NULL,
    city          VARCHAR(60)  NOT NULL
);
GO

CREATE TABLE dbo.dim_customer
(
    customer_key     INT         NOT NULL,
    customer_id      VARCHAR(12) NOT NULL,
    segment          VARCHAR(20) NOT NULL,
    province_code    CHAR(2)     NOT NULL,
    age_band         VARCHAR(10) NOT NULL,
    kyc_risk_rating  VARCHAR(10) NOT NULL,
    onboarding_date  DATE        NOT NULL
);
GO

CREATE TABLE dbo.dim_account
(
    account_key  INT         NOT NULL,
    account_id   VARCHAR(14) NOT NULL,
    customer_key INT         NOT NULL,
    product_type VARCHAR(30) NOT NULL,
    open_date    DATE        NOT NULL,
    currency     CHAR(3)     NOT NULL
);
GO

CREATE TABLE dbo.fact_transaction
(
    transaction_id     BIGINT        NOT NULL,
    date_key           INT           NOT NULL,
    account_key        INT           NOT NULL,
    branch_key         INT           NOT NULL,
    channel            VARCHAR(12)   NOT NULL,
    txn_type           VARCHAR(20)   NOT NULL,
    amount             DECIMAL(18,2) NOT NULL,
    currency           CHAR(3)       NOT NULL,
    is_large_cash_flag BIT           NOT NULL
);
GO

ALTER TABLE dbo.dim_date     ADD CONSTRAINT pk_dim_date     PRIMARY KEY NONCLUSTERED (date_key)     NOT ENFORCED;
ALTER TABLE dbo.dim_branch   ADD CONSTRAINT pk_dim_branch   PRIMARY KEY NONCLUSTERED (branch_key)   NOT ENFORCED;
ALTER TABLE dbo.dim_customer ADD CONSTRAINT pk_dim_customer PRIMARY KEY NONCLUSTERED (customer_key) NOT ENFORCED;
ALTER TABLE dbo.dim_account  ADD CONSTRAINT pk_dim_account  PRIMARY KEY NONCLUSTERED (account_key)  NOT ENFORCED;
GO
