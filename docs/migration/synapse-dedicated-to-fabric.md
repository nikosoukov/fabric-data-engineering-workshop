# Migration runbook: Synapse dedicated SQL pool to Fabric Warehouse

This runbook documents the migration that the workshop demonstrates, with the production variants next to it.
Official guidance: *Migration methods for Azure Synapse Analytics dedicated SQL pools to Fabric Data Warehouse*
on Microsoft Learn, and the Fabric Migration Assistant for Data Warehouse.

## 1. Choose a path

| Path | When to use it | Requirements | In this workshop |
|---|---|---|---|
| Fabric Migration Assistant for Data Warehouse | Automated schema and data migration from a connected dedicated pool | Connection to the source, Fabric portal | Documented. Not scripted (portal-driven). |
| Data Factory Copy activity with ADLS staging | Large tables, managed copy, partitioned reads | ADLS Gen2 staging account reachable from Fabric and Synapse | Documented. Blocked in the sandbox (storage public access disabled by policy). |
| CETAS to ADLS, then COPY INTO | High throughput export and load | ADLS Gen2 reachable, storage RBAC | Documented. Same blocker. |
| **Spark JDBC read, Delta landing, T-SQL load** | Networks without ADLS staging. Full control of parallelism and transforms | Synapse reachable over the network, Entra token | **Used.** Scripted in `notebooks/nb_01_synapse_migration.py`. |
| SQL Database Projects (VS Code) | Schema-as-code migration | Visual Studio Code extension | Documented. |
| dbt | Teams that already use dbt | dbt Fabric adapter | Documented. |

## 2. Inventory

| Source object (Synapse) | Rows | Distribution | Target (Fabric) |
|---|---|---|---|
| `dbo.dim_date` | 1,096 | Replicate | `wh_migrated_synapse.dbo.dim_date` |
| `dbo.dim_branch` | 200 | Replicate | `wh_migrated_synapse.dbo.dim_branch` |
| `dbo.dim_customer` | 50,000 | Replicate | `wh_migrated_synapse.dbo.dim_customer` |
| `dbo.dim_account` | 80,000 | Hash(account_key) | `wh_migrated_synapse.dbo.dim_account` |
| `dbo.fact_transaction` | 100,000,000 | Hash(account_key), CCI | `wh_migrated_synapse.dbo.fact_transaction` |

The fact table is about 10 GB as CSV-equivalent (100M rows at roughly 100 bytes each). Measure the real size on your
own data with `sp_spaceused` or `sys.dm_pdw_nodes_db_partition_stats`.

## 3. DDL conversion

The source DDL is `sql/synapse/01_create_source_schema.sql`. The target is `sql/fabric-warehouse/01_create_migrated_schema.sql`.

| Synapse construct | Fabric Warehouse | Rule |
|---|---|---|
| `WITH (DISTRIBUTION = REPLICATE \| HASH(col) \| ROUND_ROBIN)` | Removed | Fabric manages data layout. |
| `WITH (CLUSTERED COLUMNSTORE INDEX)` | Removed | Fabric manages storage format. |
| `CONSTRAINT pk PRIMARY KEY NONCLUSTERED (col) NOT ENFORCED` in CREATE TABLE | `ALTER TABLE ... ADD CONSTRAINT pk PRIMARY KEY NONCLUSTERED (col) NOT ENFORCED` | Not allowed in CREATE TABLE in Fabric Warehouse. |
| `TINYINT` | `SMALLINT` | Not supported in Fabric Warehouse. |
| `DECIMAL`, `VARCHAR`, `CHAR`, `DATE`, `BIT`, `BIGINT`, `INT` | Unchanged | Supported. |

Check other objects against the T-SQL surface area page before migrating a real environment. Materialized views,
triggers, synonyms, `BULK LOAD`, and `CREATE USER` are not supported in Fabric Warehouse.

## 4. Extract and land (Spark JDBC)

`notebooks/nb_01_synapse_migration.py` does the following.

1. Gets an Entra token with `notebookutils.credentials.getToken("https://database.windows.net/")`.
2. Reads each dimension in one JDBC query and writes Delta to `lh_bronze.bronze.synapse_<table>`.
3. Reads `fact_transaction` in 16 parallel partitions on `transaction_id` (`partitionColumn`, `lowerBound`,
   `upperBound`, `numPartitions`). The partition column must be numeric and evenly distributed.
4. Supports `load_mode = "month"`. It replaces one `date_key` range with Delta `replaceWhere`, for incremental loads.

## 5. Load the warehouse (T-SQL, cross-item)

For each table the notebook runs, through the Microsoft JDBC driver on the warehouse endpoint:

```sql
TRUNCATE TABLE dbo.<table>;
INSERT INTO dbo.<table> (<columns>) SELECT <columns> FROM lh_bronze.bronze.synapse_<table>;
```

Before this step, the notebook calls the lakehouse SQL endpoint `refreshMetadata` API. Without that refresh the
warehouse read stale data. We observed this: after regenerating the source, the warehouse still had the old values
until the endpoint synced.

## 6. Reconcile

Run these checks on both sides before cutover.

| Check | Synapse | Fabric |
|---|---|---|
| Row count, `fact_transaction` | `SELECT COUNT_BIG(*) FROM dbo.fact_transaction` | Same query on `wh_migrated_synapse` |
| Control total, amount | `SELECT SUM(amount) FROM dbo.fact_transaction` | Same |
| Business flag count | `SUM(CAST(is_large_cash_flag AS INT))` | Same |
| Dimension counts | `COUNT_BIG(*)` per dimension | Same |

In our run, every check matched: 100,000,000 rows, 2,000,000 flagged rows, and a total of 284,999,500,000.00.

## 7. Production changes

- **Staging and throughput.** For very large tables, use the Data Factory Copy activity with ADLS staging and
  partitioned source reads, or CETAS to ADLS followed by COPY INTO. These are faster than JDBC for multi-terabyte
  tables. Size the Synapse pool for the concurrency that partitioned reads need. DW100c has few concurrency slots,
  so partitions queue.
- **Network.** Replace the "Allow Azure services" firewall rule with private endpoints or a managed virtual
  network. Use an Entra group for SQL access, not a shared login.
- **Schedule.** Run the Silver and Gold layers from the Medallion pipeline. Use the migration pipeline only for the
  cutover and for historical reloads.
- **Cutover.** Keep the Synapse pool read-only during the final sync. Run the reconciliation again, then switch
  reports and consumers. Pause, and later decommission, the pool.
- **Governance.** Record the sign-off for each control total in your change record, for example for OSFI-regulated
  change management.

## 8. Known issues and fixes (from this workshop)

| Symptom | Cause | Fix |
|---|---|---|
| `PRIMARY KEY keyword is not supported in the CREATE TABLE statement` | Fabric Warehouse rule | Add the PK with ALTER TABLE, `NOT ENFORCED`. |
| `tinyint ... not supported` | Fabric Warehouse rule | Use `SMALLINT`. |
| Notebook session cancelled after statements fail, with no detail | Unhandled exception in a cell | Wrap steps in a stage logger that writes the Java message to a file. |
| `Invalid object name 'lh_silver.silver.branches'` from the warehouse | SQL endpoint not synced | Call `refreshMetadata`, then retry. |
| Plan validation error in `saveAsTable` (`CollapseProject`) | Observed on the Fabric Spark runtime when the silver step used `exceptAll` and tz-aware `lit(datetime)` columns. Root cause not confirmed | Replace `exceptAll` and `left_anti` with filters on the same predicate, use `F.current_timestamp()`, and add `localCheckpoint(eager=True)`. The notebook now passes. |
| `cannot resolve risk_band in UPDATE clause` in MERGE | A demo added a column to a production table | Align incoming columns to the target schema, and run demos on a copy. |
| Synapse connection refused (firewall) | Egress IP not allowed | Allow Azure services, or add the client IP. |
