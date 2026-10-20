CREATE TABLE [core].[payments] (
    [payment_id]     BIGINT          NOT NULL,
    [account_id]     INT             NOT NULL,
    [payment_type]   VARCHAR (20)    NOT NULL,
    [amount]         DECIMAL (18, 2) NOT NULL,
    [currency]       CHAR (3)        NOT NULL,
    [payment_status] VARCHAR (12)    NOT NULL,
    [created_at]     DATETIME2 (3)   NOT NULL,
    [updated_at]     DATETIME2 (3)   NOT NULL,
    CONSTRAINT [pk_payments] PRIMARY KEY CLUSTERED ([payment_id] ASC)
);


GO

