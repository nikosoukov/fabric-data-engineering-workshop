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

# Maintenance: rebuild silver.customers from bronze.
# Use this when a silver dimension has drifted (for example duplicate keys or columns added by a demo).
# A MERGE keeps existing rows, so a rebuild is the clean fix. It deduplicates, applies the same rules as
# nb_02_bronze_to_silver, and overwrites the table with the bronze definition.

from pyspark.sql import functions as F

src = spark.table("bronze.synapse_dim_customer")
clean = (src.dropDuplicates(["customer_key"])
            .withColumn("segment", F.trim("segment"))
            .withColumn("province_code", F.upper("province_code"))
            .withColumn("kyc_risk_rating", F.initcap("kyc_risk_rating"))
            .withColumn("_silver_loaded_at", F.current_timestamp()))
valid = clean.filter(F.col("customer_key").isNotNull() & F.col("kyc_risk_rating").isin("Low", "Medium", "High"))
(valid.write.format("delta").mode("overwrite")
      .option("overwriteSchema", "true")
      .saveAsTable("silver.customers"))
print("silver.customers rebuilt:", spark.table("silver.customers").count(), "rows,",
      spark.table("silver.customers").select("customer_key").distinct().count(), "distinct keys")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
