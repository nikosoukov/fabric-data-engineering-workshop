# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   },
# META   "dependencies": {
# META     "lakehouse": {
# META       "default_lakehouse": "33719262-16d1-4f9b-9cc0-c033773e221e",
# META       "default_lakehouse_name": "lh_bronze",
# META       "default_lakehouse_workspace_id": "fc81cb6f-87c4-40ce-a259-ecda4cbe7563"
# META     }
# META   }
# META }

# CELL ********************

import os
os.makedirs("/lakehouse/default/Files/diagnostics", exist_ok=True)
report = []

try:
    spark.sql("CREATE SCHEMA IF NOT EXISTS bronze")
    report.append("CREATE SCHEMA bronze OK")
except Exception as e:
    report.append("CREATE SCHEMA FAILED: " + repr(e)[:800])

try:
    import notebookutils as _nu
    _tok = _nu.credentials.getToken("https://database.windows.net/")
    report.append(f"getToken OK, length {len(_tok)}")
except Exception as e:
    report.append("getToken FAILED: " + repr(e)[:800])

sql_token = None
try:
    from azure.identity import DefaultAzureCredential
    sql_token = DefaultAzureCredential().get_token("https://database.windows.net/.default").token
    report.append(f"DefaultAzureCredential OK, token length {len(sql_token)}")
except Exception as e:
    report.append("DefaultAzureCredential FAILED: " + repr(e)[:800])

try:
    import notebookutils
    tok2 = notebookutils.credentials.getToken("https://database.windows.net/")
    report.append(f"notebookutils.getToken(raw sql resource) OK, length {len(tok2)}")
    if sql_token is None:
        sql_token = tok2
except Exception as e:
    report.append("notebookutils.getToken(raw sql resource) FAILED: " + repr(e)[:800])

if sql_token:
    try:
        jdbc_url = ("jdbc:sqlserver://syn-fdw-osfi-2610.sql.azuresynapse.net:1433;"
                    "database=dwpool;encrypt=true;trustServerCertificate=false;"
                    "hostNameInCertificate=*.sql.azuresynapse.net;loginTimeout=30")
        rows = (spark.read.format("jdbc").option("url", jdbc_url)
                .option("query", "SELECT COUNT_BIG(*) AS fact_rows FROM dbo.fact_transaction")
                .option("accessToken", sql_token).load().collect())
        report.append(f"JDBC to Synapse OK, fact_rows={rows[0][0]}")
    except Exception as e:
        report.append("JDBC FAILED: " + repr(e)[:1200])

def run_tsql(server, database, sql_text):
    """Executes T-SQL on a Fabric warehouse with the Microsoft JDBC driver and the notebook's Entra token."""
    props = sc._gateway.jvm.java.util.Properties()
    props.setProperty("accessToken", sql_token_wh)
    url = f"jdbc:sqlserver://{server}:1433;database={database};encrypt=true;trustServerCertificate=false;loginTimeout=30"
    conn = sc._gateway.jvm.java.sql.DriverManager.getConnection(url, props)
    try:
        stmt = conn.createStatement()
        has_rs = stmt.execute(sql_text)
        result = None
        if has_rs:
            rs = stmt.getResultSet()
            if rs.next():
                result = rs.getLong(1)
        stmt.close()
        return result
    finally:
        conn.close()

try:
    sql_token_wh = notebookutils.credentials.getToken("https://database.windows.net/")
    n = run_tsql("lgnbzlcthzyupkodx7ryr4kvoi-n7fyd7geq7hebisz5tnezptvmm.datawarehouse.fabric.microsoft.com", "wh_migrated_synapse",
                 "SELECT COUNT_BIG(*) FROM lh_bronze.bronze.synapse_dim_customer")
    report.append(f"T-SQL cross-item query OK, lakehouse dim_customer rows={n}")
    run_tsql("lgnbzlcthzyupkodx7ryr4kvoi-n7fyd7geq7hebisz5tnezptvmm.datawarehouse.fabric.microsoft.com", "wh_migrated_synapse",
             "IF OBJECT_ID('dbo.zz_connector_probe') IS NOT NULL DROP TABLE dbo.zz_connector_probe")
    report.append("T-SQL DDL via JDBC OK")
except Exception as e:
    report.append("T-SQL via JDBC FAILED: " + repr(e)[:1500])

with open("/lakehouse/default/Files/diagnostics/connectivity.txt", "w") as f:
    f.write("\n".join(report))
print("\n".join(report))

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
