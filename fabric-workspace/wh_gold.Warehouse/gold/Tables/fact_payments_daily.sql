CREATE TABLE [gold].[fact_payments_daily] (
    [payment_date]   DATE            NOT NULL,
    [payment_type]   VARCHAR (20)    NOT NULL,
    [payment_status] VARCHAR (12)    NOT NULL,
    [currency]       CHAR (3)        NOT NULL,
    [payment_count]  BIGINT          NOT NULL,
    [amount_total]   DECIMAL (18, 2) NOT NULL
);


GO