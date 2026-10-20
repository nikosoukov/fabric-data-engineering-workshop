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