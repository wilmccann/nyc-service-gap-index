# Databricks notebook source
# DBTITLE 1,NYC Rodent Complaint & Restaurant Violation Map
# MAGIC %md
# MAGIC # NYC Rodent Complaint & Restaurant Violation Map
# MAGIC
# MAGIC Interactive map combining 311 rodent complaint locations with ZIP-level restaurant rodent violation data from the Service Gap Index.
# MAGIC
# MAGIC **Run this after the `build_tables` job has finished** (README Step 6). It reads `zip_service_gap_index`, `rodent_complaints_clean`, and `nyc_zip_neighborhoods`, all created by that job.
# MAGIC To run it: use the **Connect** dropdown at the top right to choose **Serverless**, then click **Run all**. The map appears under the last cell; hover a bubble for its ZIP's details.
# MAGIC
# MAGIC The first cell asks for plotly 5.24 or newer because `go.Scattermap` was added in that version. Serverless can ship an older plotly, and a plain `pip install plotly` does nothing when any version is already present, so the minimum is pinned.

# COMMAND ----------

# DBTITLE 1,Install plotly
# MAGIC %pip install plotly>=5.24

# COMMAND ----------

# DBTITLE 1,Data preparation
import plotly.express as px
import plotly.graph_objects as go
import pandas as pd
import numpy as np

# --- ZIP centroids from complaint lat/lon data (aggregated, no individual points) ---
zip_centroids = spark.sql("""
SELECT
  zip,
  AVG(latitude)  AS lat,
  AVG(longitude) AS lon,
  COUNT(*)       AS complaint_points
FROM workspace.default.rodent_complaints_clean
WHERE latitude IS NOT NULL
  AND longitude IS NOT NULL
  AND zip IS NOT NULL
GROUP BY zip
""").toPandas()

print(f"ZIP centroids computed: {len(zip_centroids)}")

# --- ZIP-level Service Gap Index (all dashboard metrics) ---
# nyc_zip_neighborhoods is the raw upload of resources/data/nyc_zip_neighborhoods.csv
# (borough, neighborhood, zip as an integer), so pad its zip to 5 digits for the join.
zip_df = spark.sql("""
SELECT
  z.zip,
  z.borough,
  n.neighborhood AS neighborhood,
  -- Service Gap Index & components
  z.service_gap_index,
  z.no_show_score,
  z.slow_response_score,
  z.rodent_need_score,
  z.service_gap_label,
  z.service_gap_rank,
  -- Three key measures
  z.pct_auto_closed_before_apr2026,
  z.median_days_to_close_after_apr2026,
  z.rodent_violation_rate_pct,
  -- Complaint aggregates
  z.complaints_all,
  z.rodent_sightings,
  z.rat_sightings,
  z.condition_complaints,
  z.distinct_locations,
  z.top_location_share_pct,
  z.complaints_per_10k_residents,
  -- Restaurant / inspection aggregates
  z.restaurants,
  z.inspections,
  z.restaurants_with_rodent_violation,
  -- Population
  z.population,
  z.has_population
FROM workspace.default.zip_service_gap_index z
LEFT JOIN workspace.default.nyc_zip_neighborhoods n
  ON z.zip = LPAD(CAST(n.zip AS STRING), 5, '0')
WHERE z.has_enough_data = true
""").toPandas()

zip_df['borough'] = zip_df['borough'].str.title()

# Merge centroids so every scored ZIP has a lat/lon
zip_merged = zip_df.merge(zip_centroids, on='zip', how='inner')

print(f"\nScored ZIPs with centroids: {len(zip_merged)}")
display(zip_merged.head(5))

# COMMAND ----------

# DBTITLE 1,ZIP-level bubble map: Service Gap Index
# --- ZIP-level bubble map: Service Gap Index with component breakdown ---
# All lat/lon data aggregated to ZIP centroids. No individual complaint points.
# Metrics aligned with the NYC Service Gap Dashboard (both tabs).

fig = go.Figure()

# Bubble size: exponential scaling so high service gaps are dramatically larger
# Normalize to 0-1, apply power scaling, then scale to pixel size
index_values = zip_merged['service_gap_index'].astype(float)
normalized = (index_values - index_values.min()) / (index_values.max() - index_values.min())
size_scaled = (normalized ** 1.8) * 45 + 8  # Power of 1.8 creates dramatic size differences

# Bubble color: sqrt-scaled total 311 complaints
color_scaled = np.sqrt(zip_merged['complaints_all'].astype(float).clip(lower=1))

# Build concise hover text with key metrics
hover_text = []
for _, row in zip_merged.iterrows():
    # Build ZIP line with neighborhood if available
    if pd.notna(row.get('neighborhood')):
        zip_line = f"<b>ZIP {row['zip']} — {row['neighborhood']}, {row['borough']}</b><br>"
    else:
        zip_line = f"<b>ZIP {row['zip']} — {row['borough']}</b><br>"

    hover = (
        zip_line +
        f"Service Gap Index: <b>{row['service_gap_index']:.1f}</b><br>"
        f"Rank: #{int(row['service_gap_rank'])} of {int(zip_merged['service_gap_rank'].max())}<br>"
        f"<br>Component scores (percentile):<br>"
        f"  No-show: {row['no_show_score']*100:.0f} | Slow: {row['slow_response_score']*100:.0f} | Need: {row['rodent_need_score']*100:.0f}<br>"
        f"<br>311 complaints: {int(row['complaints_all']):,}<br>"
        f"Restaurant violations: {row['rodent_violation_rate_pct']}% ({int(row['restaurants_with_rodent_violation'])} of {int(row['restaurants'])})<br>"
    )

    if pd.notna(row['population']):
        hover += f"Population: {int(row['population']):,}"
    else:
        hover += "Population: No estimate"

    hover_text.append(hover)

fig.add_trace(go.Scattermap(
    lat=zip_merged['lat'],
    lon=zip_merged['lon'],
    mode='markers',
    marker=dict(
        size=size_scaled,
        color=color_scaled,
        colorscale=[
            [0.0, '#ffee88'],    # Medium yellow (darker so it stands out)
            [0.5, '#fec44f'],    # Golden orange
            [1.0, '#d95f0e']     # Deep orange
        ],
        cmin=color_scaled.min(),
        cmax=color_scaled.max(),
        colorbar=dict(
            title='311 Rodent<br>Complaints<br>(sqrt-scaled)',
            x=1.02,
        ),
        opacity=0.85,
        symbol='circle',
    ),
    text=hover_text,
    name='ZIP Service Gap',
    hovertemplate='%{text}<extra></extra>',
))

# Add rank labels for top 10 service gaps with ZIP codes
top_10 = zip_merged.nsmallest(10, 'service_gap_rank')

# Create labels with rank and ZIP code
labels = [f"{int(row['service_gap_rank'])}: {row['zip']}" for _, row in top_10.iterrows()]

fig.add_trace(go.Scattermap(
    lat=top_10['lat'],
    lon=top_10['lon'],
    mode='text',
    text=labels,
    textfont=dict(
        size=12,
        color='black',
        family='Arial Black, sans-serif',
    ),
    name='Top 10 Ranks',
    hoverinfo='skip',
    showlegend=False,
))

# Add size reference bubbles to show service gap index scale
ref_indices = [30, 50, 70, 90]
ref_lats = [40.49, 40.47, 40.45, 40.43]
ref_lons = [-74.25, -74.25, -74.25, -74.25]
# Apply same exponential scaling to reference bubbles
min_idx = zip_merged['service_gap_index'].min()
max_idx = zip_merged['service_gap_index'].max()
ref_sizes = [((idx - min_idx) / (max_idx - min_idx)) ** 1.8 * 45 + 8 for idx in ref_indices]

fig.add_trace(go.Scattermap(
    lat=ref_lats,
    lon=ref_lons,
    mode='markers+text',
    marker=dict(
        size=ref_sizes,
        color='rgba(100,100,100,0.3)',
        opacity=0.5,
        symbol='circle',
    ),
    text=[f'Gap {idx}' for idx in ref_indices],
    textposition='middle right',
    textfont=dict(size=10, color='rgba(60,60,60,0.9)'),
    name='Size reference',
    hoverinfo='skip',
    showlegend=False,
))

fig.update_layout(
    map=dict(
        style='carto-positron',
        center=dict(lat=40.72, lon=-74.0),
        zoom=10,
    ),
    margin=dict(l=0, r=0, t=50, b=0),
    title=dict(
        text='NYC Service Gap Index by ZIP — Bubble size = Service Gap Index, color = 311 complaint volume',
        x=0.01,
        font=dict(size=16),
    ),
    height=750,
    showlegend=False,
)

fig.show()
print(f"\nMap shows {len(zip_merged)} ZIP-level bubbles (service gap scored ZIPs only)")
print("Bubble color = Total 311 rodent complaints (sqrt-scaled, orange = more complaints)")
print("Bubble size = Service Gap Index (bigger bubble = bigger service gap)")
print("Hover for component breakdown, key measures, and all aggregate stats")
