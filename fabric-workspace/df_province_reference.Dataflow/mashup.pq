[StagingDefinition = [Kind = "FastCopy"]]
section Section1;

shared ref_province = let
    Source = #table(
        type table [province_code = text, province_name = text, region = text],
        {
            {"ON", "Ontario", "Central"},
            {"QC", "Quebec", "Central"},
            {"BC", "British Columbia", "West"},
            {"AB", "Alberta", "West"},
            {"MB", "Manitoba", "West"},
            {"SK", "Saskatchewan", "West"},
            {"NS", "Nova Scotia", "Atlantic"},
            {"NB", "New Brunswick", "Atlantic"}
        }),
    Typed = Table.TransformColumnTypes(Source, {{"province_code", type text}, {"province_name", type text}, {"region", type text}}),
    Cleaned = Table.TransformColumns(Typed, {{"province_code", Text.Upper, type text}}),
    Sorted = Table.Sort(Cleaned, {{"province_code", Order.Ascending}})
in
    Sorted;
