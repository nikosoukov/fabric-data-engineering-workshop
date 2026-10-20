CREATE TABLE [dbo].[fact_transaction] (
    [transaction_id]     BIGINT          NOT NULL,
    [date_key]           INT             NOT NULL,
    [account_key]        INT             NOT NULL,
    [branch_key]         INT             NOT NULL,
    [channel]            VARCHAR (12)    NOT NULL,
    [txn_type]           VARCHAR (20)    NOT NULL,
    [amount]             DECIMAL (18, 2) NOT NULL,
    [currency]           CHAR (3)        NOT NULL,
    [is_large_cash_flag] BIT             NOT NULL
);


GO