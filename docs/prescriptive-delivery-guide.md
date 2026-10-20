# Prescriptive delivery guide: Fabric for Data Engineers (2-hour workshop)

Guide de prestation : Fabric pour ingénieurs de données (atelier de 2 heures)

This guide tells a presenter or Solution Engineer how to deliver the workshop, step by step, with the
environment already deployed by [scripts/deploy-all.ps1](../scripts/deploy-all.ps1). It assumes no prior
knowledge of this build. Read sections 1, 2, and 4 before the first session.

## 1. Session design

| Block | Minutes | Content | Owner |
|---|---|---|---|
| Welcome and objectives | 5 | Goals, the synthetic data disclaimer, the environment check | Presenter |
| Slides | 30 | Concepts from the Seismic deck (see section 3) | Presenter |
| Demo 1: Pipelines and Dataflows | 10 | Pipeline run, dataflow, orchestration | Presenter |
| Demo 2: Lakehouse, Spark, Delta, Notebooks | 15 | Delta history, time travel, MERGE, schema evolution, OPTIMIZE and VACUUM | Presenter |
| Demo 3: Warehouse and T-SQL | 10 | Reporting views, cross-item query, stored procedure, T-SQL limits | Presenter |
| Demo 4: Synapse equivalents and migration | 12 | Synapse source, migration pipeline, DDL conversion, reconciliation | Presenter |
| Demo 5: Shortcuts and mirroring | 8 | OneLake shortcuts, Fabric SQL database mirror | Presenter |
| Demo 6: Medallion patterns | 10 | Pipeline run history, data-quality logs, gold views, architecture diagram | Presenter |
| Demo 7: Git and deployment | 10 | Git integration, deployment pipeline, Dev to Test | Presenter |
| Questions and close | 10 | Q&A, next steps, feedback | Presenter |
| **Total** | **120** | Demo time is 75 minutes (within 70 to 80) | |

Keep 10 minutes in reserve. If a demo runs long, use the reserve in Q&A, not in the demos.

## 2. Pre-session checklist

Do these steps in order. Each one has a check, so you can tell whether it worked.

**Seven days before**

1. Confirm the environment still exists: `pwsh ./scripts/pause-resume.ps1 -Action Resume`, then check that the pool is
   `Online` and the capacity is `Active`. Pause it again afterwards.
2. Confirm the Git connection and the deployment pipeline are present in the Fabric portal (Dev workspace settings, and
   the `dp_fdw_osfi` pipeline).
3. Re-run the source checks in section 6.3 (row counts and control totals).

**One day before**

4. Resume the environment (step 1 above). Wait about 5 minutes for the pool to come online.
5. Run `reset-demo.ps1` to return the migrated warehouse to a known state.
6. Run `pl_medallion_daily` from the Dev workspace so the run history shows a fresh run on the day.
7. Run notebook `nb_00_connectivity_check`. Check the output file for `JDBC to Synapse OK`, `T-SQL cross-item query OK`,
   and `T-SQL DDL via JDBC OK`.
8. Confirm your client IP is allowed on the Synapse firewall, if you are on a different network. Use
   `scripts/01-deploy-azure.ps1 -ClientIp <your-ip>`.

**Thirty minutes before**

9. Open these browser tabs: Fabric portal (`FDW-Dev-OSFI-2610`), the GitHub repository, the Synapse pool in the Azure
   portal, and this guide.
10. Confirm you are signed in to the Fabric tenant that owns the capacity. Check `az account show`.
11. Close the Test workspace tab unless you are showing deployments.

## 3. Slide-to-demo mapping

Your slides come from Seismic. Insert the slide numbers in the right-hand column before you present.

| Agenda topic | Slide reference (fill in) | Demo that follows |
|---|---|---|
| Pipelines and Dataflows | Slides __ to __ | Demo 1 |
| Lakehouse, Spark, Delta | Slides __ to __ | Demo 2 |
| Warehouse and T-SQL | Slides __ to __ | Demo 3 |
| Synapse equivalents | Slides __ to __ (use [docs/synapse-equivalents.md](synapse-equivalents.md)) | Demo 4 |
| Shortcuts and mirroring | Slides __ to __ | Demo 5 |
| Medallion patterns | Slides __ to __ (use [diagrams/medallion-architecture.svg](../diagrams/medallion-architecture.svg)) | Demo 6 |
| Notebooks | Slides __ to __ | Demo 2 |
| Git and deployment | Slides __ to __ | Demo 7 |

## 4. Demo run-of-show

Each demo lists the goal, the steps, the expected result, what to say, and a fallback. Items are in the Fabric
workspace **FDW-Dev-OSFI-2610** unless stated otherwise.

### Demo 1: Pipelines and Dataflows (10 min)

**Goal.** Show orchestration with pipelines and a low-code dataflow.

1. Open `pl_medallion_daily`. Point to the three activities and their dependencies: the dataflow refresh, then
   `Bronze to Silver`, then `Silver to Gold`.
2. Open the run history. The most recent run should show `Completed`. Open the run to show each activity's duration.
3. Open `df_province_reference` in the Dataflow Gen2 editor. Show the `#table` input, the type change, and the sort.
   Explain that the destination is set in the editor. Do not change anything.
4. Show the pipeline JSON if the audience wants definitions: the Fabric Git folder `fabric-workspace/` or the repo's
   `pipelines/pl_medallion_daily.json`.

**Expected result.** `pl_medallion_daily` shows `Completed`. The dataflow activity shows `Succeeded`.

**What to say.** Pipelines coordinate. Compute happens in notebooks, dataflows, or the warehouse. Dataflow Gen2 suits
reference data and light transforms.

**Fallback.** If the run history is empty, start the pipeline from the item's Run menu and cut to the completed run from
the day before. Mention that the run takes about 7 minutes.

### Demo 2: Lakehouse, Spark, Delta, and Notebooks (15 min)

**Goal.** Show Delta as a table format with history, time travel, MERGE, schema evolution, and maintenance.

1. Open `lh_silver` in the Lakehouse explorer. Expand `Tables > bronze` to show the shortcut icons, then
   `Tables > silver`. Explain that the bronze tables are shortcuts and are not copies.
2. Open `nb_03_delta_lakehouse_deep_dive`. Run it, or show the last run's output if time is short.
3. Walk through the cells:
   - **History.** `DESCRIBE HISTORY` lists each version and operation.
   - **Time travel.** `versionAsOf 0` returns the rows from the first version.
   - **MERGE.** One row is updated and one is deleted. The history shows the MERGE.
   - **Schema evolution.** `mergeSchema` adds `risk_band` to the scratch table only.
   - **Maintenance.** `OPTIMIZE ... ZORDER` and `VACUUM ... DRY RUN`.
4. Explain why the demo uses `silver.demo_customers` (a scratch copy): production tables must not change during a demo.
5. Show `nb_02_bronze_to_silver` (not run live). Point to the stage logger and the data-quality checks.

**Expected result.** The notebook shows `Completed`. The history has a MERGE. `columns now:` includes `risk_band`.

**What to say.** Delta gives ACID writes, history, and time travel on files in OneLake. Schema changes need care in
silver. A pipeline that does not align columns breaks on the first added column.

**Fallback.** If the notebook is slow to start (Spark sessions can take a few minutes), show the saved outputs and
explain the cells.

### Demo 3: Warehouse and T-SQL (10 min)

**Goal.** Show the T-SQL experience that analysts use, and the limits that matter when migrating.

1. Open `wh_gold`. In the SQL query editor, run:

   ```sql
   SELECT TOP 5 province_code, year_num, large_cash_flags, transactions
   FROM gold.vw_large_cash_flags_by_province
   ORDER BY large_cash_flags DESC;
   ```

   Explain that the view joins a fact and two dimensions in the gold star schema.
2. Run a cross-item query that reads silver through the lakehouse SQL endpoint:

   ```sql
   SELECT COUNT_BIG(*) AS transactions FROM lh_silver.silver.transactions;
   ```

   Explain the three-part name and that the endpoint syncs asynchronously.
3. Show the stored procedure `gold.usp_load_gold` (read-only). Explain that the notebook
   `nb_04_silver_to_gold_warehouse` calls it.
4. Open `sql/fabric-warehouse/01_create_migrated_schema.sql` and point to the two conversion rules: `TINYINT` is not
   allowed, and the primary key is added with `ALTER TABLE`.

**Expected result.** The first query returns rows with large cash-flag counts. The count query returns 100,000,000.

**What to say.** Warehouse is a T-SQL engine on OneLake. You can join it with lakehouse tables without copying them.

**Fallback.** If the SQL endpoint has not synced, run `refreshMetadata` from the lakehouse settings and rerun.

### Demo 4: Synapse equivalents and migration (12 min)

**Goal.** Show a real migration from a dedicated SQL pool, with reconciliation.

1. Show the Synapse source. In the Azure portal, open `dwpool`, or run in Azure Data Studio or the SQL editor:

   ```sql
   SELECT COUNT_BIG(*) AS fact_rows, SUM(CAST(is_large_cash_flag AS INT)) AS large_flags, SUM(amount) AS total
   FROM dbo.fact_transaction;
   ```

   Expected: `100000000`, `2000000`, `284999500000.00`.
2. Open `pl_synapse_migration` and show the notebook activity and its `load_mode` parameter. Explain that the full
   extract ran before the session, and the demo runs the warehouse step (`warehouse_only`). Run it live if you have time
   (it takes a few minutes), or show the completed run.
3. Run the same totals on `wh_migrated_synapse`:

   ```sql
   SELECT COUNT_BIG(*) AS fact_rows, SUM(CAST(is_large_cash_flag AS INT)) AS large_flags, SUM(amount) AS total
   FROM dbo.fact_transaction;
   ```

   The values must match the Synapse query exactly.
4. Walk through `docs/migration/synapse-dedicated-to-fabric.md`, section 3 (DDL conversion) and section 1 (the path
   choice). Explain why this demo uses Spark JDBC, and what the production path looks like with ADLS staging.
5. Show the Synapse equivalents table in `docs/synapse-equivalents.md`.

**Expected result.** Control totals match across the two systems.

**What to say.** Migration is a reconciliation exercise. Control totals and row counts are the evidence. Keep this
evidence in your change record.

**Fallback.** If the Synapse pool is paused, resume it (about 5 minutes) or show the screenshots in the migration doc.

### Demo 5: Shortcuts and mirroring (8 min)

**Goal.** Show zero-copy access and mirroring.

1. In `lh_silver`, show the shortcuts under `Tables/bronze`. Click a shortcut to show its target path.
2. In `lh_bronze`, show `Tables/bronze/core_payments`. It is a shortcut to the mirrored table in the Fabric SQL database.
3. Open `sqldb_core_banking`. Show the `core` schema (customers, accounts, payments) and explain that its data is mirrored
   to OneLake automatically.
4. Optional, if time allows: run a single insert in the SQL database, then show the row in `silver.payments` after the next
   pipeline run. Mirroring has a delay, so do not promise a live result.

**Expected result.** The shortcut targets resolve. `core_payments` has 400,000 rows in the SQL database.

**What to say.** Shortcuts show data without copying it. Mirroring keeps an operational source in OneLake without an ETL
job. For external sources, the shortcut points at ADLS, S3, or another cloud. Mirroring of external databases needs the
source to be reachable from Fabric.

**Fallback.** If a shortcut shows an error, check the target item still exists. Mention the sandbox policy that blocks
ADLS and Azure SQL public access, and show the production pattern in the best-practices guide.

### Demo 6: Medallion patterns (10 min)

**Goal.** Show bronze, silver, and gold, with quality evidence.

1. Show the architecture diagram `diagrams/medallion-architecture.svg`. Walk the layers left to right.
2. Run this in `wh_gold` (or show it saved):

   ```sql
   SELECT COUNT_BIG(*) AS txns, SUM(large_cash_flag_count) AS large_flags FROM gold.fact_daily_channel_summary;
   ```

   Expected: `100000000` and `2000000`.
3. In `lh_silver`, open the table `silver.dq_results` and show the run log: rows in, rows out, rows rejected.
4. Explain `silver.dq_rejects`. The workshop data is clean, so the table is empty or absent. Say so.
5. Show the Best Practices document, section 1 (architecture) and section 4 (data quality).

**Expected result.** Gold totals match silver totals.

**What to say.** Each layer has a contract. Quality is checked in silver, and gold is for consumers. Reconciliation runs
after every load.

**Fallback.** If `silver.dq_rejects` does not exist, that is expected: the table is created only when a rule rejects rows.

### Demo 7: Git and deployment (10 min)

**Goal.** Show source control and promotion across environments.

1. In the Dev workspace, open **Workspace settings > Git integration**. Show the connected repository, branch `main`,
   and folder `/fabric-workspace`.
2. Open the GitHub repository and the folder `fabric-workspace/`. Show one item folder, for example
   `pl_medallion_daily.DataPipeline`, and explain that Fabric writes it.
3. Open the deployment pipeline `dp_fdw_osfi`. Show the three stages and the workspace assigned to each.
4. Open the Test workspace. Show that the notebooks and pipelines arrived, and that the lakehouses are empty.
   Open `pl_medallion_daily` in Test and show that its notebook references point to the Test items.
5. Explain the promotion to Prod: the same deployment step, with an approval gate in your process. Show the
   `-DeployToProd` switch in `scripts/10-git-and-deployment.ps1`.

**Expected result.** The Test workspace has the same items. The lakehouses are empty until the pipelines run in Test.

**What to say.** Git holds the definitions. Deployment pipelines move definitions across stages. Data moves separately,
through the same pipelines, so each stage runs its own load.

**Fallback.** If Git shows an error, check that the stored connection is valid (for example, the GitHub token has not
expired), then reconnect from the workspace settings.

## 5. Q&A bank

| Question | Short answer | Where to look |
|---|---|---|
| Where is the data stored? | In OneLake, in the region of the capacity. This build uses Canada Central. | Best practices, section 7 |
| Is Fabric a replacement for Synapse dedicated pools? | Warehouse covers the T-SQL workload. Spark and pipelines cover the rest. Check feature gaps in your workload. | `docs/synapse-equivalents.md` |
| How is the capacity sized and billed? | By F SKU capacity units. Pause or scale down when idle. Monitor with the Capacity Metrics app. | Best practices, section 2 |
| How do you secure access? | Workspace roles with Entra groups, item sharing, RLS and CLS in the warehouse, sensitivity labels. | Best practices, section 7 |
| Is traffic private? | Not in this sandbox. Production uses private endpoints and managed networks. | Best practices, section 7 |
| How do we handle disaster recovery? | Plan it with your resilience team (OSFI E-21). Fabric does not remove the need for a recovery design. Keep code in Git and rebuild from scripts. | Best practices, section 10 |
| Can we use shortcuts to on-premises data? | Use mirroring, the on-premises data gateway, or pipelines. Check the connector list for your source. | Learn: shortcuts and mirroring |
| What about third-party risk? | Document the service, data location, and exit plan under B-10. | Best practices, section 10 |
| Why not copy Synapse data with a single pipeline? | You can. Use the Copy activity with ADLS staging for large volumes. The sandbox blocked storage access, so we used Spark JDBC. | Migration runbook, section 1 |
| How long does a migration take? | It depends on volume, the number of objects, and the reconciliation effort. In the workshop build, the 100M-row fact table moved through Spark JDBC into Delta and then into the warehouse, and the totals reconciled. | Migration runbook || Do we keep the Synapse pool during cutover? | Keep it read-only until reconciliation passes, then pause, then decommission. | Migration runbook, section 7 |

## 6. Operating the environment

### 6.1 Resume and pause

```powershell
pwsh ./scripts/pause-resume.ps1 -Action Resume   # before a session (wait ~5 min for the pool)
pwsh ./scripts/pause-resume.ps1 -Action Pause    # after a session
```

### 6.2 Reset between sessions

```powershell
pwsh ./scripts/reset-demo.ps1
```

Removes scratch artifacts and reruns `pl_synapse_migration` in `warehouse_only` mode. It keeps the source, bronze,
silver, and gold data.

### 6.3 Source checks

Run these in the Synapse pool and in `wh_migrated_synapse`. Expect 100,000,000 fact rows and 2,000,000 large cash flags.
Run `nb_05_maintenance_rebuild_silver_customers` only to repair a dimension, never during a demo.

### 6.4 Full rebuild

```powershell
pwsh ./scripts/deploy-all.ps1
```

Plan about one hour. The steps that take the longest are the Synapse data generation (about 10 minutes), the full
migration (the Spark JDBC extract), and the Medallion pipeline (about 7 minutes).

### 6.5 Teardown

```powershell
pwsh ./scripts/teardown.ps1 -DeleteFabricWorkspaces -DeleteAzureResources
```

Revoke the GitHub token that Fabric stores for the Git connection when the workshop ends.

## 7. Troubleshooting (issues seen in this build)

| Symptom | Likely cause | Fix |
|---|---|---|
| Synapse login fails with "Client with IP address ... is not allowed" | Firewall | Run `01-deploy-azure.ps1 -ClientIp <ip>`. Egress IPs can change, so "Allow Azure services" (0.0.0.0) is set. |
| Notebook session cancelled with no detail | An exception in a cell | Read `Files/diagnostics/*_progress.txt` in the lakehouse (stage logger). |
| Notebook has no default lakehouse; `/lakehouse/default` missing | The notebook starts with a markdown cell | Start the notebook with a code cell. |
| Warehouse shows old values after a silver load | SQL endpoint not synced | Refresh the endpoint metadata, then rerun the load. |
| `Invalid object name 'lh_silver.silver.<table>'` | The table is new and the endpoint has not synced | Refresh metadata and retry. |
| `DefaultAzureCredential failed` in a notebook | Expected in Fabric notebooks | Use `notebookutils.credentials.getToken("https://database.windows.net/")`. |
| `synapsesql` attribute missing on `DataFrameWriter` | The Warehouse connector is not loaded in this Python session | Use T-SQL over JDBC from the notebook, as the workshop does. |
| MERGE fails with "cannot resolve <column>" | Target has a column the source does not | The notebook aligns columns. Rebuild the dimension with `nb_05` if it has drifted. |
| Git connect returns `GitProviderResourceNotFound` | The folder in the repo does not exist | Create the folder in the repository, commit it, then connect. |
| Deployment to Test fails with `CopyOverwriteResult.GenericError` on a warehouse | Repeat deployment of an existing warehouse | Deploy selectively (notebooks, pipelines, dataflows). `10-git-and-deployment.ps1` does this when Test already has lakehouses. Apply warehouse DDL with scripts. |
| Capacity admin rejected: "principals must be existing" | Object ID used instead of a UPN | Use a UPN in the capacity's tenant. |
| Azure SQL or storage creation blocked by policy | Tenant governance | Use Fabric-native sources and shortcuts, as the workshop does. |

## 8. Cost and resource control

- The Fabric capacity and the Synapse pool are the main costs. Pause both after every session.
- The workshop builds the pool at DW100c. Scale it up only for the bulk load, and scale it back down afterwards.
- Check the Azure cost analysis for `rg-fabric-de-workshop` and the Fabric Capacity Metrics app after each run.
- Remove resources you no longer need with `teardown.ps1`.

## 9. Adapting this kit

- **Your own data.** Replace the synthetic generator (`sql/synapse/02_generate_synthetic_data.sql`) with your source.
  Keep the bronze, silver, and gold contracts.
- **Your tenant.** Change `config/workshop.settings.json`. Names must be globally unique.
- **Your language.** The diagram has bilingual labels. The guide has bilingual headings and a glossary. Translate the
  sections you need.
- **Your audience.** Drop the Git section for a short executive session. Keep the migration and the reconciliation for
  technical audiences.

## 10. Bilingual glossary

| English | Français |
|---|---|
| Lakehouse | Lakehouse (maison du lac de données) |
| Warehouse | Entrepôt (Warehouse) |
| Shortcut | Raccourci |
| Mirroring | Mise en miroir (mirroring) |
| Medallion architecture | Architecture Medallion |
| Bronze / Silver / Gold | Brut / Conforme / Curé |
| Data quality | Qualité des données |
| Control totals | Totaux de contrôle |
| Migration | Migration |
| Deployment pipeline | Pipeline de déploiement |
| Capacity | Capacité |
| Data residency | Résidence des données |
| Synthetic data | Données synthétiques |
