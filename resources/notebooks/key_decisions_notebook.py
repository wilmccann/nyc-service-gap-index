-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Key decisions behind the Service Gap Index
-- MAGIC One cell per decision: **what we decided, why, the assumption underneath it, and a query that shows it in the data.**
-- MAGIC Edit any query and re-run. Expected numbers are noted so you can tell if something changed.
-- MAGIC
-- MAGIC Tables: `rat_sightings` / `restaurant_inspections` / `nyc_population_by_zip` (raw) and `rodent_complaints_clean`, `restaurant_violations_clean`, `restaurants_clean`, `nyc_population_clean`, `zip_service_gap_index` (ours).

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Decision 1. What counts as a rodent complaint
-- MAGIC **Decision:** a rodent *sighting* = descriptor in (Rat Sighting, Mouse Sighting, Signs of Rodents). "Condition Attracting Rodents" stays in the table, flagged `is_rodent_sighting = FALSE`, and is not counted as a sighting.
-- MAGIC **Why:** a sighting is direct evidence of rodents; "Condition Attracting Rodents" is a garbage/harborage report.
-- MAGIC **Assumption:** the descriptor is chosen accurately by the caller or 311 operator.

-- COMMAND ----------

-- Every complaint is complaint_type = Rodent; the four descriptors and how we classified them.
-- Expect: Rat Sighting 32,942 / Condition Attracting Rodents 10,788 / Signs of Rodents 5,178 / Mouse Sighting 2,046
SELECT descriptor,
       is_rodent_sighting,
       COUNT(*)                                                    AS complaints,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)          AS pct_of_all,
       ROUND(100.0 * SUM(CASE WHEN is_auto_closed THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_auto_closed
FROM workspace.default.rodent_complaints_clean
GROUP BY descriptor, is_rodent_sighting
ORDER BY complaints DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Decision 2. What "the city showed up" means
-- MAGIC **Decision:** a complaint closed within 60 seconds of being filed is `is_auto_closed` = no visit. Anything closed later is "worked".
-- MAGIC **Why:** 22,547 complaints (44%) closed in under a minute, at every hour of the night. That is a system action, not an inspection.
-- MAGIC **Assumption (the big one):** the 311 export has **no resolution text**, so "no visit" is inferred from timing. Some auto-closes could be legitimate duplicates, but 84% of auto-closed locations never called again within 30 days.

-- COMMAND ----------

-- How long complaints take to close, in buckets. Expect '<= 1 minute' = 22,547 (44.2%) and almost nothing between 1 minute and 1 hour.
SELECT CASE WHEN closed_at IS NULL            THEN '7. still open'
            WHEN minutes_to_close <= 1        THEN '1. <= 1 minute  (auto-closed)'
            WHEN minutes_to_close <= 60       THEN '2. 1 min - 1 hour'
            WHEN minutes_to_close <= 1440     THEN '3. 1 hour - 1 day'
            WHEN minutes_to_close <= 7*1440   THEN '4. 1 - 7 days'
            WHEN minutes_to_close <= 30*1440  THEN '5. 7 - 30 days'
            ELSE                                   '6. over 30 days' END AS time_to_close,
       COUNT(*) AS complaints,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM workspace.default.rodent_complaints_clean
GROUP BY 1 ORDER BY 1;

-- COMMAND ----------

-- Proof it is a machine: hour of day when complaints were closed. Auto-closes happen at 1am-4am; worked closures cluster in office hours and 6-8pm.
SELECT HOUR(closed_at) AS hour_closed,
       SUM(CASE WHEN is_auto_closed THEN 1 ELSE 0 END)     AS auto_closed,
       SUM(CASE WHEN NOT is_auto_closed THEN 1 ELSE 0 END) AS worked
FROM workspace.default.rodent_complaints_clean
WHERE closed_at IS NOT NULL
GROUP BY 1 ORDER BY 1;

-- COMMAND ----------

-- Did people call back after being auto-closed? About 16% of locations re-filed within 30 days; 84% did not.
-- (Caution: worked complaints re-file at ~45%, but those skew to big apartment buildings with many residents, so this is not a clean comparison.)
WITH a AS (
  SELECT is_auto_closed, created_at,
         LEAD(created_at) OVER (PARTITION BY latitude, longitude ORDER BY created_at) AS next_complaint_at
  FROM workspace.default.rodent_complaints_clean
  WHERE latitude IS NOT NULL
)
SELECT COUNT(*) AS auto_closed,
       SUM(CASE WHEN next_complaint_at <= created_at + INTERVAL 30 DAYS THEN 1 ELSE 0 END) AS refiled_within_30d,
       ROUND(100.0 * SUM(CASE WHEN next_complaint_at <= created_at + INTERVAL 30 DAYS THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_refiled
FROM a
WHERE is_auto_closed;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Decision 3. Two time windows, not one
-- MAGIC **Decision:** "did the city show up" (auto-close %) is measured **Jan 2025 - Apr 19 2026**. "How fast" (median days) is measured **Apr 20 - Jul 31 2026**. Aug/Sep 2026 excluded from speed because most are still open.
-- MAGIC **Why:** auto-closing stopped on 2026-04-20. Before that there is no real response time; after it there is no auto-close variation. Mixing eras produces the false conclusion "response got 50x worse in 2026".
-- MAGIC **Assumption:** April 20 is a real policy/system change, not an export artifact. We can confirm the date, not the cause.

-- COMMAND ----------

-- The trap in one table: naive median (all rows) says 0.0 days in 2025 and ~10 days in 2026.
-- pct_auto_closed says why: ~60% of complaints got no visit until April 2026, then 0%.
SELECT created_month,
       COUNT(*)                                                                  AS complaints,
       ROUND(100.0 * SUM(CASE WHEN is_auto_closed THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_auto_closed,
       ROUND(100.0 * SUM(CASE WHEN closed_at IS NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_still_open,
       ROUND(MEDIAN(days_to_close), 1)                                           AS naive_median_days_all_rows,
       ROUND(MEDIAN(CASE WHEN NOT is_auto_closed THEN days_to_close END), 1)     AS median_days_worked_only
FROM workspace.default.rodent_complaints_clean
GROUP BY 1 ORDER BY 1;

-- COMMAND ----------

-- Pin the cutover to the day. Expect auto-closes fall to 1 on 2026-04-20 and 0 after.
SELECT CAST(created_at AS DATE) AS day, COUNT(*) AS complaints,
       SUM(CASE WHEN is_auto_closed THEN 1 ELSE 0 END) AS auto_closed
FROM workspace.default.rodent_complaints_clean
WHERE created_at BETWEEN '2026-04-13' AND '2026-04-27'
GROUP BY 1 ORDER BY 1;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Decision 4. Median, not average, and never on auto-closed rows
-- MAGIC **Decision:** every response-time number is `MEDIAN(days_to_close)` over worked complaints only.
-- MAGIC **Why:** auto-closes at 0.0 days drag any unfiltered statistic to zero, so the ZIPs where the city never came look like the fastest-served ZIPs in the city.

-- COMMAND ----------

-- Same ZIPs, three ways of measuring "response time". Watch the ranking flip.
-- Before April 2026, the ZIPs with the LOWEST naive median are the ones with the HIGHEST auto-close rate.
SELECT zip, borough,
       COUNT(*)                                                                AS complaints,
       ROUND(100.0 * SUM(CASE WHEN is_auto_closed THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_auto_closed,
       ROUND(AVG(days_to_close), 1)                                            AS avg_days_all_rows,
       ROUND(MEDIAN(days_to_close), 1)                                         AS median_days_all_rows,
       ROUND(MEDIAN(CASE WHEN NOT is_auto_closed THEN days_to_close END), 1)   AS median_days_worked
FROM workspace.default.rodent_complaints_clean
WHERE policy_era = 'before_2026-04-20' AND zip IS NOT NULL
GROUP BY 1, 2
HAVING COUNT(*) >= 150
ORDER BY median_days_all_rows ASC, pct_auto_closed DESC
LIMIT 15;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Decision 5. What counts as a rodent violation at a restaurant
-- MAGIC **Decision:** codes **04K (rats)** and **04L (mice)** only. **08A** (harborage / conditions conducive to pests, 12,502 rows) is flagged but not counted. Same logic as Decision 1: evidence of rodents vs. conditions that might attract them.
-- MAGIC **Assumption:** inspectors apply codes consistently across boroughs.

-- COMMAND ----------

-- Every code whose description mentions rodents/pests, with rows vs distinct restaurants. Only 04K and 04L are rodent evidence.
SELECT violation_code,
       violation_description,
       is_rodent_violation,
       COUNT(*)              AS violation_rows,
       COUNT(DISTINCT camis) AS restaurants
FROM workspace.default.restaurant_violations_clean
WHERE LOWER(violation_description) RLIKE 'rat|mice|mouse|rodent|vermin|pest'
GROUP BY 1, 2, 3
ORDER BY violation_rows DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Decision 6. Count restaurants, never rows
-- MAGIC **Decision:** restaurant rodent rate = restaurants with at least one 04K/04L citation / restaurants inspected, via `COUNT(DISTINCT camis)`. We built `restaurants_clean` (one row per restaurant) so this cannot be done wrong.
-- MAGIC **Why:** the file is one row per violation. Rodent-violation *counts* per ZIP correlate 0.93 with inspection counts, so counting rows is counting inspections.
-- MAGIC **Assumption:** restaurants in a ZIP have roughly equal odds of being inspected. 14,122 of 26,114 were inspected only once, so the rate is a floor.

-- COMMAND ----------

-- Three different "counts" from the same file. Expect 158,083 rows / 44,447 inspections / 26,114 restaurants.
SELECT COUNT(*)                                        AS violation_rows,
       COUNT(DISTINCT camis, inspection_date)          AS inspections,
       COUNT(DISTINCT camis)                           AS restaurants,
       COUNT(DISTINCT CASE WHEN is_rodent_violation THEN camis END) AS restaurants_with_rodent_violation,
       SUM(CASE WHEN is_rodent_violation THEN 1 ELSE 0 END)         AS rodent_violation_rows
FROM workspace.default.restaurant_violations_clean;

-- COMMAND ----------

-- Per ZIP: raw rodent-violation rows track inspection volume almost perfectly (corr ~0.93).
-- The RATE (share of restaurants cited) is what varies independently.
WITH z AS (
  SELECT zip,
         COUNT(DISTINCT camis, inspection_date)                          AS inspections,
         COUNT(DISTINCT camis)                                           AS restaurants,
         SUM(CASE WHEN is_rodent_violation THEN 1 ELSE 0 END)            AS rodent_violation_rows,
         COUNT(DISTINCT CASE WHEN is_rodent_violation THEN camis END)    AS restaurants_with_rodent
  FROM workspace.default.restaurant_violations_clean
  WHERE zip IS NOT NULL GROUP BY zip
)
SELECT ROUND(CORR(inspections, rodent_violation_rows), 2)                     AS corr_rows_vs_inspections,
       ROUND(CORR(inspections, restaurants_with_rodent / restaurants), 2)     AS corr_rate_vs_inspections
FROM z;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Decision 7. ZIP normalization and what we dropped
-- MAGIC **Decision:** pad to 5 digits, keep only NYC ranges (`100xx-104xx`, `11xxx`). Dropped: 1 complaint (ZIP 12345), 1,513 violation rows with no ZIP, 54 with NJ/Long Island ZIPs. Population `zip_code` cast INT to string to join.
-- MAGIC **Assumption:** `incident_zip` is where the rat was seen, not where the caller lives.

-- COMMAND ----------

-- Raw 311 ZIPs that failed validation. Expect exactly 1 row: 12345.
WITH z AS (SELECT incident_zip, LPAD(SUBSTRING(CAST(incident_zip AS STRING), 1, 5), 5, '0') AS zip_raw FROM workspace.default.rat_sightings)
SELECT incident_zip, COUNT(*) AS complaints
FROM z
WHERE zip_raw IS NULL OR NOT zip_raw RLIKE '^1[01][0-9]{3}$'
GROUP BY 1 ORDER BY 2 DESC;

-- COMMAND ----------

-- Raw inspection ZIPs that failed validation: NULLs and non-NYC (07xxx = New Jersey, 117xx = Long Island). boro = '0' marks out-of-city restaurants.
WITH z AS (SELECT zipcode, boro, camis, LPAD(SUBSTRING(CAST(zipcode AS STRING), 1, 5), 5, '0') AS zip_raw FROM workspace.default.restaurant_inspections)
SELECT zipcode, boro, COUNT(*) AS violation_rows, COUNT(DISTINCT camis) AS restaurants
FROM z
WHERE zip_raw IS NULL OR NOT zip_raw RLIKE '^1[01][0-9]{3}$'
GROUP BY 1, 2 ORDER BY 3 DESC;

-- COMMAND ----------

-- What survived: valid-ZIP rows in each clean table. Expect 50,953 complaints and 156,516 violation rows with a ZIP.
SELECT 'complaints' AS tbl, COUNT(*) AS total_rows, SUM(CASE WHEN zip IS NULL THEN 1 ELSE 0 END) AS rows_without_zip FROM workspace.default.rodent_complaints_clean
UNION ALL
SELECT 'violations', COUNT(*), SUM(CASE WHEN zip IS NULL THEN 1 ELSE 0 END) FROM workspace.default.restaurant_violations_clean
UNION ALL
SELECT 'restaurants', COUNT(*), SUM(CASE WHEN zip IS NULL THEN 1 ELSE 0 END) FROM workspace.default.restaurants_clean;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Decision 8. When a ZIP is "not enough data"
-- MAGIC **Decision:** a ZIP gets an index and rank only with >= 30 complaints, >= 10 restaurants, >= 20 pre-April complaints and >= 5 post-April complaints. 155 ranked, 72 not. Unranked ZIPs show raw counts and the borough comparison, never a score.
-- MAGIC **Why:** JFK has 2 complaints; LaGuardia 0. A median of 5 numbers is noise; a rank built on it is a lie with a decimal point.
-- MAGIC **Assumption:** the thresholds are judgment calls, chosen so the smallest ranked ZIP has stable percentages. No ranked ZIP has a NULL component.

-- COMMAND ----------

-- Who got ranked and who did not. Expect 155 TRUE / 72 FALSE.
SELECT has_enough_data, service_gap_label, COUNT(*) AS zips,
       MIN(complaints_all) AS min_complaints, MIN(restaurants) AS min_restaurants
FROM workspace.default.zip_service_gap_index
GROUP BY 1, 2 ORDER BY 1 DESC, 3 DESC;

-- COMMAND ----------

-- The unranked ZIPs and which threshold they missed. Airports, office ZIPs, Financial District.
SELECT zip, borough, complaints_all, restaurants, complaints_before_apr2026, complaints_after_apr2026, population,
       CONCAT_WS(', ',
         CASE WHEN complaints_all < 30 THEN 'under 30 complaints' END,
         CASE WHEN restaurants < 10 THEN 'under 10 restaurants' END,
         CASE WHEN complaints_before_apr2026 < 20 THEN 'under 20 pre-April' END,
         CASE WHEN complaints_after_apr2026 < 5 THEN 'under 5 post-April' END) AS why_unranked
FROM workspace.default.zip_service_gap_index
WHERE NOT has_enough_data
ORDER BY complaints_all DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Decision 9. Per-capita only where population >= 1,000
-- MAGIC **Decision:** 18 ZIPs with no population estimate, 27 with zero, 3 under 1,000 get NULL per-capita columns. Two "Long Island" border ZIPs kept, flagged `is_nyc = FALSE`.
-- MAGIC **Why:** ZIP 10152 has 7 residents. One complaint there is 1,428 per 10k.
-- MAGIC **Assumption:** ACS residential population is the right denominator for 311 calls. It ignores workers and visitors, so commercial ZIPs are under-counted.

-- COMMAND ----------

-- Population data quality. Expect: ok 180, under 1,000 = 3, zero 27, no estimate 18; total ~8.55M.
SELECT population_quality, COUNT(*) AS zips, SUM(population) AS residents,
       SUM(CASE WHEN NOT is_nyc THEN 1 ELSE 0 END) AS long_island_zips
FROM workspace.default.nyc_population_clean
GROUP BY 1 ORDER BY 2 DESC;

-- COMMAND ----------

-- Why the 1,000 floor matters: per-capita rates for tiny ZIPs are absurd.
SELECT p.zip, p.borough, p.population, p.margin_of_error_pct, i.complaints_all,
       ROUND(10000.0 * i.complaints_all / NULLIF(p.population, 0), 1) AS complaints_per_10k_if_we_allowed_it,
       i.complaints_per_10k_residents                                   AS what_the_index_shows
FROM workspace.default.nyc_population_clean p
JOIN workspace.default.zip_service_gap_index i ON i.zip = p.zip
WHERE p.population BETWEEN 1 AND 2000
ORDER BY p.population;

-- COMMAND ----------

-- Per-capita calling rate by borough. Manhattan calls about 2.3x as often per resident as Queens.
SELECT borough,
       SUM(rodent_sightings) AS sightings, SUM(population) AS residents,
       ROUND(10000.0 * SUM(rodent_sightings) / SUM(population), 1) AS sightings_per_10k
FROM workspace.default.zip_service_gap_index
WHERE has_population
GROUP BY 1 ORDER BY 4 DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Decision 10. The index: three rates, equal weight, relative ranks
-- MAGIC **Decision:** `service_gap_index` = 100 x average of three percentile ranks: % auto-closed (no-show), median days (slow response), % restaurants with rodent citations (need). Population is context, not a component.
-- MAGIC **Why:** each is a rate, from a different source, explainable in one sentence. Restaurant citations are the only rodent signal that does not depend on who calls 311.
-- MAGIC **Assumptions:** (a) equal weights, because we had no basis to prefer one; (b) restaurant rodent presence proxies neighborhood rodent presence; (c) percentile ranks make the index *relative*: 90 means worse than 90% of ZIPs, not "90% bad".

-- COMMAND ----------

-- Decompose the index for any ZIP. Edit the list.
SELECT zip, borough, service_gap_rank, zips_ranked, service_gap_index, service_gap_label,
       pct_auto_closed_before_apr2026,      ROUND(no_show_score, 2)        AS no_show_score,
       median_days_to_close_after_apr2026,  ROUND(slow_response_score, 2)  AS slow_response_score,
       rodent_violation_rate_pct,           ROUND(rodent_need_score, 2)    AS rodent_need_score,
       ROUND(100 * (no_show_score + slow_response_score + rodent_need_score) / 3, 1) AS recomputed_index
FROM workspace.default.zip_service_gap_index
WHERE zip IN ('11423', '11367', '10025', '10027', '11430')
ORDER BY service_gap_rank;

-- COMMAND ----------

-- The headline: the index is NEGATIVELY correlated with complaint volume (~ -0.42).
-- The ZIPs that call the most are the best served. Per-capita calling vs inspector-found rodents: ~0.
SELECT ROUND(CORR(service_gap_index, complaints_all), 2)                              AS corr_index_vs_complaints,
       ROUND(CORR(service_gap_index, rodent_sightings_per_10k_residents), 2)          AS corr_index_vs_calls_per_capita,
       ROUND(CORR(rodent_sightings_per_10k_residents, rodent_violation_rate_pct), 2)  AS corr_calls_per_capita_vs_rodent_evidence,
       ROUND(CORR(no_show_score, slow_response_score), 2)                             AS corr_component1_vs_2,
       ROUND(CORR(no_show_score, rodent_need_score), 2)                               AS corr_component1_vs_3
FROM workspace.default.zip_service_gap_index
WHERE has_enough_data;

-- COMMAND ----------

-- Borough summary of the index and its components.
SELECT borough, COUNT(*) AS zips_ranked,
       ROUND(AVG(service_gap_index), 1)                    AS avg_index,
       ROUND(AVG(pct_auto_closed_before_apr2026), 1)       AS avg_pct_auto_closed,
       ROUND(AVG(median_days_to_close_after_apr2026), 1)   AS avg_median_days,
       ROUND(AVG(rodent_violation_rate_pct), 1)            AS avg_pct_restaurants_with_rodents,
       SUM(CASE WHEN is_quiet_zip THEN 1 ELSE 0 END)       AS quiet_zips
FROM workspace.default.zip_service_gap_index
WHERE has_enough_data
GROUP BY 1 ORDER BY avg_index DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Decision 11. Single-location concentration
-- MAGIC **Decision:** every ZIP reports `distinct_locations` and `top_location_share_pct` next to its complaint count. We did **not** remove or cap the 10035 building (1,227 complaints from one lat/long = 82% of the ZIP).
-- MAGIC **Why:** removing it would be editing the data; showing it lets the reader see that the count is one building. This is why complaint counts never rank anything.
-- MAGIC **Assumption:** repeated complaints from one location are real reports, not a data error.

-- COMMAND ----------

-- The busiest single locations in the city. Expect the top one: 10035, 1,227 complaints, all 'Signs of Rodents', 3+ Family Apt. Building.
SELECT zip, borough, latitude, longitude,
       COUNT(*) AS complaints,
       MIN(CAST(created_at AS DATE)) AS first_complaint, MAX(CAST(created_at AS DATE)) AS last_complaint,
       COUNT(DISTINCT CAST(created_at AS DATE)) AS distinct_days,
       MAX(descriptor) AS descriptor, MAX(location_type) AS location_type
FROM workspace.default.rodent_complaints_clean
WHERE latitude IS NOT NULL
GROUP BY 1, 2, 3, 4
ORDER BY complaints DESC
LIMIT 10;

-- COMMAND ----------

-- What 10035 looks like with and without that one building. Rank 1 in the city becomes roughly rank 40.
SELECT zip, complaints_all, distinct_locations, top_location_share_pct,
       complaints_all - ROUND(complaints_all * top_location_share_pct / 100) AS complaints_without_top_location,
       RANK() OVER (ORDER BY complaints_all DESC) AS rank_by_raw_complaints,
       RANK() OVER (ORDER BY complaints_all - ROUND(complaints_all * top_location_share_pct / 100) DESC) AS rank_without_top_location
FROM workspace.default.zip_service_gap_index
ORDER BY complaints_all DESC
LIMIT 12;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## The one-line version for judges
-- MAGIC > Every number on this dashboard is a rate, never a count; every rate excludes complaints the city closed in under a minute; and every ZIP tells you when it does not have enough data to be ranked. The biggest assumption is that "closed in 60 seconds" means "nobody came", because the export has no resolution text.