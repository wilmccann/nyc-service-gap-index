# NYC Service Gap Index — Databricks Asset Bundle

A Databricks Asset Bundle (DAB) that packages the **build notebook**, **key-decisions notebook**, and **Lakeview dashboard** for the NYC ZIP Service Gap Index project, so they can be deployed to another Databricks account.

---

## What's included

| File | Description |
| --- | --- |
| `databricks.yml` | Bundle definition — variables, targets, resources |
| `resources/notebooks/build_notebook.py` | DDL/DML notebook that builds all clean tables and the `zip_service_gap_index` from the 3 raw uploads |
| `resources/notebooks/key_decisions_notebook.py` | Documentation notebook — key analytical decisions with validation queries |
| `resources/dashboards/zip_service_gap_index_dashboard.json` | Lakeview dashboard (bar chart + full table) |

## Tables this bundle creates

Starting from **3 raw tables** (CSV uploads) the build notebook creates:

| Raw table (you upload) | Clean table (notebook builds) |
| --- | --- |
| `rat_sightings` | `rodent_complaints_clean` |
| `restaurant_inspections` | `restaurant_violations_clean` → `restaurants_clean` |
| `nyc_population_by_zip` | `nyc_population_clean` |
| | **`zip_service_gap_index`** (final output) |

All tables use the catalog/schema `workspace.default` by default. If the target account uses a different catalog/schema, see [Updating catalog & schema](#updating-catalog--schema) below.

---

## Deploy on the target account

### 1. Install the Databricks CLI

```bash
pip install databricks-sdk
# or
brew install databricks
```

Authenticate with a profile for the **target** workspace:
```bash
databricks configure --profile target --host https://<target-workspace> --token
```

### 2. Get the code onto the target workspace

Clone or copy this folder into a **Git folder** on the target workspace (the bundle root must be inside a Git folder).

```bash
git clone <your-repo-url> nyc-service-gap-index
cd nyc-service-gap-index
```

### 3. (Optional) Set the SQL warehouse ID

Edit `databricks.yml` and set the `warehouse_id` variable, or pass it at deploy time:
```bash
databricks bundle deploy --target dev --var="warehouse_id=abc123def456"
```

### 4. Validate and deploy

```bash
databricks bundle validate --target dev
databricks bundle deploy  --target dev
```

This deploys:
- The **build_tables** job (paused — run it manually after uploading data)
- The **ZIP Service Gap Index** dashboard
- Both notebooks to the workspace

---

## Upload the raw data

The build notebook expects 3 raw tables in `workspace.default`. Create them by uploading the original CSVs:

| Table name | CSV source |
| --- | --- |
| `workspace.default.rat_sightings` | NYC 311 Rodent Complaints export |
| `workspace.default.restaurant_inspections` | NYC DOHMH Restaurant Inspections export |
| `workspace.default.nyc_population_by_zip` | ACS population estimates by ZIP code |

Upload each CSV via the Databricks UI (**Catalog → Create Table → Upload File**) or via:
```python
spark.read.csv("/path/to/rat_sightings.csv", header=True, inferSchema=True) \
  .write.saveAsTable("workspace.default.rat_sightings")
```

Once the raw tables exist, run the **build_tables** job (or open `build_notebook.py` and Run All) to create all clean tables and the final index.

---

## Updating catalog & schema

The notebook SQL hardcodes `workspace.default.*`. To use a different catalog/schema, either:

1. **Create matching names** on the target: `CREATE CATALOG workspace; CREATE SCHEMA workspace.default;` — then no code changes are needed.

2. **Find-and-replace** in the notebook files: replace `workspace.default` with your target catalog.schema in `build_notebook.py` and `key_decisions_notebook.py`, and update the dashboard dataset source in `zip_service_gap_index_dashboard.json`.

---

## Project background

The NYC Service Gap Index measures the gap between rodent need and city response for each ZIP code:
- **Component 1 — No-show rate:** % of pre-April-2026 311 rodent complaints auto-closed within 60 seconds (no inspection).
- **Component 2 — Slow response:** Median days to close complaints filed Apr–Jul 2026 (after auto-closing stopped).
- **Component 3 — Rodent need:** % of restaurants cited for rats (04K) or mice (04L) on inspection.

The composite index (0–100) averages the three percentile ranks. A higher score means a bigger gap between how many rodents inspectors find and how little the city responds.