# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   },
# META   "dependencies": {
# META     "lakehouse": {
# META       "default_lakehouse": "1cbc6d83-4d4f-48c2-94c6-65a63649c874",
# META       "default_lakehouse_name": "lh_silver",
# META       "default_lakehouse_workspace_id": "fc81cb6f-87c4-40ce-a259-ecda4cbe7563"
# META     }
# META   }
# META }

# CELL ********************

# Delta Lake deep dive (Lakehouse, Spark, Delta segment).
# All writes go to silver.demo_customers, a scratch copy of silver.customers, so the production table and the
# daily pipeline are never affected. Every step runs in seconds during a live session.
# Shows: transaction history, time travel, MERGE with update and delete, schema evolution, OPTIMIZE, and VACUUM.

from delta.tables import DeltaTable
from pyspark.sql import functions as F

spark.sql("CREATE SCHEMA IF NOT EXISTS silver")
spark.sql("CREATE OR REPLACE TABLE silver.demo_customers AS SELECT * FROM silver.customers")
print("scratch copy ready:", spark.table("silver.demo_customers").count(), "rows")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# 1. Delta transaction log: every write is a numbered version.
spark.sql("DESCRIBE HISTORY silver.demo_customers") \
     .select("version", "timestamp", "operation") \
     .show(5, truncate=False)

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# 2. Time travel: read the table as of version 0 (the copy made above).
v0_count = spark.read.option("versionAsOf", 0).table("silver.demo_customers").count()
current_count = spark.table("silver.demo_customers").count()
print(f"rows at version 0: {v0_count} | current rows: {current_count}")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# 3. MERGE with an update and a delete on a small change set (simulates a daily CDC feed).
changes = spark.createDataFrame(
    [(1, "High", None),
     (2, None, "DELETE")],
    "customer_key int, kyc_risk_rating string, op string")

target = DeltaTable.forName(spark, "silver.demo_customers")
(target.alias("t")
    .merge(changes.alias("s"), "t.customer_key = s.customer_key")
    .whenMatchedDelete(condition="s.op = 'DELETE'")
    .whenMatchedUpdate(set={"kyc_risk_rating": "s.kyc_risk_rating"})
    .execute())
print("MERGE applied. Latest operation:",
      spark.sql("DESCRIBE HISTORY silver.demo_customers").select("operation").first()[0])

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# 4. Schema evolution: append a derived column with mergeSchema. Only the scratch table changes.
enriched = (spark.table("silver.demo_customers").limit(100)
            .withColumn("risk_band", F.when(F.col("kyc_risk_rating") == "High", "Enhanced")
                                      .otherwise("Standard")))
(enriched.write.format("delta").mode("append")
         .option("mergeSchema", "true")
         .saveAsTable("silver.demo_customers"))
print("columns now:", spark.table("silver.demo_customers").columns)

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# 5. Maintenance: compact small files with OPTIMIZE and preview VACUUM before deleting anything.
spark.sql("OPTIMIZE silver.demo_customers ZORDER BY (province_code)").show(truncate=False)
spark.sql("VACUUM silver.demo_customers RETAIN 168 HOURS DRY RUN").show(truncate=False)
print(spark.sql("DESCRIBE DETAIL silver.demo_customers").select("numFiles", "sizeInBytes").first())

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
