# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Databricks Asset Bundle (DAB) that recreates one hackathon team's "Is My Block Cursed?" solution in any Databricks workspace, including Free Edition. There is no application code: the repo is two bundle configs, three notebooks, a Lakeview dashboard export, a Genie space export, and the raw CSVs. The README is the product; its audience has never used Databricks, so every change must keep the README's step-by-step flow working from a fresh clone.

## Commands

All bundle commands need a profile and the warehouse variable. The README has users export both; when working here do the same:

```bash
export DATABRICKS_CONFIG_PROFILE=target          # or pass --profile on each command
export WAREHOUSE_ID=<id>                         # databricks warehouses list
```

Full flow, in order (this is what the README walks users through):

```bash
databricks bundle validate --target dev --var="warehouse_id=$WAREHOUSE_ID"
databricks bundle deploy   --target dev --var="warehouse_id=$WAREHOUSE_ID"
./scripts/stage_data.sh                                            # copies the 2 hackathon CSVs into resources/data/
databricks fs cp resources/data dbfs:/Volumes/workspace/default/raw_data --recursive --overwrite
databricks bundle run build_tables --target dev --var="warehouse_id=$WAREHOUSE_ID"   # ~4 min, serverless
cd genie && databricks bundle deploy --target dev --var="warehouse_id=$WAREHOUSE_ID" && cd ..
databricks bundle summary --target dev --var="warehouse_id=$WAREHOUSE_ID"            # URLs for dashboard, job, space
```

Verification after any change to notebooks, `databricks.yml`, or the dashboard/Genie exports:

- The build job's last SQL cell prints `actual` vs `expected` for every table and view. All rows must match; the expected values are hardcoded there.
- Run every dashboard dataset query against the warehouse (loop over `datasets[].queryLines` in the dashboard JSON via `POST /api/2.0/sql/statements`). A dataset that errors shows as a blank widget, which users report as "the dashboard is broken".
- Check UI listings, not just the API: `databricks genie list-spaces`, the Dashboards page, and the Workspace browser.

Cleanup: `./scripts/teardown.sh` (needs the same two env vars). It runs both bundle destroys, then deletes the job, dashboard, and Genie space by name in case bundle state is missing, drops the tables, views, and volume, and removes the project's workspace folders. Tested against a workspace whose state a fresh clone could not see.

## Architecture

**Two bundles, deployed in a fixed order.** The root `databricks.yml` creates the volume, the `build_tables` job, and the dashboard. `genie/databricks.yml` creates only the Genie space. They are separate because Databricks refuses to create a Genie space unless every table it references already exists, and on a fresh workspace those tables only exist after the job runs. Do not merge them.

**Data path.** `hackathon-materials/` holds the two event CSVs as the only committed copies. `scripts/stage_data.sh` copies them into `resources/data/` (gitignored there); the team's own `nyc_population_by_zip.csv` is committed in `resources/data/` directly. CSVs are excluded from bundle sync and uploaded with `databricks fs cp` to the Unity Catalog volume `workspace.default.raw_data`. Never have notebooks read data from the `/Workspace` file mount: multi-MB reads there fail on some workspaces (FAILED_READ_FILE, or a 403 from blob storage even for plain Python reads).

**Pipeline** (`build_tables` job, two notebook tasks on serverless):
1. `ingest_raw_data.py` reads the three CSVs from the volume (`data_dir` job parameter, defaulting to the volume path) and writes `workspace.default.{rat_sightings, restaurant_inspections, nyc_population_by_zip}`.
2. `build_notebook.sql` builds five clean tables and `zip_service_gap_index`, then three views the exports depend on: `zip_lookup_v` and `borough_metric_shares_v` (dashboard), `rats_clean` (Genie). Cell 5 is the sanity check.

`key_decisions_notebook.sql` is documentation only; nothing runs it.

**Everything is hardcoded to `workspace.default`**: the notebooks, the dashboard datasets (each carries `catalog`/`schema`), the Genie data sources, the job parameter, and the volume path. Changing catalog or schema means a find-and-replace across all of them.

**Exports are the source of truth for UI objects.** The dashboard JSON and `.geniespace.json` were exported from the original workspace (`databricks lakeview get --include-serialized-space`-style API calls and `databricks bundle generate genie-space`). Edit them by re-exporting, not by hand. If a re-export references a new table or view, add it to `build_notebook.sql` and to the sanity check, or the Genie deploy will fail and dashboard widgets will go blank.

## Constraints that are not obvious from the code

- SQL notebooks must have a `.sql` extension. With `.py`, the CLI treats `-- Databricks notebook source` files as plain files and refuses to run them as job tasks.
- `mode: development` prefixes job, dashboard, and Genie names with `[dev <user>]` but does not prefix the volume name.
- The root bundle sets `workspace.root_path` to `~/nyc_service_gap_index` so notebooks are findable from Home. The Genie bundle sets `parent_path` to the user's home for the same reason: anything created under the default hidden `.bundle/` path is missing from UI listings. Changing `root_path` recreates the dashboard (new URL).
- `warehouse_id` deliberately has no default in either bundle so validate fails early with a clear message.
- Sync excludes `resources/data/**`, `hackathon-materials/**`, `docs/**`, `genie/**`, and `.gitignore`. Anything else at the repo root gets uploaded to every workspace on deploy. Sync exclude globs did not match a folder name containing spaces or `+`.
- `docs/` is for humans reading the repo (findings, brief, screenshots) and is never deployed.
- The README's `[dev <your name>]` prefixes, file counts in sample output, and step numbers are load-bearing for beginners; update them when resources change.

## Git

Other sessions and editors write into this working tree. Run `git status --short` before committing, stage files by name, and never use `git add -A`. Large pushes over HTTPS needed `git config http.postBuffer 524288000` once; it is set in this clone's local config.
