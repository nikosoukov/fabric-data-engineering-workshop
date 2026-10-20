# Synapse equivalents in Microsoft Fabric

Use this table when someone asks "what replaces X?". Each row is either verified in this workshop (marked **Tested**)
or taken from Microsoft Learn guidance (marked **Docs**). Check the docs for the current release before a session.

| Azure Synapse Analytics | Microsoft Fabric | Status | Notes for data engineers |
|---|---|---|---|
| Dedicated SQL pool (DWU) | Warehouse on a Fabric capacity (F SKU) | **Tested** (migration) | No distribution keys or columnstore clauses in DDL. Fabric manages layout. Capacity units replace DWU sizing. |
| Dedicated SQL pool `DISTRIBUTION`, `CLUSTERED COLUMNSTORE INDEX` | Not used | **Tested** | Remove these clauses when converting DDL. |
| Dedicated SQL pool `PRIMARY KEY ... NOT ENFORCED` in `CREATE TABLE` | `ALTER TABLE ... ADD CONSTRAINT ... PRIMARY KEY NONCLUSTERED ... NOT ENFORCED` | **Tested** | Fabric Warehouse rejects PK in `CREATE TABLE`. Add it with ALTER TABLE. |
| `TINYINT` | `SMALLINT` | **Tested** | Fabric Warehouse does not support `TINYINT`. |
| Serverless SQL pool | SQL analytics endpoint of a Lakehouse (read-only T-SQL) and Warehouse | **Docs** | Use the endpoint for T-SQL reads over Delta. Writes go through Spark or the Warehouse. |
| Apache Spark pool | Spark in Fabric (Lakehouse, notebooks, Spark job definitions) | **Tested** | Delta is the default table format. |
| Synapse notebooks | Fabric notebooks (`.py` in Git format) | **Tested** | `notebookutils` replaces `mssparkutils` for credentials and file access. |
| Synapse pipelines | Fabric Data Factory pipelines (`TridentNotebook`, `RefreshDataFlow`, copy, script) | **Tested** (notebook, dataflow) | Pipeline JSON is close to Synapse and ADF. Notebook and dataflow activities are tested. |
| Mapping data flows | Dataflow Gen2 (Power Query M) | **Tested** (create, refresh) | Dataflow Gen2 is the recommended low-code transform. Destinations are configured in the editor. |
| ADLS Gen2 linked services | OneLake (`Files`, `Tables`) and OneLake shortcuts | **Tested** (OneLake shortcuts) | Shortcuts point at external ADLS Gen2 or S3, or at other Fabric items, without copying data. |
| Synapse Link for Azure SQL or Cosmos DB | Mirroring | **Tested** (Fabric SQL database replica in OneLake) | Mirroring replicates source tables into OneLake as Delta. External source mirroring needs a reachable source. |
| Synapse Link for Dataverse | Fabric Link | **Docs** | Dataverse data to OneLake. |
| Azure Data Explorer in Synapse | Real-Time Intelligence (Eventhouse, KQL database) | **Docs** | Streaming and telemetry analytics with KQL. |
| Synapse Studio | Fabric portal (workspaces, capacity settings, monitoring hub) | **Tested** | |
| Synapse workspace (RBAC, managed VNet) | Fabric workspace roles, capacity admins, private links | **Docs** | Capacity admins are UPNs in the tenant (object IDs are rejected). |
| Synapse Git integration | Fabric Git integration (GitHub or Azure DevOps) | **Tested** (GitHub connection, connect, commit) | Connect Dev to a folder in the repo. Commit from the workspace or by API. |
| Synapse deployment (ARM, manual) | Fabric deployment pipelines (Dev, Test, Prod) | **Tested** (Dev to Test) | Deployment pipelines rebind notebook references in pipelines. They do not move data. |
| Workload management, resource classes | Capacity throttling and smoothing | **Docs** | Track utilization in the Fabric Capacity Metrics app. |
| Materialized views (dedicated pool) | Not supported in Fabric Warehouse | **Docs** | Use tables built by a pipeline or views. |
| `BULK LOAD` (dedicated pool) | `COPY INTO` (preview `bcp`) | **Docs** | Check the T-SQL surface area page for the current list. |
| Synapse PolyBase external tables | Shortcuts (lakehouse) and `COPY INTO` | **Docs** | Prefer shortcuts for data that stays where it is. |

## Behaviour that trips people up

- In the Synapse dedicated pool, `FROM (VALUES ...)` inside a CTAS and multi-row `INSERT ... VALUES` both failed with
  syntax errors. The generator uses `INSERT ... SELECT ... UNION ALL` instead.
- Fabric Warehouse reads a lakehouse table through the lakehouse SQL endpoint. That endpoint syncs asynchronously.
  Call `refreshMetadata` before a cross-item query in a load job.
- A notebook that starts with a markdown cell can lose its default-lakehouse binding when uploaded. Start with a code cell.
