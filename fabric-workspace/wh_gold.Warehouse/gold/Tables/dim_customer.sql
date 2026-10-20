CREATE TABLE [gold].[dim_customer] (
    [customer_key]    INT          NOT NULL,
    [customer_id]     VARCHAR (12) NOT NULL,
    [segment]         VARCHAR (20) NOT NULL,
    [province_code]   CHAR (2)     NOT NULL,
    [age_band]        VARCHAR (10) NOT NULL,
    [kyc_risk_rating] VARCHAR (10) NOT NULL,
    [onboarding_date] DATE         NOT NULL
);


GO