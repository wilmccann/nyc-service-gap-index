#!/usr/bin/env bash
# Copies the two raw CSVs handed out at the hackathon from hackathon-materials/
# into resources/data/, where the bundle expects them (see README, Step 5).
# nyc_population_by_zip.csv is not a hackathon file and is committed in
# resources/data/ directly. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=hackathon-materials
DST=resources/data
mkdir -p "$DST"

for f in rat_sightings.csv restaurant_inspections.csv; do
  if [ ! -f "$SRC/$f" ]; then
    echo "Missing $SRC/$f. Did the clone finish?" >&2
    exit 1
  fi
  cp "$SRC/$f" "$DST/$f"
  echo "copied $SRC/$f -> $DST/$f ($(du -h "$DST/$f" | cut -f1))"
done

echo "resources/data now contains:"
ls -1 "$DST"
