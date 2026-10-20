CREATE TABLE [core].[customers] (
    [customer_id]   INT           NOT NULL,
    [customer_ref]  VARCHAR (12)  NOT NULL,
    [full_name]     VARCHAR (80)  NOT NULL,
    [province_code] CHAR (2)      NOT NULL,
    [segment]       VARCHAR (20)  NOT NULL,
    [updated_at]    DATETIME2 (3) NOT NULL,
    CONSTRAINT [pk_customers] PRIMARY KEY CLUSTERED ([customer_id] ASC)
);


GO

