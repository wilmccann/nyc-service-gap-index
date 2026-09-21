# Databricks notebook source
# DBTITLE 1,Ingest Raw Data
# MAGIC %md
# MAGIC # Ingest Raw Data
# MAGIC
# MAGIC Reads the 3 source CSVs from the bundle's `resources/data/` directory and creates the raw tables that `build_notebook.py` expects.
# MAGIC
# MAGIC | CSV file | Table created |
# MAGIC | --- | --- |
# MAGIC | `rat_sightings.csv` | `workspace.default.rat_sightings` |
# MAGIC | `restaurant_inspections.csv` | `workspace.default.restaurant_inspections` |
# MAGIC | `nyc_population_by_zip.csv` | `workspace.default.nyc_population_by_zip` |
# MAGIC
# MAGIC Run this notebook **before** `build_notebook.py`.

# COMMAND ----------

# DBTITLE 1,Setup
import os

# Widget: override the CSV directory if your data lives elsewhere
dbutils.widgets.text("data_dir", "", "Directory containing the 3 CSV files")

# Auto-derive data_dir from this notebook's path if the widget is blank
data_dir = dbutils.widgets.get("data_dir")
if not data_dir:
    notebook_path = dbutils.notebook.getContext().notebookPath().get()
    parts = notebook_path.split("/")
    if "resources" in parts:
        idx = parts.index("resources")
        bundle_root = "/".join(parts[:idx])
        data_dir = f"/Workspace{bundle_root}/resources/data"
    else:
        data_dir = "/Workspace/resources/data"

print(f"Reading CSVs from: {data_dir}")
if os.path.exists(data_dir):
    print(f"Files found: {os.listdir(data_dir)}")
else:
    print("⚠ Directory not found. Set the data_dir widget to the correct path.")
    dbutils.notebook.exit("data_dir not found")

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

print("\n✓ All raw tables ready. Now run build_notebook.py to create the clean tables.")

# COMMAND ----------

