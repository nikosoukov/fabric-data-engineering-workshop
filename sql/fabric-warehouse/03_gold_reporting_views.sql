-- =============================================================================
-- Reporting views in wh_gold. Run after nb_04 has loaded the gold tables.
-- These are the objects BI tools (Power BI DirectLake or DirectQuery) and analysts query.
-- =============================================================================

IF OBJECT_ID('gold.vw_large_cash_flags_by_province') IS NOT NULL DROP VIEW gold.vw_large_cash_flags_by_province;
GO

CREATE VIEW gold.vw_large_cash_flags_by_province
AS
SELECT
    b.province_code,
    d.year_num,
    d.month_num,
    SUM(f.large_cash_flag_count) AS large_cash_flags,
    SUM(f.txn_count)             AS transactions,
    SUM(f.total_amount)          AS total_amount
FROM gold.fact_daily_channel_summary AS f
JOIN gold.dim_branch AS b ON b.branch_key = f.branch_key
JOIN gold.dim_date   AS d ON d.date_key   = f.date_key
GROUP BY b.province_code, d.year_num, d.month_num;
GO

IF OBJECT_ID('gold.vw_channel_mix_monthly') IS NOT NULL DROP VIEW gold.vw_channel_mix_monthly;
GO

CREATE VIEW gold.vw_channel_mix_monthly
AS
SELECT
    d.year_num,
    d.month_num,
    f.channel,
    SUM(f.txn_count)    AS transactions,
    SUM(f.total_amount) AS total_amount
FROM gold.fact_daily_channel_summary AS f
JOIN gold.dim_date AS d ON d.date_key = f.date_key
GROUP BY d.year_num, d.month_num, f.channel;
GO
