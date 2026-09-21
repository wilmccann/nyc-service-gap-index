# Databricks notebook source
# DBTITLE 1,Ingest Raw Data
# MAGIC %md
# MAGIC # Ingest Raw Data
# MAGIC
# MAGIC Reads the 3 source CSVs from the Unity Catalog volume `workspace.default.raw_data` (uploaded with `databricks fs cp`, see README) and creates the raw tables that `build_notebook.sql` expects.
# MAGIC
# MAGIC | CSV file | Table created |
# MAGIC | --- | --- |
# MAGIC | `rat_sightings.csv` | `workspace.default.rat_sightings` |
# MAGIC | `restaurant_inspections.csv` | `workspace.default.restaurant_inspections` |
# MAGIC | `nyc_population_by_zip.csv` | `workspace.default.nyc_population_by_zip` |
# MAGIC
# MAGIC Run this notebook **before** `build_notebook.sql`.

# COMMAND ----------

# DBTITLE 1,Setup
import os

# The 3 CSVs live in a Unity Catalog volume. The bundle creates the volume
# (see databricks.yml) and you upload the files once with:
#   databricks fs cp resources/data dbfs:/Volumes/workspace/default/raw_data --recursive --overwrite
# Widget: override the directory if your data lives elsewhere.
dbutils.widgets.text("data_dir", "", "Directory containing the 3 CSV files")

data_dir = dbutils.widgets.get("data_dir").strip() or "/Volumes/workspace/default/raw_data"
CSV_FILES = ["rat_sightings.csv", "restaurant_inspections.csv", "nyc_population_by_zip.csv"]

print(f"Reading CSVs from: {data_dir}")
missing = [f for f in CSV_FILES if not os.path.exists(os.path.join(data_dir, f))]
if missing:
    raise FileNotFoundError(
        f"Missing in {data_dir}: {missing}\n"
        "Upload the CSVs from the repo with:\n"
        "  databricks fs cp resources/data dbfs:/Volumes/workspace/default/raw_data --recursive --overwrite"
    )
for f in CSV_FILES:
    print(f"  {f}: {os.path.getsize(os.path.join(data_dir, f)) / 1e6:.1f} MB")

# COMMAND ----------

# DBTITLE 1,Create catalog/schema
# Create catalog and schema if they don't exist
spark.sql("CREATE CATALOG IF NOT EXISTS workspace")
spark.sql("CREATE SCHEMA IF NOT EXISTS workspace.default")
print("Catalog 'workspace' and schema 'default' are ready.")

# COMMAND ----------

# DBTITLE 1,Ingest rat_sightings
# Ingest rat_sightings.csv → workspace.default.rat_sightings
# Expected columns: unique_key, created_date, closed_date, status, descriptor,
#   location_type, incident_zip, borough, latitude, longitude

df = spark.read.csv(
    f"{data_dir}/rat_sightings.csv",
    header=True,
    inferSchema=True,
)
df.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable("workspace.default.rat_sightings")
print(f"rat_sightings: {df.count():,} rows ingested")

# COMMAND ----------

# DBTITLE 1,Ingest restaurant_inspections
# Ingest restaurant_inspections.csv → workspace.default.restaurant_inspections
# Expected columns: camis, dba, boro, zipcode, cuisine_description,
#   inspection_date, score, violation_code, grade

df = spark.read.csv(
    f"{data_dir}/restaurant_inspections.csv",
    header=True,
    inferSchema=True,
)
df.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable("workspace.default.restaurant_inspections")
print(f"restaurant_inspections: {df.count():,} rows ingested")

# COMMAND ----------

# DBTITLE 1,Ingest nyc_population_by_zip
# Ingest nyc_population_by_zip.csv → workspace.default.nyc_population_by_zip
# Expected columns: zip_code, borough, population, margin_of_error

df = spark.read.csv(
    f"{data_dir}/nyc_population_by_zip.csv",
    header=True,
    inferSchema=True,
)
df.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable("workspace.default.nyc_population_by_zip")
print(f"nyc_population_by_zip: {df.count():,} rows ingested")

# COMMAND ----------

# DBTITLE 1,Verify
# Verify all 3 raw tables exist and show row counts
tables = [
    "workspace.default.rat_sightings",
    "workspace.default.restaurant_inspections",
    "workspace.default.nyc_population_by_zip",
]

print("Raw table verification:\n")
for t in tables:
    count = spark.table(t).count()
    cols = len(spark.table(t).columns)
    print(f"  {t}: {count:,} rows, {cols} columns")

print("\n✓ All raw tables ready. Now run build_notebook.sql to create the clean tables.")

# COMMAND ----------

