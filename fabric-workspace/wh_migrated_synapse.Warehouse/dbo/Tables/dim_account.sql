CREATE TABLE [dbo].[dim_account] (
    [account_key]  INT          NOT NULL,
    [account_id]   VARCHAR (14) NOT NULL,
    [customer_key] INT          NOT NULL,
    [product_type] VARCHAR (30) NOT NULL,
    [open_date]    DATE         NOT NULL,
    [currency]     CHAR (3)     NOT NULL
);


GO

ALTER TABLE [dbo].[dim_account]
    ADD CONSTRAINT [pk_dim_account] PRIMARY KEY NONCLUSTERED ([account_key] ASC) NOT ENFORCED;


GO