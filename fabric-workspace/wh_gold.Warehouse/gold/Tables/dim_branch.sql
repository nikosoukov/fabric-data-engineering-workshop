CREATE TABLE [gold].[dim_branch] (
    [branch_key]    INT           NOT NULL,
    [branch_code]   VARCHAR (10)  NOT NULL,
    [branch_name]   VARCHAR (100) NOT NULL,
    [province_code] CHAR (2)      NOT NULL,
    [city]          VARCHAR (60)  NOT NULL
);


GO