CREATE TABLE [core].[accounts] (
    [account_id]   INT           NOT NULL,
    [customer_id]  INT           NOT NULL,
    [account_ref]  VARCHAR (14)  NOT NULL,
    [product_type] VARCHAR (30)  NOT NULL,
    [status]       VARCHAR (12)  NOT NULL,
    [opened_on]    DATE          NOT NULL,
    [updated_at]   DATETIME2 (3) NOT NULL,
    CONSTRAINT [pk_accounts] PRIMARY KEY CLUSTERED ([account_id] ASC)
);


GO

