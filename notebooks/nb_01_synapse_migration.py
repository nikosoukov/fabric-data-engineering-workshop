# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   },
# META   "dependencies": {
# META     "lakehouse": {
# META       "default_lakehouse": "__LAKEHOUSE_ID_BRONZE__",
# META       "default_lakehouse_name": "lh_bronze",
# META       "default_lakehouse_workspace_id": "__WORKSPACE_ID__"
# META     }
# META   }
# META }

# CELL ********************

# Synapse dedicated SQL pool to Fabric migration (Medallion bronze, then warehouse).
# Step 1 reads the legacy star schema in parallel over JDBC into Delta tables in lh_bronze.
# Step 2 loads wh_migrated_synapse with T-SQL that reads the lakehouse tables through cross-item queries.
# load_mode: "full" reads all rows (pre-staged), "month" replaces one month, "warehouse_only" skips step 1.

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# PARAMETERS CELL ********************

load_mode = "full"            # "full" | "month" | "warehouse_only"
month_key = 202401            # used when load_mode = "month", format YYYYMM
synapse_host = "__SYNAPSE_HOST__"
synapse_db = "__SYNAPSE_POOL__"
wh_migrated_server = "__WH_MIGRATED_SERVER__"
fact_partitions = 16

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

import notebookutils
from datetime import datetime, timezone

spark.sql("CREATE SCHEMA IF NOT EXISTS bronze")
token = notebookutils.credentials.getToken("https://database.windows.net/")
jdbc_url = (
    f"jdbc:sqlserver://{synapse_host}:1433;database={synapse_db};encrypt=true;"
    "trustServerCertificate=false;hostNameInCertificate=*.sql.azuresynapse.net;loginTimeout=30"
)

def read_synapse(dbtable, **partition_opts):
    reader = (spark.read.format("jdbc")
              .option("url", jdbc_url)
              .option("accessToken", token)
              .option("dbtable", dbtable))
    for k, v in partition_opts.items():
        reader = reader.option(k, v)
    return reader.load()

def run_tsql(server, database, sql_text):
    """Runs T-SQL on a Fabric warehouse via the Microsoft JDBC driver (no connector, no stored secret)."""
    props = sc._gateway.jvm.java.util.Properties()
    props.setProperty("accessToken", token)
    url = f"jdbc:sqlserver://{server}:1433;database={database};encrypt=true;trustServerCertificate=false;loginTimeout=30"
    conn = sc._gateway.jvm.java.sql.DriverManager.getConnection(url, props)
    try:
        stmt = conn.createStatement()
        stmt.execute(sql_text)
        stmt.close()
    finally:
        conn.close()

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

dimensions = ["dim_date", "dim_branch", "dim_customer", "dim_account"]
fact_bounds = dict(partitionColumn="transaction_id", lowerBound="1", upperBound="100000001",
                   numPartitions=str(fact_partitions))

if load_mode == "warehouse_only":
    print("skipping JDBC extract: using existing bronze tables")
elif load_mode == "full":
    for name in dimensions:
        df = read_synapse(f"dbo.{name}")
        df.write.format("delta").mode("overwrite").saveAsTable(f"bronze.synapse_{name}")
        print(f"bronze.synapse_{name}: {df.count()} rows")
    fact = read_synapse("dbo.fact_transaction", **fact_bounds)
    fact.write.format("delta").mode("overwrite").saveAsTable("bronze.synapse_fact_transaction")
    print("bronze.synapse_fact_transaction: full load complete")
elif load_mode == "month":
    month_start, month_end = month_key * 100 + 1, month_key * 100 + 31
    month_query = (f"(SELECT * FROM dbo.fact_transaction "
                   f"WHERE date_key BETWEEN {month_start} AND {month_end}) AS f")
    fact = read_synapse(month_query, **fact_bounds)
    (fact.write.format("delta").mode("overwrite")
         .option("replaceWhere", f"date_key BETWEEN {month_start} AND {month_end}")
         .saveAsTable("bronze.synapse_fact_transaction"))
    print(f"bronze.synapse_fact_transaction: month {month_key} replaced")
else:
    raise ValueError(f"unknown load_mode: {load_mode}")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# Step 2: warehouse load. The lh_bronze SQL endpoint syncs asynchronously, so refresh its metadata first.
# Each table is then truncated and reloaded with INSERT ... SELECT from the lakehouse.
import requests
import time as _time
fabric_token = notebookutils.credentials.getToken("pbi")
_refresh_url = ("https://api.fabric.microsoft.com/v1/workspaces/__WORKSPACE_ID__"
                "/sqlEndpoints/__SQLENDPOINT_ID_LH_BRONZE__/refreshMetadata")
_resp = requests.post(_refresh_url, headers={"Authorization": f"Bearer {fabric_token}"}, json={}, timeout=120)
print("bronze endpoint refreshMetadata status:", _resp.status_code)
if _resp.status_code == 202:
    _op = _resp.headers.get("Location")
    for _ in range(60):
        _time.sleep(10)
        _state = requests.get(_op, headers={"Authorization": f"Bearer {fabric_token}"}, timeout=60).json()
        if _state.get("status") in ("Succeeded", "Failed"):
            print("bronze endpoint refresh:", _state.get("status"))
            break

started = datetime.now(timezone.utc)
warehouse_loads = {
    "dim_date": ("date_key, calendar_date, year_num, quarter_num, month_num, month_name, day_of_week, is_weekend",
                 "bronze.synapse_dim_date"),
    "dim_branch": ("branch_key, branch_code, branch_name, province_code, city",
                   "bronze.synapse_dim_branch"),
    "dim_customer": ("customer_key, customer_id, segment, province_code, age_band, kyc_risk_rating, onboarding_date",
                     "bronze.synapse_dim_customer"),
    "dim_account": ("account_key, account_id, customer_key, product_type, open_date, currency",
                    "bronze.synapse_dim_account"),
    "fact_transaction": ("transaction_id, date_key, account_key, branch_key, channel, txn_type, amount, currency, is_large_cash_flag",
                         "bronze.synapse_fact_transaction"),
}
for table, (cols, source) in warehouse_loads.items():
    run_tsql(wh_migrated_server, "wh_migrated_synapse",
             f"TRUNCATE TABLE dbo.{table}; "
             f"INSERT INTO dbo.{table} ({cols}) SELECT {cols} FROM lh_bronze.{source};")
    print(f"wh_migrated_synapse.dbo.{table} loaded from lh_bronze.{source}")
print(f"warehouse load finished in {(datetime.now(timezone.utc) - started).total_seconds():.0f} s")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
