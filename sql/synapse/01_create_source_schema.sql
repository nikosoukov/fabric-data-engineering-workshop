-- =============================================================================
-- LEGACY SOURCE: Azure Synapse dedicated SQL pool (dwpool)
-- Synapse-specific DDL: DISTRIBUTION and CLUSTERED COLUMNSTORE INDEX are required here.
-- Fabric Warehouse has no DISTRIBUTION or index clauses. The conversion is shown in
-- sql/fabric-warehouse/01_create_migrated_schema.sql.
-- All data is synthetic. It models a Canadian financial institution for teaching only.
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
    quarter_num   TINYINT      NOT NULL,
    month_num     TINYINT      NOT NULL,
    month_name    VARCHAR(12)  NOT NULL,
    day_of_week   TINYINT      NOT NULL,
    is_weekend    BIT          NOT NULL,
    CONSTRAINT pk_dim_date PRIMARY KEY NONCLUSTERED (date_key) NOT ENFORCED
)
WITH (DISTRIBUTION = REPLICATE, CLUSTERED COLUMNSTORE INDEX);
GO

CREATE TABLE dbo.dim_branch
(
    branch_key    INT          NOT NULL,
    branch_code   VARCHAR(10)  NOT NULL,
    branch_name   VARCHAR(100) NOT NULL,
    province_code CHAR(2)      NOT NULL,
    city          VARCHAR(60)  NOT NULL,
    CONSTRAINT pk_dim_branch PRIMARY KEY NONCLUSTERED (branch_key) NOT ENFORCED
)
WITH (DISTRIBUTION = REPLICATE, CLUSTERED COLUMNSTORE INDEX);
GO

CREATE TABLE dbo.dim_customer
(
    customer_key     INT         NOT NULL,
    customer_id      VARCHAR(12) NOT NULL,
    segment          VARCHAR(20) NOT NULL,
    province_code    CHAR(2)     NOT NULL,
    age_band         VARCHAR(10) NOT NULL,
    kyc_risk_rating  VARCHAR(10) NOT NULL,
    onboarding_date  DATE        NOT NULL,
    CONSTRAINT pk_dim_customer PRIMARY KEY NONCLUSTERED (customer_key) NOT ENFORCED
)
WITH (DISTRIBUTION = REPLICATE, CLUSTERED COLUMNSTORE INDEX);
GO

CREATE TABLE dbo.dim_account
(
    account_key  INT         NOT NULL,
    account_id   VARCHAR(14) NOT NULL,
    customer_key INT         NOT NULL,
    product_type VARCHAR(30) NOT NULL,
    open_date    DATE        NOT NULL,
    currency     CHAR(3)     NOT NULL,
    CONSTRAINT pk_dim_account PRIMARY KEY NONCLUSTERED (account_key) NOT ENFORCED
)
WITH (DISTRIBUTION = HASH(account_key), CLUSTERED COLUMNSTORE INDEX);
GO
