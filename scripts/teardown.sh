#!/usr/bin/env bash
# Removes everything this project created in a Databricks workspace, so you
# can run the README from Step 5 again as if for the first time.
#
# Uses the CLI profile in DATABRICKS_CONFIG_PROFILE and the warehouse in
# WAREHOUSE_ID, exactly like the README's deploy commands:
#   export DATABRICKS_CONFIG_PROFILE=target
#   export WAREHOUSE_ID=<id>
#   ./scripts/teardown.sh
#
# Removes: the Genie space, the build_tables job, the dashboard, the raw_data
# volume and its files, the 11 tables and views in workspace.default, and the
# project's workspace folders (including ones left by older versions).
# Leaves alone: the SQL warehouse, the workspace catalog and default schema,
# and anything you created yourself.
set -euo pipefail
: "${WAREHOUSE_ID:?Set WAREHOUSE_ID first (find it with: databricks warehouses list)}"
cd "$(dirname "$0")/.."
TARGET="${TARGET:-dev}"

ME=$(databricks current-user me -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["userName"])')
echo "Tearing down target '$TARGET' for $ME"

sql() {
  local body
  body=$(python3 -c 'import json,sys; print(json.dumps({"warehouse_id": sys.argv[1], "wait_timeout": "50s", "statement": sys.argv[2]}))' "$WAREHOUSE_ID" "$1")
  databricks api post /api/2.0/sql/statements --json "$body" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); s=d["status"]["state"]; print("   ", sys.argv[1], "->", s if s=="SUCCEEDED" else s+": "+d["status"].get("error",{}).get("message","")[:120])' "$1"
}

echo "1/4  Genie space"
(cd genie && databricks bundle destroy --target "$TARGET" --var="warehouse_id=$WAREHOUSE_ID" --auto-approve) \
  || echo "    (genie bundle destroy reported a problem; continuing)"

echo "2/4  Job, dashboard, volume, and uploaded files"
databricks bundle destroy --target "$TARGET" --var="warehouse_id=$WAREHOUSE_ID" --auto-approve \
  || echo "    (bundle destroy reported a problem; continuing)"

echo "3/4  Tables and views in workspace.default"
for v in zip_lookup_v borough_metric_shares_v rats_clean; do
  sql "DROP VIEW IF EXISTS workspace.default.$v"
done
for t in zip_service_gap_index restaurants_clean restaurant_violations_clean rodent_complaints_clean \
         nyc_population_clean rat_sightings restaurant_inspections nyc_population_by_zip; do
  sql "DROP TABLE IF EXISTS workspace.default.$t"
done
sql "DROP VOLUME IF EXISTS workspace.default.raw_data"

echo "4/4  Leftover workspace folders"
for p in "/Workspace/Users/$ME/nyc_service_gap_index" \
         "/Workspace/Users/$ME/.bundle/nyc_service_gap_index" \
         "/Workspace/Users/$ME/.bundle/nyc_service_gap_index_genie"; do
  if databricks workspace delete "$p" --recursive >/dev/null 2>&1; then echo "    deleted $p"; fi
done

echo "Done. Start again from README Step 5."
