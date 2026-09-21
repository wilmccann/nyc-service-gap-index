# NYC Service Gap Index — Databricks Asset Bundle

A self-contained Databricks Asset Bundle (DAB) that packages the **source data**, **build notebooks**, and **Lakeview dashboard** for the NYC ZIP Service Gap Index project. Clone the repo, deploy the bundle, run two notebooks, and the dashboard is live — no manual data upload required.

---

## What's included

| File | Description |
| --- | --- |
| `databricks.yml` | Bundle definition — variables, targets, dashboard resource, sync rules |
| `resources/data/rat_sightings.csv` | NYC 311 rodent complaint records (50,954 rows) |
| `resources/data/restaurant_inspections.csv` | NYC DOHMH restaurant inspection records (158,083 rows) |
| `resources/data/nyc_population_by_zip.csv` | ACS population estimates by ZIP code (231 rows) |
| `resources/notebooks/ingest_raw_data.py` | Reads the 3 CSVs and creates the raw Databricks tables |
| `resources/notebooks/build_notebook.py` | DDL/DML that transforms raw tables into clean tables + the final `zip_service_gap_index` |
| `resources/notebooks/key_decisions_notebook.py` | Documentation notebook — 11 analytical decisions with validation queries |
| `resources/dashboards/zip_service_gap_index_dashboard.json` | Lakeview dashboard (bar chart + full ZIP-level table) |

## Data pipeline overview

```
resources/data/*.csv
        │
        ▼  (ingest_raw_data.py — Run All)
  3 raw tables in workspace.default
        │
        ▼  (build_notebook.py — Run All)
  5 clean tables + zip_service_gap_index
        │
        ▼
  Lakeview dashboard reads zip_service_gap_index
```

| Raw table (created from CSV) | Clean table (build notebook creates) |
| --- | --- |
| `rat_sightings` | `rodent_complaints_clean` |
| `restaurant_inspections` | `restaurant_violations_clean` → `restaurants_clean` |
| `nyc_population_by_zip` | `nyc_population_clean` |
| | **`zip_service_gap_index`** (final output the dashboard reads) |

All tables use the catalog/schema `workspace.default` by default. To use a different catalog/schema, see [Updating catalog & schema](#updating-catalog--schema) below.

---

## Quick start (for a new user on the target account)

### Prerequisites

* A Databricks workspace with **serverless compute** enabled (or an attached cluster)
* Permission to create catalogs and schemas in Unity Catalog
* A SQL warehouse (any size — the dashboard needs it; the notebooks use serverless compute)

### Step 1 — Install and authenticate the Databricks CLI

```bash
pip install databricks-sdk
# or: brew install databricks
```

Authenticate with a profile for the **target** workspace:

```bash
databricks configure --profile target --host https://<target-workspace-url> --token
```

### Step 2 — Clone the repo into a Databricks Git folder

The bundle root must live inside a **Git folder** in the Databricks workspace. You can either:

* **In the Databricks UI:** Workspace → Repos → Add → clone your Git repo, or
* **Via CLI:**

```bash
git clone <your-repo-url> nyc-service-gap-index
cd nyc-service-gap-index
```

### Step 3 — Find your SQL warehouse ID

The dashboard requires a SQL warehouse. Find its ID in the Databricks UI:

**Workspace → SQL Warehouses** → click your warehouse → copy the ID (e.g. `dcac6c74800b452a`).

If you don't have one, create a 2X-Small Serverless warehouse — that's enough for this dashboard.

### Step 4 — Validate and deploy the bundle

```bash
# Use the profile you created in Step 1
export DATABRICKS_CONFIG_PROFILE=target

databricks bundle validate --target dev
databricks bundle deploy  --target dev --var="warehouse_id=<your-warehouse-id>"
```

This deploys:
* The **ZIP Service Gap Index** dashboard
* All three notebooks to the workspace (ingest, build, key decisions)
* The 3 CSV files to `resources/data/` in the deployed workspace folder

### Step 5 — Ingest the raw data

In the Databricks UI, navigate to the deployed workspace folder and open `ingest_raw_data.py`.

Click **Run All**. This reads the 3 CSVs that shipped with the bundle and creates:

| Table | Source CSV | Rows |
| --- | --- | --- |
| `workspace.default.rat_sightings` | `rat_sightings.csv` | ~51K |
| `workspace.default.restaurant_inspections` | `restaurant_inspections.csv` | ~158K |
| `workspace.default.nyc_population_by_zip` | `nyc_population_by_zip.csv` | 231 |

The notebook also creates the `workspace` catalog and `default` schema if they don't already exist.

### Step 6 — Build the clean tables and index

Open `build_notebook.py` and click **Run All**. This creates:

* `rodent_complaints_clean` — one row per 311 complaint, with auto-close flagging
* `restaurant_violations_clean` — one row per violation, with rodent-violation flags
* `restaurants_clean` — one row per restaurant, with inspection summaries
* `nyc_population_clean` — one row per ZIP, with population quality flags
* **`zip_service_gap_index`** — the final table the dashboard reads

Cell 5 at the end of the notebook prints a sanity-check table showing `actual` vs `expected` row counts. If every row matches, the build succeeded.

### Step 7 — Open the dashboard

Navigate to **Workspace → Dashboards** (or **Catalog → Dashboards**) and find **"ZIP Service Gap Index"**. It should display:
* A bar chart of average service gap index by borough
* A full table of every NYC ZIP code with all complaint, restaurant, and index columns
* Borough and index-range filters

If the widgets show no data, make sure your SQL warehouse is running.

---

## Troubleshooting

| Problem | Fix |
| --- | --- |
| **"Catalog workspace does not exist"** | `ingest_raw_data.py` creates it automatically. If it fails, ensure you have `CREATE CATALOG` permission. |
| **Dashboard shows no data** | Run `ingest_raw_data.py` then `build_notebook.py` first. The dashboard reads `workspace.default.zip_service_gap_index`, which doesn't exist until both notebooks have run. |
| **"warehouse_id is required"** | Pass `--var="warehouse_id=<id>"` on the deploy command, or set it in `databricks.yml`. |
| **Notebook can't find CSVs** | The `data_dir` widget in `ingest_raw_data.py` auto-detects the path. If it's wrong, set the widget manually to the deployed `resources/data/` folder. |
| **Different catalog/schema** | See [Updating catalog & schema](#updating-catalog--schema) below. |

---

## Updating catalog & schema

The notebook SQL hardcodes `workspace.default.*`. To use a different catalog/schema, either:

1. **Create matching names** on the target (simplest):

   ```sql
   CREATE CATALOG IF NOT EXISTS workspace;
   CREATE SCHEMA IF NOT EXISTS workspace.default;
   ```

   Then no code changes are needed.

2. **Find-and-replace** in the notebook and dashboard files: replace `workspace.default` with your target `catalog.schema` in:
   * `ingest_raw_data.py`
   * `build_notebook.py`
   * `key_decisions_notebook.py`
   * `zip_service_gap_index_dashboard.json` (the dashboard dataset source)

---

## Project background

The NYC Service Gap Index measures the gap between rodent need and city response for each ZIP code:

* **Component 1 — No-show rate:** % of pre-April-2026 311 rodent complaints auto-closed within 60 seconds (no inspection).
* **Component 2 — Slow response:** Median days to close complaints filed Apr–Jul 2026 (after auto-closing stopped).
* **Component 3 — Rodent need:** % of restaurants cited for rats (04K) or mice (04L) on inspection.

The composite index (0–100) averages the three percentile ranks. A higher score means a bigger gap between how many rodents inspectors find and how little the city responds.

For a detailed walkthrough of each analytical decision (what counts as a rodent complaint, why auto-closes are excluded, why median not average, etc.), open `key_decisions_notebook.py` and run the cells.