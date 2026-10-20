CREATE TABLE [gold].[fact_daily_channel_summary] (
    [date_key]              INT             NOT NULL,
    [branch_key]            INT             NOT NULL,
    [channel]               VARCHAR (12)    NOT NULL,
    [currency]              CHAR (3)        NOT NULL,
    [txn_count]             BIGINT          NOT NULL,
    [total_amount]          DECIMAL (18, 2) NOT NULL,
    [large_cash_flag_count] BIGINT          NOT NULL
);


GO