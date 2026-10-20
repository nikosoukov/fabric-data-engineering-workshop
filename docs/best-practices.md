# Best practices: Medallion architecture with a Lakehouse and a Warehouse in Microsoft Fabric

Architecture Medallion : Lakehouse + Warehouse dans Microsoft Fabric (bonnes pratiques)

These practices come from the workshop build and from Microsoft Learn guidance. Items marked **Tested** were verified
in this environment. Re-check the Learn pages for your release, because Fabric features change often.

Reference diagram: [diagrams/medallion-architecture.svg](../diagrams/medallion-architecture.svg).

## 1. Architecture

- **Use Medallion layers with clear contracts.** Bronze keeps data as received. Silver holds conformed, validated
  data. Gold holds business-ready models. Write the contract for each layer (grain, keys, quality rules, owner).
- **Lakehouse for bronze and silver, Warehouse for gold.** Data engineers use Spark and Python in the Lakehouse.
  Analysts and BI use T-SQL on a Warehouse. **Tested**.
- **Shortcuts instead of copies.** Read other Fabric items and external storage through OneLake shortcuts.
  Copy data only when the consumer needs a different engine or format. **Tested** (lakehouse to lakehouse, and
  lakehouse to a Fabric SQL database mirror).
- **Separate workspaces per environment** (Dev, Test, Prod) and per domain for large estates. Connect only Dev to Git.
- **Name items by layer and type.** Examples used here: `lh_bronze`, `lh_silver`, `wh_gold`, `nb_02_bronze_to_silver`,
  `pl_medallion_daily`, `df_province_reference`, `dp_fdw_osfi`.

## 2. Capacity and cost

- **Size the F SKU for peak concurrency**, not average use. A Spark job with 100M rows needs more capacity than a
  Warehouse query on aggregates. Monitor with the Fabric Capacity Metrics app.
- **Separate capacities for production and non-production** when workloads or budgets differ. Use the same region
  everywhere for residency.
- **Pause or scale down** development capacity outside working hours. **Tested** (the workshop has pause and resume
  scripts for the pool and the capacity).
- **Pause pools and idle compute** when not used. A DW100c dedicated pool bills while running.

## 3. Delta and Spark

- **Partition large fact tables by a low-cardinality date key** such as `year_month`. This made month-level replace
  (`replaceWhere`) possible. **Tested**.
- **Use MERGE for dimensions and keyed entities.** Make sure the source is de-duplicated on the business key first.
  **Tested**.
- **Make schema changes deliberately.** Use `mergeSchema` in landing or demo tables. In silver, align incoming
  columns to the target before a MERGE. Otherwise a single added column breaks the pipeline. **Tested** (this failure
  happened in the workshop when a demo changed a production table).
- **Compact and clean up.** Run `OPTIMIZE` (with `ZORDER` on common filter columns) after large loads. Run `VACUUM`
  with `DRY RUN` first and keep the retention period you need for time travel and audit. **Tested** (dry run).
- **Start notebooks with a code cell.** A markdown first cell lost the lakehouse binding on upload. **Tested**.
- **Log every stage.** A failed Spark session shows only "statements failed". Write each stage's status and the Java
  exception message to a file (or to a log table) so the failure is visible. **Tested**.
- **Avoid fragile plan patterns on your runtime.** On the Fabric Spark runtime used here, `exceptAll` and `left_anti`
  in the silver step failed during `saveAsTable`. Filters on the same predicate and `localCheckpoint` worked. Test
  your transforms on the runtime you deploy.

## 4. Data quality

- **Validate in silver, not in gold.** Typing, null checks, domain checks (for example KYC rating values), and
  currency and channel checks happen before the warehouse sees data. **Tested**.
- **Quarantine rejected rows.** Store rejects with the rule name and the row as JSON (`silver.dq_rejects`). Keep a run
  log with rows in, rows out, and rows rejected (`silver.dq_results`). **Tested**.
- **Reconcile with control totals.** Row counts, sums, and flag counts should match between source, bronze, silver,
  and gold. In this workshop the totals matched across Synapse, the migrated warehouse, and gold.
- **Decide fail or warn thresholds up front** and record them in the data contract.

## 5. Warehouse and T-SQL

- **Use cross-item queries for loads when the data is in the same workspace.** `INSERT ... SELECT` from a lakehouse
  table works. **Tested**. Refresh the lakehouse SQL endpoint metadata before the query, because the endpoint syncs
  asynchronously. **Tested** (stale reads before refresh).
- **Put load logic in stored procedures** (for example `gold.usp_load_gold`) and call them from a pipeline or notebook.
  Use `TRUNCATE` and reload for small gold tables, and MERGE where history matters. **Tested**.
- **Respect Fabric Warehouse limits.** No `TINYINT`. No primary key in `CREATE TABLE` (add it with ALTER TABLE as
  `NOT ENFORCED`). No materialized views, triggers, or synonyms. Check the T-SQL surface area page. **Tested** for the
  first three.
- **Reporting views in the warehouse** keep BI definitions in one place. **Tested**.

## 6. Pipelines

- **Orchestrate with pipelines, compute in notebooks or dataflows.** Keep each activity small and idempotent.
- **Use dependency conditions** and retries for transient failures. Use `replaceWhere` or `TRUNCATE` so reruns are safe.
- **Parameterize** the environment-specific values (for example `load_mode`, `month_key`). **Tested**.
- **Monitor runs** in the monitoring hub, and alert on failures.

## 7. Security and governance

- **Least privilege by workspace role.** Use Entra groups, not individual users. Viewers consume, Contributors build,
  Admins manage. Use item-level sharing for consumers.
- **Use managed identities and Entra tokens.** Do not store passwords or keys in notebooks or the repository. The
  workshop uses `notebookutils` tokens and `az login`. **Tested**. `DefaultAzureCredential` did not work inside Fabric
  notebooks.
- **Protect sensitive data in the warehouse** with row-level security and column-level security, and label datasets
  with sensitivity labels. Confirm which controls apply to your data classification.
- **Restrict network paths.** The workshop allows Azure services on the Synapse firewall so Fabric Spark can connect.
  For production use private endpoints, managed virtual networks, and approved outbound paths. **Tested** (the
  sandbox policy disabled public access on storage and Azure SQL).
- **Keep data in the right region.** Capacity region determines where OneLake data is stored. Use Canada Central or
  Canada East when data residency applies. **Tested** (F4 in Canada Central).
- **Audit.** Keep the admin, workspace, and item activity logs. Keep Git history for every change to items.

## 8. Git and deployment

- **Connect only Dev to Git.** Use a folder per workspace (for example `fabric-workspace/`). **Tested** (GitHub
  connection, connect, initialize, commit by API).
- **Promote with deployment pipelines** (Dev, Test, Prod). They rebind notebook references in pipelines to the target
  workspace items. **Tested** (Dev to Test).
- **Deployment moves definitions, not data.** Lakehouses and warehouses deploy empty. Plan a data load in Test and
  Prod (for example run the migration or the Medallion pipeline after deployment). **Tested** (the lakehouses in Test
  were empty after deployment).
- **Use deployment rules** for values that differ by environment (connection strings, lakehouse IDs, parameters).
- **Keep scripts idempotent** and store them in the repository. Treat the repository as the record of how the
  environment is built. **Tested** (every deploy script reruns safely).
- **Require review and approval** for the Test to Prod step.

## 9. Testing

- Test transforms with small local or sample data before a full run. The workshop's Delta demo uses a scratch copy.
- Keep a reconciliation query for each gold table, and run it after every load.
- Run the connectivity check notebook (`nb_00_connectivity_check`) before a session.

## 10. Regulated-industry notes (for example OSFI)

These points help start the conversation with your compliance and resilience teams. They are not a compliance
assessment. Confirm current requirements with your second line and with OSFI guidance.

- **Third-party risk.** Cloud and SaaS use falls under third-party risk management expectations (OSFI Guideline B-10).
  Document the service, its data, its location, and the exit plan.
- **Technology and cyber risk.** Access control, logging, change management, and resilience apply (OSFI Guideline B-13).
- **Operational resilience.** Map critical operations, impact tolerances, and recovery. A single capacity region is a
  resilience decision to record (OSFI Guideline E-21).
- **Data residency and sovereignty.** Keep capacity and storage in Canada. Record the region in the design.
- **Model and data lineage.** Keep notebooks, pipelines, and definitions in Git. Use Delta history and the run logs
  as audit evidence.
- **Synthetic data only in workshops.** Never load production or customer data into training or demo environments.
