CREATE TABLE [dbo].[dim_date] (
    [date_key]      INT          NOT NULL,
    [calendar_date] DATE         NOT NULL,
    [year_num]      SMALLINT     NOT NULL,
    [quarter_num]   SMALLINT     NOT NULL,
    [month_num]     SMALLINT     NOT NULL,
    [month_name]    VARCHAR (12) NOT NULL,
    [day_of_week]   SMALLINT     NOT NULL,
    [is_weekend]    BIT          NOT NULL
);


GO

ALTER TABLE [dbo].[dim_date]
    ADD CONSTRAINT [pk_dim_date] PRIMARY KEY NONCLUSTERED ([date_key] ASC) NOT ENFORCED;


GO