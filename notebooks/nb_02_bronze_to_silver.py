# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   },
# META   "dependencies": {
# META     "lakehouse": {
# META       "default_lakehouse": "__LAKEHOUSE_ID_SILVER__",
# META       "default_lakehouse_name": "lh_silver",
# META       "default_lakehouse_workspace_id": "__WORKSPACE_ID__"
# META     }
# META   }
# META }

# CELL ********************

# Bronze to Silver (Medallion, silver layer).
# Reads bronze tables through OneLake shortcuts in lh_silver, applies typing, de-duplication and data-quality rules,
# then writes conformed Delta tables. Dimensions use MERGE. The fact table is partitioned by year_month.
# Rejected rows go to silver.dq_rejects (as JSON) and every run is logged to silver.dq_results.
# Each stage is logged to Files/diagnostics/nb02_progress.txt so a failed run shows the exact step.

import os, traceback, contextlib
from datetime import datetime, timezone
from pyspark.sql import functions as F
from delta.tables import DeltaTable

os.makedirs("/lakehouse/default/Files/diagnostics", exist_ok=True)
PROGRESS = "/lakehouse/default/Files/diagnostics/nb02_progress.txt"

def note(msg):
    with open(PROGRESS, "a") as f:
        f.write(msg + "\n")

@contextlib.contextmanager
def stage(name):
    note(f"START {name}")
    try:
        yield
        note(f"OK {name}")
    except Exception as e:
        java_msg = ""
        try:
            java_msg = str(e.java_exception.getMessage())
        except Exception:
            pass
        note(f"FAILED {name}: {repr(e)[:300]}")
        note("JAVA MESSAGE: " + java_msg[:3000])
        raise

spark.sql("CREATE SCHEMA IF NOT EXISTS silver")
run_ts = datetime.now(timezone.utc)
dq_log = []

def log_dq(rule, rows_in, rows_out):
    dq_log.append((run_ts, rule, int(rows_in), int(rows_out), int(rows_in) - int(rows_out)))

def log_rejects(df, rule):
    # Every rejected row is stored as JSON so all rules share one table schema.
    if df.limit(1).count() == 0:
        return
    (df.select(F.lit(rule).alias("rule"), F.lit(run_ts).alias("run_ts"),
               F.to_json(F.struct(*df.columns)).alias("row_json"))
       .write.format("delta").mode("append").saveAsTable("silver.dq_rejects"))

def merge_or_create(table_name, df, key):
    if spark.catalog.tableExists(table_name):
        # Align incoming columns to the target schema, so a column added to the target
        # (for example by a schema-evolution demo) cannot break the MERGE.
        target_types = dict(spark.table(table_name).dtypes)
        for col_name, col_type in target_types.items():
            if col_name not in df.columns:
                df = df.withColumn(col_name, F.lit(None).cast(col_type))
        df = df.select(*list(target_types.keys()))
        (DeltaTable.forName(spark, table_name).alias("t")
            .merge(df.alias("s"), f"t.{key} = s.{key}")
            .whenMatchedUpdateAll()
            .whenNotMatchedInsertAll()
            .execute())
    else:
        df.write.format("delta").saveAsTable(table_name)

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

with stage("customers"):
    src = spark.table("bronze.synapse_dim_customer")
    clean = (src.dropDuplicates(["customer_key"])
                .withColumn("segment", F.trim("segment"))
                .withColumn("province_code", F.upper("province_code"))
                .withColumn("kyc_risk_rating", F.initcap("kyc_risk_rating"))
                .withColumn("_silver_loaded_at", F.lit(run_ts)))
    valid_cond = F.col("customer_key").isNotNull() & F.col("kyc_risk_rating").isin("Low", "Medium", "High")
    valid = clean.filter(valid_cond)
    log_rejects(clean.filter(~valid_cond), "customer_kyc_rating")
    merge_or_create("silver.customers", valid, "customer_key")
    log_dq("customers", src.count(), valid.count())

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

with stage("accounts_and_branches"):
    acc = (spark.table("bronze.synapse_dim_account")
           .dropDuplicates(["account_key"])
           .withColumn("product_type", F.trim("product_type"))
           .withColumn("_silver_loaded_at", F.current_timestamp())
           .localCheckpoint(eager=True))
    merge_or_create("silver.accounts", acc, "account_key")
    log_dq("accounts", spark.table("bronze.synapse_dim_account").count(), acc.count())

    branches = (spark.table("bronze.synapse_dim_branch")
                .dropDuplicates(["branch_key"])
                .withColumn("province_code", F.upper("province_code"))
                .withColumn("_silver_loaded_at", F.current_timestamp())
                .localCheckpoint(eager=True))
    branches.write.format("delta").mode("overwrite").saveAsTable("silver.branches")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

with stage("transactions"):
    fact_src = spark.table("bronze.synapse_fact_transaction")
    fact = (fact_src
            .withColumn("year_month", (F.col("date_key") / 100).cast("int"))
            .withColumn("channel", F.trim("channel"))
            .withColumn("_silver_loaded_at", F.lit(run_ts)))
    fact_cond = ((F.col("amount") >= 0)
                 & F.col("currency").isin("CAD", "USD")
                 & F.col("channel").isin("Branch", "Online", "Mobile", "ATM"))
    fact_ok = fact.filter(fact_cond)
    log_rejects(fact.filter(~fact_cond), "transaction_amount_currency_channel")
    (fact_ok.write.format("delta").mode("overwrite")
            .partitionBy("year_month")
            .saveAsTable("silver.transactions"))
    log_dq("transactions", fact_src.count(), spark.table("silver.transactions").count())

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

with stage("payments"):
    payments = (spark.table("bronze.core_payments")
                .dropDuplicates(["payment_id"])
                .withColumn("payment_status", F.initcap("payment_status"))
                .withColumn("_silver_loaded_at", F.lit(run_ts)))
    merge_or_create("silver.payments", payments, "payment_id")
    log_dq("payments", spark.table("bronze.core_payments").count(), payments.count())

with stage("dq_results"):
    dq_df = spark.createDataFrame(dq_log, "run_ts timestamp, dataset string, rows_in long, rows_out long, rows_rejected long")
    dq_df.write.format("delta").mode("append").saveAsTable("silver.dq_results")
    print("silver layer complete")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
