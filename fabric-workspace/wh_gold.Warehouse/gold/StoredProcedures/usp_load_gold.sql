CREATE PROCEDURE gold.usp_load_gold
AS
BEGIN
    TRUNCATE TABLE gold.dim_date;
    INSERT INTO gold.dim_date (date_key, calendar_date, year_num, quarter_num, month_num, month_name, day_of_week, is_weekend)
    SELECT date_key, calendar_date, year_num, quarter_num, month_num, month_name, day_of_week, is_weekend
    FROM lh_silver.bronze.synapse_dim_date;

    TRUNCATE TABLE gold.dim_branch;
    INSERT INTO gold.dim_branch (branch_key, branch_code, branch_name, province_code, city)
    SELECT branch_key, branch_code, branch_name, province_code, city
    FROM lh_silver.silver.branches;

    TRUNCATE TABLE gold.dim_customer;
    INSERT INTO gold.dim_customer (customer_key, customer_id, segment, province_code, age_band, kyc_risk_rating, onboarding_date)
    SELECT customer_key, customer_id, segment, province_code, age_band, kyc_risk_rating, onboarding_date
    FROM lh_silver.silver.customers;

    TRUNCATE TABLE gold.dim_account;
    INSERT INTO gold.dim_account (account_key, account_id, customer_key, product_type, open_date, currency)
    SELECT account_key, account_id, customer_key, product_type, open_date, currency
    FROM lh_silver.silver.accounts;

    TRUNCATE TABLE gold.fact_daily_channel_summary;
    INSERT INTO gold.fact_daily_channel_summary (date_key, branch_key, channel, currency, txn_count, total_amount, large_cash_flag_count)
    SELECT date_key, branch_key, channel, currency,
           COUNT_BIG(*),
           SUM(amount),
           SUM(CASE WHEN is_large_cash_flag = 1 THEN 1 ELSE 0 END)
    FROM lh_silver.silver.transactions
    GROUP BY date_key, branch_key, channel, currency;

    TRUNCATE TABLE gold.fact_payments_daily;
    INSERT INTO gold.fact_payments_daily (payment_date, payment_type, payment_status, currency, payment_count, amount_total)
    SELECT CAST(created_at AS DATE), payment_type, payment_status, currency, COUNT_BIG(*), SUM(amount)
    FROM lh_silver.silver.payments
    GROUP BY CAST(created_at AS DATE), payment_type, payment_status, currency;
END;

GO