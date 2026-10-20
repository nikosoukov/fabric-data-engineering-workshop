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

# Silver to Gold (Medallion, warehouse layer).
# The gold star schema is built by a T-SQL stored procedure in wh_gold (gold.usp_load_gold) that reads
# silver Delta tables in lh_silver through cross-item queries. This notebook only triggers it, so analysts
# query the same T-SQL engine and BI tools connect to one warehouse.

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# PARAMETERS CELL ********************

wh_gold_server = "__WH_GOLD_SERVER__"

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

import notebookutils
import requests
import time
from datetime import datetime, timezone

token = notebookutils.credentials.getToken("https://database.windows.net/")
fabric_token = notebookutils.credentials.getToken("pbi")
workspace_id = "__WORKSPACE_ID__"
silver_sql_endpoint_id = "__SQLENDPOINT_ID_LH_SILVER__"

# The warehouse reads lh_silver through its SQL analytics endpoint, which syncs asynchronously.
# Refresh the endpoint metadata before the gold load so new silver tables are visible.
refresh_url = f"https://api.fabric.microsoft.com/v1/workspaces/{workspace_id}/sqlEndpoints/{silver_sql_endpoint_id}/refreshMetadata"
resp = requests.post(refresh_url, headers={"Authorization": f"Bearer {fabric_token}"}, json={}, timeout=120)
print("refreshMetadata status:", resp.status_code)
if resp.status_code == 202:
    op = resp.headers.get("Location")
    for _ in range(40):
        time.sleep(10)
        state = requests.get(op, headers={"Authorization": f"Bearer {fabric_token}"}, timeout=60).json()
        if state.get("status") in ("Succeeded", "Failed"):
            print("refreshMetadata:", state.get("status"))
            break

def run_tsql(server, database, sql_text):
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

# Retry while the endpoint finishes syncing (typically a minute or two after a silver write).
started = datetime.now(timezone.utc)
for attempt in range(1, 6):
    try:
        run_tsql(wh_gold_server, "wh_gold", "EXEC gold.usp_load_gold")
        print(f"gold.usp_load_gold succeeded on attempt {attempt}")
        break
    except Exception as e:
        print(f"attempt {attempt} failed: {str(e)[:200]}")
        if attempt == 5:
            raise
        time.sleep(60)
print(f"gold load finished in {(datetime.now(timezone.utc) - started).total_seconds():.0f} s")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
