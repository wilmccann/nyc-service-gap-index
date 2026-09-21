-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Build Notebook (DDL/DML statements)
-- MAGIC Builds the clean tables and the ZIP Service Gap Index from the raw uploads, in dependency order:
-- MAGIC `raw` → (1 complaints, 2 violations, 3b population) → 3 restaurants → 4 index → 4b dashboard views → 4c Genie view → 5 sanity checks.
-- MAGIC
-- MAGIC Every CREATE cell also re-applies its table and column COMMENTs so a rebuild never strips the descriptions Genie reads.
-- MAGIC Run All from the top; Cell 5 shows `actual` vs `expected` for every table.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## CELL 1: Clean 311 rodent complaints  (one row per complaint)

-- COMMAND ----------

CREATE OR REPLACE TABLE workspace.default.rodent_complaints_clean AS
WITH base AS (
  SELECT
    CAST(unique_key AS STRING)                                   AS complaint_id,
    CAST(created_date AS TIMESTAMP)                              AS created_at,
    CAST(closed_date  AS TIMESTAMP)                              AS closed_at,
    status,
    descriptor,
    location_type,
    LPAD(SUBSTRING(CAST(incident_zip AS STRING), 1, 5), 5, '0')  AS zip_raw,
    INITCAP(borough)                                             AS borough,
    CAST(latitude  AS DOUBLE)                                    AS latitude,
    CAST(longitude AS DOUBLE)                                    AS longitude
  FROM workspace.default.rat_sightings
)
SELECT
  complaint_id,
  created_at,
  closed_at,
  status,
  descriptor,
  location_type,
  CASE WHEN zip_raw RLIKE '^1[01][0-9]{3}$' THEN zip_raw END      AS zip,
  borough,
  latitude,
  longitude,
  -- our written definition: a rodent SIGHTING is direct evidence of rodents.
  -- "Condition Attracting Rodents" (garbage, harborage) is kept but flagged separately.
  CASE WHEN descriptor IN ('Rat Sighting','Mouse Sighting','Signs of Rodents') THEN TRUE ELSE FALSE END AS is_rodent_sighting,
  CASE WHEN descriptor = 'Rat Sighting' THEN TRUE ELSE FALSE END                                        AS is_rat_sighting,
  -- minutes from creation to closure (NULL if still open)
  TIMESTAMPDIFF(MINUTE, created_at, closed_at)                     AS minutes_to_close,
  TIMESTAMPDIFF(MINUTE, created_at, closed_at) / 1440.0            AS days_to_close,
  -- THE KEY FLAG: closed within 60 seconds of being filed = system auto-close, no inspection.
  CASE WHEN TIMESTAMPDIFF(MINUTE, created_at, closed_at) <= 1 THEN TRUE ELSE FALSE END AS is_auto_closed,
  -- the auto-close practice stopped on 2026-04-20
  CASE WHEN created_at < TIMESTAMP '2026-04-20 00:00:00' THEN 'before_2026-04-20' ELSE 'after_2026-04-20' END AS policy_era,
  CASE
    WHEN closed_at IS NULL THEN 'open'
    WHEN TIMESTAMPDIFF(MINUTE, created_at, closed_at) <= 1 THEN 'auto_closed_no_visit'
    ELSE 'worked'
  END AS outcome,
  DATE_TRUNC('month', created_at)                                  AS created_month
FROM base;

COMMENT ON TABLE workspace.default.rodent_complaints_clean IS
'One row per NYC 311 rodent complaint (complaint_type = Rodent), Jan 2025 to Sep 2026, ~50,954 rows. Source: rat_sightings.csv. ZIP normalized to 5 digits, non-NYC ZIPs set to NULL. Includes an is_auto_closed flag: complaints closed within 60 seconds of filing were closed by the system without an inspection (44% of all complaints, about 60% of complaints before 2026-04-20, 0% after).';
ALTER TABLE workspace.default.rodent_complaints_clean ALTER COLUMN complaint_id       COMMENT '311 unique key for the complaint (string).';
ALTER TABLE workspace.default.rodent_complaints_clean ALTER COLUMN created_at         COMMENT 'Timestamp the complaint was filed with 311.';
ALTER TABLE workspace.default.rodent_complaints_clean ALTER COLUMN closed_at          COMMENT 'Timestamp the complaint was closed. NULL if still open (In Progress).';
ALTER TABLE workspace.default.rodent_complaints_clean ALTER COLUMN status             COMMENT '311 status: Closed, In Progress, or Unspecified.';
ALTER TABLE workspace.default.rodent_complaints_clean ALTER COLUMN descriptor         COMMENT 'What was reported: Rat Sighting, Mouse Sighting, Signs of Rodents, or Condition Attracting Rodents.';
ALTER TABLE workspace.default.rodent_complaints_clean ALTER COLUMN location_type      COMMENT 'Type of place reported, e.g. 3+ Family Apt. Building, 1-2 Family Dwelling, Sidewalk, Commercial Building.';
ALTER TABLE workspace.default.rodent_complaints_clean ALTER COLUMN zip                COMMENT '5-digit NYC ZIP code of the incident (string). NULL if not a valid NYC ZIP.';
ALTER TABLE workspace.default.rodent_complaints_clean ALTER COLUMN borough            COMMENT 'Borough: Manhattan, Brooklyn, Queens, Bronx, Staten Island.';
ALTER TABLE workspace.default.rodent_complaints_clean ALTER COLUMN latitude           COMMENT 'Latitude of the incident location.';
ALTER TABLE workspace.default.rodent_complaints_clean ALTER COLUMN longitude          COMMENT 'Longitude of the incident location.';
ALTER TABLE workspace.default.rodent_complaints_clean ALTER COLUMN is_rodent_sighting COMMENT 'TRUE if descriptor is Rat Sighting, Mouse Sighting, or Signs of Rodents (direct evidence of rodents). FALSE for Condition Attracting Rodents. This is our definition of a rodent complaint.';
ALTER TABLE workspace.default.rodent_complaints_clean ALTER COLUMN is_rat_sighting    COMMENT 'TRUE if descriptor is exactly Rat Sighting.';
ALTER TABLE workspace.default.rodent_complaints_clean ALTER COLUMN minutes_to_close   COMMENT 'Minutes between created_at and closed_at. NULL if still open.';
ALTER TABLE workspace.default.rodent_complaints_clean ALTER COLUMN days_to_close      COMMENT 'Days (decimal) between created_at and closed_at. NULL if still open. Use MEDIAN, not AVG. Exclude auto-closed rows when measuring real response time.';
ALTER TABLE workspace.default.rodent_complaints_clean ALTER COLUMN is_auto_closed     COMMENT 'TRUE if the complaint was closed within 60 seconds of being filed, meaning the system closed it automatically and no inspector visited. This is how we measure whether the city showed up.';
ALTER TABLE workspace.default.rodent_complaints_clean ALTER COLUMN policy_era         COMMENT 'before_2026-04-20 (city auto-closed ~60% of complaints) or after_2026-04-20 (auto-closing stopped; all complaints are worked).';
ALTER TABLE workspace.default.rodent_complaints_clean ALTER COLUMN outcome            COMMENT 'open, auto_closed_no_visit, or worked (closed after more than 1 minute, i.e. a person handled it).';
ALTER TABLE workspace.default.rodent_complaints_clean ALTER COLUMN created_month      COMMENT 'First day of the month the complaint was filed. Use for monthly trends.';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## CELL 2: Clean restaurant violations  (one row per violation, as delivered)

-- COMMAND ----------

CREATE OR REPLACE TABLE workspace.default.restaurant_violations_clean AS
WITH base AS (
  SELECT *, LPAD(SUBSTRING(CAST(zipcode AS STRING), 1, 5), 5, '0') AS zip_raw
  FROM workspace.default.restaurant_inspections
)
SELECT
  CAST(camis AS STRING)                                             AS camis,
  dba                                                               AS restaurant_name,
  CASE WHEN boro = '0' THEN NULL ELSE boro END                      AS borough,
  CASE WHEN zip_raw RLIKE '^1[01][0-9]{3}$' THEN zip_raw END        AS zip,
  cuisine_description                                               AS cuisine,
  CAST(inspection_date AS DATE)                                     AS inspection_date,
  violation_code,
  violation_description,
  critical_flag,
  TRY_CAST(score AS INT)                                            AS inspection_score,
  grade,
  CASE WHEN violation_code IN ('04K','04L') THEN TRUE ELSE FALSE END AS is_rodent_violation,
  CASE WHEN violation_code = '04K' THEN TRUE ELSE FALSE END          AS is_rat_violation,
  CASE WHEN violation_code = '04L' THEN TRUE ELSE FALSE END          AS is_mouse_violation,
  CASE WHEN violation_code = '08A' THEN TRUE ELSE FALSE END          AS is_harborage_violation,
  CASE WHEN violation_code IS NULL THEN TRUE ELSE FALSE END          AS is_no_violation_row
FROM base;

COMMENT ON TABLE workspace.default.restaurant_violations_clean IS
'One row per VIOLATION cited at a NYC restaurant inspection (NOT one row per restaurant or per inspection), Jan 2025 to Sep 2026, ~158,000 rows, ~26,100 restaurants, ~44,400 inspections. Source: restaurant_inspections.csv. To count restaurants always use COUNT(DISTINCT camis). To count inspections use COUNT(DISTINCT camis, inspection_date). Rodent violations are codes 04K (rats) and 04L (mice). 08A is harborage/conditions conducive to pests. ~1,800 rows have NULL violation_code meaning an inspection with no violations.';
ALTER TABLE workspace.default.restaurant_violations_clean ALTER COLUMN camis                  COMMENT 'Unique restaurant ID (string). Count restaurants with COUNT(DISTINCT camis).';
ALTER TABLE workspace.default.restaurant_violations_clean ALTER COLUMN restaurant_name        COMMENT 'Restaurant name (doing business as).';
ALTER TABLE workspace.default.restaurant_violations_clean ALTER COLUMN borough                COMMENT 'Borough: Manhattan, Brooklyn, Queens, Bronx, Staten Island. NULL for a few out-of-city rows.';
ALTER TABLE workspace.default.restaurant_violations_clean ALTER COLUMN zip                    COMMENT '5-digit NYC ZIP code of the restaurant (string). NULL for ~1,500 rows with missing or non-NYC ZIP.';
ALTER TABLE workspace.default.restaurant_violations_clean ALTER COLUMN cuisine                COMMENT 'Cuisine description, e.g. American, Chinese, Pizza.';
ALTER TABLE workspace.default.restaurant_violations_clean ALTER COLUMN inspection_date        COMMENT 'Date of the inspection. One inspection = one (camis, inspection_date) pair.';
ALTER TABLE workspace.default.restaurant_violations_clean ALTER COLUMN violation_code         COMMENT 'DOHMH violation code, e.g. 04K = rats, 04L = mice, 08A = harborage conducive to pests, 04M = roaches, 04N = flies. NULL means no violation at that inspection.';
ALTER TABLE workspace.default.restaurant_violations_clean ALTER COLUMN violation_description  COMMENT 'Text description of the violation.';
ALTER TABLE workspace.default.restaurant_violations_clean ALTER COLUMN critical_flag          COMMENT 'Critical, Not Critical, or Not Applicable.';
ALTER TABLE workspace.default.restaurant_violations_clean ALTER COLUMN inspection_score       COMMENT 'Total inspection points (higher is worse; 0-13 = A, 14-27 = B, 28+ = C). Same value repeats on every row of the same inspection.';
ALTER TABLE workspace.default.restaurant_violations_clean ALTER COLUMN grade                  COMMENT 'Letter grade A, B, C; N = not yet graded, Z = grade pending, P = grade pending after reopening. NULL when no grade was issued at that inspection.';
ALTER TABLE workspace.default.restaurant_violations_clean ALTER COLUMN is_rodent_violation    COMMENT 'TRUE if violation_code is 04K (rats) or 04L (mice): evidence of rodents found by an inspector.';
ALTER TABLE workspace.default.restaurant_violations_clean ALTER COLUMN is_rat_violation       COMMENT 'TRUE if violation_code is 04K (evidence of rats or live rats).';
ALTER TABLE workspace.default.restaurant_violations_clean ALTER COLUMN is_mouse_violation     COMMENT 'TRUE if violation_code is 04L (evidence of mice or live mice).';
ALTER TABLE workspace.default.restaurant_violations_clean ALTER COLUMN is_harborage_violation COMMENT 'TRUE if violation_code is 08A (conditions conducive to rodents, insects, or other pests).';
ALTER TABLE workspace.default.restaurant_violations_clean ALTER COLUMN is_no_violation_row    COMMENT 'TRUE if this row represents an inspection with no violations cited.';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## CELL 3: Restaurants  (one row per restaurant)

-- COMMAND ----------

CREATE OR REPLACE TABLE workspace.default.restaurants_clean AS
SELECT
  camis,
  MAX(restaurant_name)                                   AS restaurant_name,
  MAX(borough)                                           AS borough,
  MAX(zip)                                               AS zip,
  MAX(cuisine)                                           AS cuisine,
  COUNT(DISTINCT inspection_date)                        AS inspections,
  MIN(inspection_date)                                   AS first_inspection,
  MAX(inspection_date)                                   AS last_inspection,
  SUM(CASE WHEN violation_code IS NOT NULL THEN 1 ELSE 0 END) AS violations,
  MAX(CASE WHEN is_rodent_violation THEN 1 ELSE 0 END) = 1   AS had_rodent_violation,
  MAX(CASE WHEN is_rat_violation THEN 1 ELSE 0 END) = 1      AS had_rat_violation,
  MAX(CASE WHEN is_mouse_violation THEN 1 ELSE 0 END) = 1    AS had_mouse_violation,
  MAX(CASE WHEN is_harborage_violation THEN 1 ELSE 0 END) = 1 AS had_harborage_violation
FROM workspace.default.restaurant_violations_clean
GROUP BY camis;

COMMENT ON TABLE workspace.default.restaurants_clean IS
'One row per NYC restaurant (camis) inspected Jan 2025 to Sep 2026, ~26,100 rows. Built from restaurant_violations_clean. Use this table to count restaurants or compute the share of restaurants with rodent evidence.';
ALTER TABLE workspace.default.restaurants_clean ALTER COLUMN camis                   COMMENT 'Unique restaurant ID (string).';
ALTER TABLE workspace.default.restaurants_clean ALTER COLUMN restaurant_name         COMMENT 'Restaurant name.';
ALTER TABLE workspace.default.restaurants_clean ALTER COLUMN borough                 COMMENT 'Borough of the restaurant.';
ALTER TABLE workspace.default.restaurants_clean ALTER COLUMN zip                     COMMENT '5-digit NYC ZIP code (string). NULL if missing.';
ALTER TABLE workspace.default.restaurants_clean ALTER COLUMN cuisine                 COMMENT 'Cuisine description.';
ALTER TABLE workspace.default.restaurants_clean ALTER COLUMN inspections             COMMENT 'Number of distinct inspection dates in the period.';
ALTER TABLE workspace.default.restaurants_clean ALTER COLUMN first_inspection        COMMENT 'Earliest inspection date in the period.';
ALTER TABLE workspace.default.restaurants_clean ALTER COLUMN last_inspection         COMMENT 'Latest inspection date in the period.';
ALTER TABLE workspace.default.restaurants_clean ALTER COLUMN violations              COMMENT 'Total violations cited across all inspections in the period.';
ALTER TABLE workspace.default.restaurants_clean ALTER COLUMN had_rodent_violation    COMMENT 'TRUE if the restaurant was cited for rats (04K) or mice (04L) at least once.';
ALTER TABLE workspace.default.restaurants_clean ALTER COLUMN had_rat_violation       COMMENT 'TRUE if cited for rats (04K) at least once.';
ALTER TABLE workspace.default.restaurants_clean ALTER COLUMN had_mouse_violation     COMMENT 'TRUE if cited for mice (04L) at least once.';
ALTER TABLE workspace.default.restaurants_clean ALTER COLUMN had_harborage_violation COMMENT 'TRUE if cited for pest harborage conditions (08A) at least once.';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## CELL 3b: Population by ZIP  (one row per ZIP; depends only on the raw upload)
-- MAGIC Raw table: workspace.default.nyc_population_by_zip (zip_code INT, borough, population INT, margin_of_error INT)

-- COMMAND ----------

CREATE OR REPLACE TABLE workspace.default.nyc_population_clean AS
SELECT
  LPAD(CAST(zip_code AS STRING), 5, '0')                            AS zip,
  borough,
  population,
  margin_of_error,
  ROUND(100.0 * margin_of_error / NULLIF(population, 0), 1)        AS margin_of_error_pct,
  CASE WHEN population IS NULL THEN 'no estimate (PO box / office ZIP)'
       WHEN population = 0    THEN 'zero (office, park, or airport ZIP)'
       WHEN population < 1000 THEN 'under 1,000 residents'
       ELSE 'ok' END                                                AS population_quality,
  CASE WHEN population >= 1000 THEN TRUE ELSE FALSE END             AS usable_for_per_capita,
  CASE WHEN borough = 'Long Island' THEN FALSE ELSE TRUE END        AS is_nyc
FROM workspace.default.nyc_population_by_zip
WHERE zip_code IS NOT NULL;

COMMENT ON TABLE workspace.default.nyc_population_clean IS
'Residential population per NYC ZIP code (American Community Survey estimate with margin of error), one row per ZIP, 231 rows, total about 8.55 million. 18 ZIPs have no estimate and 27 have zero population (office-building, park, and airport ZIPs such as 11371 LaGuardia). Two ZIPs (11001, 11040) are labelled Long Island and straddle the Queens/Nassau border. Use usable_for_per_capita = TRUE (population at least 1,000) before dividing by population.';
ALTER TABLE workspace.default.nyc_population_clean ALTER COLUMN zip                   COMMENT '5-digit ZIP code (string). Primary key. Joins to zip in the other tables.';
ALTER TABLE workspace.default.nyc_population_clean ALTER COLUMN borough               COMMENT 'Borough: Manhattan, Brooklyn, Queens, Bronx, Staten Island, or Long Island for two border ZIPs.';
ALTER TABLE workspace.default.nyc_population_clean ALTER COLUMN population            COMMENT 'Estimated residents. NULL = no estimate. 0 = non-residential ZIP.';
ALTER TABLE workspace.default.nyc_population_clean ALTER COLUMN margin_of_error       COMMENT 'Survey margin of error on population (plus or minus residents).';
ALTER TABLE workspace.default.nyc_population_clean ALTER COLUMN margin_of_error_pct   COMMENT 'Margin of error as a percent of population. Over 20% means the estimate is unreliable.';
ALTER TABLE workspace.default.nyc_population_clean ALTER COLUMN population_quality    COMMENT 'ok, under 1,000 residents, zero (office, park, or airport ZIP), or no estimate (PO box / office ZIP).';
ALTER TABLE workspace.default.nyc_population_clean ALTER COLUMN usable_for_per_capita COMMENT 'TRUE if population is at least 1,000, so per-10k-resident rates are meaningful.';
ALTER TABLE workspace.default.nyc_population_clean ALTER COLUMN is_nyc                COMMENT 'FALSE for the two Long Island border ZIPs (11001, 11040).';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## CELL 4: ZIP Service Gap Index  (one row per ZIP)

-- COMMAND ----------

CREATE OR REPLACE TABLE workspace.default.zip_service_gap_index AS
WITH c AS (   -- 311 side
  SELECT
    zip,
    MODE(borough)                                                       AS borough,
    COUNT(*)                                                            AS complaints_all,
    SUM(CASE WHEN is_rodent_sighting THEN 1 ELSE 0 END)                 AS rodent_sightings,
    SUM(CASE WHEN is_rat_sighting THEN 1 ELSE 0 END)                    AS rat_sightings,
    SUM(CASE WHEN NOT is_rodent_sighting THEN 1 ELSE 0 END)             AS condition_complaints,
    COUNT(DISTINCT latitude, longitude)                                 AS distinct_locations,
    SUM(CASE WHEN outcome = 'open' THEN 1 ELSE 0 END)                   AS complaints_open,
    -- era 1: did the city show up at all?
    SUM(CASE WHEN policy_era = 'before_2026-04-20' THEN 1 ELSE 0 END)   AS complaints_before_apr2026,
    SUM(CASE WHEN policy_era = 'before_2026-04-20' AND is_auto_closed THEN 1 ELSE 0 END) AS auto_closed_before_apr2026,
    -- era 2: how fast, now that everything is worked (Apr 20 - Jul 31 2026; Aug/Sep excluded as too recent)
    SUM(CASE WHEN created_at >= TIMESTAMP '2026-04-20 00:00:00' AND created_at < TIMESTAMP '2026-08-01 00:00:00' THEN 1 ELSE 0 END) AS complaints_after_apr2026,
    MEDIAN(CASE WHEN created_at >= TIMESTAMP '2026-04-20 00:00:00' AND created_at < TIMESTAMP '2026-08-01 00:00:00' AND NOT is_auto_closed THEN days_to_close END) AS median_days_to_close_after_apr2026
  FROM workspace.default.rodent_complaints_clean
  WHERE zip IS NOT NULL
  GROUP BY zip
),
hot AS (  -- share of a ZIP's complaints that come from its single busiest location
  SELECT zip, MAX(n) AS top_location_complaints
  FROM (SELECT zip, latitude, longitude, COUNT(*) n FROM workspace.default.rodent_complaints_clean WHERE zip IS NOT NULL AND latitude IS NOT NULL GROUP BY zip, latitude, longitude)
  GROUP BY zip
),
r AS (   -- restaurant side
  SELECT
    zip,
    MODE(borough)                                                       AS borough,
    COUNT(*)                                                            AS restaurants,
    SUM(inspections)                                                    AS inspections,
    SUM(CASE WHEN had_rodent_violation THEN 1 ELSE 0 END)               AS restaurants_with_rodent_violation,
    SUM(CASE WHEN had_rat_violation THEN 1 ELSE 0 END)                  AS restaurants_with_rat_violation
  FROM workspace.default.restaurants_clean
  WHERE zip IS NOT NULL
  GROUP BY zip
),
p AS (   -- population side
  SELECT zip, borough, population, margin_of_error_pct, usable_for_per_capita
  FROM workspace.default.nyc_population_clean
),
j AS (
  SELECT
    COALESCE(c.zip, r.zip)                                              AS zip,
    COALESCE(c.borough, r.borough, p.borough)                           AS borough,
    p.population,
    p.margin_of_error_pct                                               AS population_moe_pct,
    COALESCE(p.usable_for_per_capita, FALSE)                            AS has_population,
    COALESCE(c.complaints_all, 0)                                       AS complaints_all,
    COALESCE(c.rodent_sightings, 0)                                     AS rodent_sightings,
    COALESCE(c.rat_sightings, 0)                                        AS rat_sightings,
    COALESCE(c.condition_complaints, 0)                                 AS condition_complaints,
    COALESCE(c.distinct_locations, 0)                                   AS distinct_locations,
    ROUND(100.0 * hot.top_location_complaints / NULLIF(c.complaints_all, 0), 1) AS top_location_share_pct,
    COALESCE(c.complaints_open, 0)                                      AS complaints_open,
    COALESCE(c.complaints_before_apr2026, 0)                            AS complaints_before_apr2026,
    COALESCE(c.auto_closed_before_apr2026, 0)                           AS auto_closed_before_apr2026,
    ROUND(100.0 * c.auto_closed_before_apr2026 / NULLIF(c.complaints_before_apr2026, 0), 1) AS pct_auto_closed_before_apr2026,
    COALESCE(c.complaints_after_apr2026, 0)                             AS complaints_after_apr2026,
    ROUND(c.median_days_to_close_after_apr2026, 1)                      AS median_days_to_close_after_apr2026,
    COALESCE(r.restaurants, 0)                                          AS restaurants,
    COALESCE(r.inspections, 0)                                          AS inspections,
    COALESCE(r.restaurants_with_rodent_violation, 0)                    AS restaurants_with_rodent_violation,
    COALESCE(r.restaurants_with_rat_violation, 0)                       AS restaurants_with_rat_violation,
    ROUND(100.0 * r.restaurants_with_rodent_violation / NULLIF(r.restaurants, 0), 1) AS rodent_violation_rate_pct,
    ROUND(100.0 * c.complaints_all / NULLIF(r.restaurants, 0), 1)       AS complaints_per_100_restaurants,
    -- per-capita rates, only where population >= 1000
    CASE WHEN p.usable_for_per_capita THEN ROUND(10000.0 * c.complaints_all   / p.population, 1) END AS complaints_per_10k_residents,
    CASE WHEN p.usable_for_per_capita THEN ROUND(10000.0 * c.rodent_sightings / p.population, 1) END AS rodent_sightings_per_10k_residents,
    CASE WHEN p.usable_for_per_capita THEN ROUND(10000.0 * r.restaurants      / p.population, 1) END AS restaurants_per_10k_residents,
    CASE WHEN COALESCE(c.complaints_all,0) >= 30 AND COALESCE(r.restaurants,0) >= 10
         AND COALESCE(c.complaints_before_apr2026,0) >= 20 AND COALESCE(c.complaints_after_apr2026,0) >= 5
         THEN TRUE ELSE FALSE END                                       AS has_enough_data
  FROM c
  FULL OUTER JOIN r ON c.zip = r.zip
  LEFT JOIN hot ON hot.zip = COALESCE(c.zip, r.zip)
  LEFT JOIN p   ON p.zip   = COALESCE(c.zip, r.zip)
),
ranked AS (
  SELECT
    j.*,
    -- percentile ranks among ZIPs with enough data (0 = best, 1 = worst)
    CASE WHEN has_enough_data THEN PERCENT_RANK() OVER (PARTITION BY has_enough_data ORDER BY pct_auto_closed_before_apr2026) END      AS no_show_score,
    CASE WHEN has_enough_data THEN PERCENT_RANK() OVER (PARTITION BY has_enough_data ORDER BY median_days_to_close_after_apr2026) END  AS slow_response_score,
    CASE WHEN has_enough_data THEN PERCENT_RANK() OVER (PARTITION BY has_enough_data ORDER BY rodent_violation_rate_pct) END           AS rodent_need_score
  FROM j
)
SELECT
  ranked.*,
  ROUND(100.0 * (no_show_score + slow_response_score + rodent_need_score) / 3.0, 1) AS service_gap_index,
  CASE WHEN has_enough_data THEN RANK() OVER (PARTITION BY has_enough_data ORDER BY (no_show_score + slow_response_score + rodent_need_score) DESC) END AS service_gap_rank,
  SUM(CASE WHEN has_enough_data THEN 1 ELSE 0 END) OVER ()             AS zips_ranked,
  -- "quiet ZIP": inspectors find rodents at an above-median share of restaurants, but residents call 311 at a below-median rate
  CASE WHEN has_enough_data AND has_population
        AND rodent_need_score >= 0.5
        AND rodent_sightings_per_10k_residents < MEDIAN(CASE WHEN has_enough_data AND has_population THEN rodent_sightings_per_10k_residents END) OVER ()
       THEN TRUE ELSE FALSE END                                         AS is_quiet_zip,
  CASE
    WHEN NOT has_enough_data THEN 'Not enough data to rank this ZIP'
    WHEN (no_show_score + slow_response_score + rodent_need_score) / 3.0 >= 0.66 THEN 'Large service gap'
    WHEN (no_show_score + slow_response_score + rodent_need_score) / 3.0 >= 0.33 THEN 'Moderate service gap'
    ELSE 'Small service gap'
  END AS service_gap_label
FROM ranked;

COMMENT ON TABLE workspace.default.zip_service_gap_index IS
'Service Gap Index: one row per NYC ZIP code (about 200 ZIPs) combining 311 rodent complaints and restaurant inspection evidence. service_gap_index is 0-100, higher = bigger gap between rodent need and city response. It is the average of three percentile ranks: (1) share of complaints auto-closed without a visit before 2026-04-20, (2) median days to close a complaint after 2026-04-20, (3) share of restaurants cited for rats or mice. ZIPs with too little data have has_enough_data = FALSE and NULL index. Not a rat map: 311 counts measure who calls, not where rats are.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN zip                                COMMENT '5-digit NYC ZIP code (string). Primary key.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN borough                            COMMENT 'Borough: Manhattan, Brooklyn, Queens, Bronx, Staten Island.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN complaints_all                     COMMENT 'All 311 rodent complaints in the ZIP, Jan 2025 to Sep 2026 (all four descriptors).';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN rodent_sightings                   COMMENT 'Complaints that are Rat Sighting, Mouse Sighting, or Signs of Rodents (our rodent complaint definition).';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN rat_sightings                      COMMENT 'Complaints with descriptor Rat Sighting only.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN condition_complaints               COMMENT 'Complaints with descriptor Condition Attracting Rodents (garbage/harborage, not a sighting).';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN distinct_locations                 COMMENT 'Number of distinct lat/long points complaints came from. Compare to complaints_all to spot repeat callers.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN top_location_share_pct             COMMENT 'Percent of the ZIP''s complaints that came from its single busiest location. High values (e.g. 82% in 10035) mean one building drives the count.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN complaints_open                    COMMENT 'Complaints still In Progress.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN complaints_before_apr2026          COMMENT 'Complaints filed before 2026-04-20, when the city still auto-closed complaints.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN auto_closed_before_apr2026         COMMENT 'Of those, how many were closed within 60 seconds with no inspection.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN pct_auto_closed_before_apr2026     COMMENT 'Percent of pre-2026-04-20 complaints closed without a visit. Citywide about 60%. Higher = city showed up less. Component 1 of the index.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN complaints_after_apr2026           COMMENT 'Complaints filed 2026-04-20 to 2026-07-31 (after auto-closing stopped; Aug/Sep excluded as too recent to be closed).';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN median_days_to_close_after_apr2026 COMMENT 'Median days to close a complaint filed 2026-04-20 to 2026-07-31. Citywide about 10 days. Higher = slower. Component 2 of the index.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN restaurants                        COMMENT 'Distinct restaurants (camis) inspected in the ZIP, Jan 2025 to Sep 2026.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN inspections                        COMMENT 'Total restaurant inspections in the ZIP.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN restaurants_with_rodent_violation  COMMENT 'Restaurants cited at least once for rats (04K) or mice (04L).';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN restaurants_with_rat_violation     COMMENT 'Restaurants cited at least once for rats (04K).';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN rodent_violation_rate_pct          COMMENT 'Percent of the ZIP''s restaurants cited for rats or mice. Independent evidence of rodent presence that does not depend on who calls 311. Citywide about 24%. Component 3 of the index.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN complaints_per_100_restaurants     COMMENT 'Complaints per 100 restaurants. Context only.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN population                         COMMENT 'Estimated residents (ACS). NULL if no estimate.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN population_moe_pct                 COMMENT 'Population margin of error as a percent of population.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN has_population                     COMMENT 'TRUE if population is at least 1,000, so per-10k-resident rates are shown.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN complaints_per_10k_residents       COMMENT 'All rodent complaints per 10,000 residents, Jan 2025 to Sep 2026. NULL when has_population is FALSE. Measures how much a ZIP calls 311, not how many rats it has.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN rodent_sightings_per_10k_residents COMMENT 'Rodent sightings (Rat, Mouse, Signs of Rodents) per 10,000 residents. Citywide about 50. Manhattan about 69, Queens about 30. NULL when has_population is FALSE.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN restaurants_per_10k_residents      COMMENT 'Inspected restaurants per 10,000 residents. High values mean a commercial ZIP.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN is_quiet_zip                       COMMENT 'TRUE if inspectors find rodents at an above-median share of the ZIP''s restaurants but residents call 311 at a below-median per-capita rate. These ZIPs likely under-report and are invisible to a complaint-count map.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN has_enough_data                    COMMENT 'TRUE if the ZIP has at least 30 complaints, 10 restaurants, 20 pre-April-2026 complaints and 5 post-April-2026 complaints. Only these ZIPs get an index and rank.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN no_show_score                      COMMENT 'Percentile rank (0 best to 1 worst) of pct_auto_closed_before_apr2026 among ranked ZIPs.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN slow_response_score                COMMENT 'Percentile rank (0 best to 1 worst) of median_days_to_close_after_apr2026 among ranked ZIPs.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN rodent_need_score                  COMMENT 'Percentile rank (0 lowest to 1 highest) of rodent_violation_rate_pct among ranked ZIPs.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN service_gap_index                  COMMENT 'Service Gap Index 0-100 = average of no_show_score, slow_response_score and rodent_need_score times 100. Higher = bigger gap between rodent need and city response. NULL when has_enough_data is FALSE.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN service_gap_rank                   COMMENT 'Rank of the ZIP by service_gap_index, 1 = largest gap (worst served). NULL when not enough data.';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN zips_ranked                        COMMENT 'Total number of ZIPs that received a rank (denominator for service_gap_rank).';
ALTER TABLE workspace.default.zip_service_gap_index ALTER COLUMN service_gap_label                  COMMENT 'Plain-English label: Large, Moderate, Small service gap, or Not enough data to rank this ZIP.';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## CELL 4b: Dashboard views
-- MAGIC The NYC Service Gap Dashboard reads two views on top of `zip_service_gap_index` and the raw `rat_sightings` table:
-- MAGIC `zip_lookup_v` (per-ZIP text, typical values and not-scored reasons for the "Look up your ZIP" page) and
-- MAGIC `borough_metric_shares_v` (each borough's share of five citywide metrics). Definitions are copied verbatim from the source workspace.

-- COMMAND ----------

CREATE OR REPLACE VIEW workspace.default.zip_lookup_v (
  zip COMMENT '5-digit NYC ZIP code (string). Primary key.',
  borough COMMENT 'Borough: Manhattan, Brooklyn, Queens, Bronx, Staten Island.',
  population COMMENT 'Estimated residents (ACS). NULL if no estimate.',
  population_moe_pct COMMENT 'Population margin of error as a percent of population.',
  has_population COMMENT 'TRUE if population is at least 1,000, so per-10k-resident rates are shown.',
  complaints_all COMMENT 'All 311 rodent complaints in the ZIP, Jan 2025 to Sep 2026 (all four descriptors).',
  rodent_sightings COMMENT 'Complaints that are Rat Sighting, Mouse Sighting, or Signs of Rodents (our rodent complaint definition).',
  rat_sightings COMMENT 'Complaints with descriptor Rat Sighting only.',
  condition_complaints COMMENT 'Complaints with descriptor Condition Attracting Rodents (garbage/harborage, not a sighting).',
  distinct_locations COMMENT 'Number of distinct lat/long points complaints came from. Compare to complaints_all to spot repeat callers.',
  top_location_share_pct COMMENT 'Percent of the ZIP''s complaints that came from its single busiest location. High values (e.g. 82% in 10035) mean one building drives the count.',
  complaints_open COMMENT 'Complaints still In Progress.',
  complaints_before_apr2026 COMMENT 'Complaints filed before 2026-04-20, when the city still auto-closed complaints.',
  auto_closed_before_apr2026 COMMENT 'Of those, how many were closed within 60 seconds with no inspection.',
  pct_auto_closed_before_apr2026 COMMENT 'Percent of pre-2026-04-20 complaints closed without a visit. Citywide about 60%. Higher = city showed up less. Component 1 of the index.',
  complaints_after_apr2026 COMMENT 'Complaints filed 2026-04-20 to 2026-07-31 (after auto-closing stopped; Aug/Sep excluded as too recent to be closed).',
  median_days_to_close_after_apr2026 COMMENT 'Median days to close a complaint filed 2026-04-20 to 2026-07-31. Citywide about 10 days. Higher = slower. Component 2 of the index.',
  restaurants COMMENT 'Distinct restaurants (camis) inspected in the ZIP, Jan 2025 to Sep 2026.',
  inspections COMMENT 'Total restaurant inspections in the ZIP.',
  restaurants_with_rodent_violation COMMENT 'Restaurants cited at least once for rats (04K) or mice (04L).',
  restaurants_with_rat_violation COMMENT 'Restaurants cited at least once for rats (04K).',
  rodent_violation_rate_pct COMMENT 'Percent of the ZIP''s restaurants cited for rats or mice. Independent evidence of rodent presence that does not depend on who calls 311. Citywide about 24%. Component 3 of the index.',
  complaints_per_100_restaurants COMMENT 'Complaints per 100 restaurants. Context only.',
  complaints_per_10k_residents COMMENT 'All rodent complaints per 10,000 residents, Jan 2025 to Sep 2026. NULL when has_population is FALSE. Measures how much a ZIP calls 311, not how many rats it has.',
  rodent_sightings_per_10k_residents COMMENT 'Rodent sightings (Rat, Mouse, Signs of Rodents) per 10,000 residents. Citywide about 50. Manhattan about 69, Queens about 30. NULL when has_population is FALSE.',
  restaurants_per_10k_residents COMMENT 'Inspected restaurants per 10,000 residents. High values mean a commercial ZIP.',
  has_enough_data COMMENT 'TRUE if the ZIP has at least 30 complaints, 10 restaurants, 20 pre-April-2026 complaints and 5 post-April-2026 complaints. Only these ZIPs get an index and rank.',
  no_show_score COMMENT 'Percentile rank (0 best to 1 worst) of pct_auto_closed_before_apr2026 among ranked ZIPs.',
  slow_response_score COMMENT 'Percentile rank (0 best to 1 worst) of median_days_to_close_after_apr2026 among ranked ZIPs.',
  rodent_need_score COMMENT 'Percentile rank (0 lowest to 1 highest) of rodent_violation_rate_pct among ranked ZIPs.',
  service_gap_index COMMENT 'Service Gap Index 0-100 = average of no_show_score, slow_response_score and rodent_need_score times 100. Higher = bigger gap between rodent need and city response. NULL when has_enough_data is FALSE.',
  service_gap_rank COMMENT 'Rank of the ZIP by service_gap_index, 1 = largest gap (worst served). NULL when not enough data.',
  zips_ranked COMMENT 'Total number of ZIPs that received a rank (denominator for service_gap_rank).',
  is_quiet_zip COMMENT 'TRUE if inspectors find rodents at an above-median share of the ZIP''s restaurants but residents call 311 at a below-median per-capita rate. These ZIPs likely under-report and are invisible to a complaint-count map.',
  service_gap_label COMMENT 'Plain-English label: Large, Moderate, Small service gap, or Not enough data to rank this ZIP.',
  not_scored_reason,
  is_borderline,
  typical_pct_auto_closed,
  typical_median_days_to_close,
  typical_rodent_violation_rate,
  summary_sentence,
  population_text)
WITH SCHEMA COMPENSATION
AS WITH typical AS (
  SELECT
    percentile_approx(CAST(pct_auto_closed_before_apr2026 AS DOUBLE), 0.5) AS typical_pct_auto_closed,
    percentile_approx(median_days_to_close_after_apr2026, 0.5) AS typical_median_days_to_close,
    percentile_approx(CAST(rodent_violation_rate_pct AS DOUBLE), 0.5) AS typical_rodent_violation_rate
  FROM workspace.default.zip_service_gap_index
  WHERE has_enough_data = TRUE
),
checks AS (
  SELECT
    z.*,
    (COALESCE(complaints_all, 0) < 30) AS fail_total,
    (COALESCE(restaurants, 0) < 10) AS fail_rest,
    (COALESCE(complaints_before_apr2026, 0) < 20) AS fail_before,
    (COALESCE(complaints_after_apr2026, 0) < 5) AS fail_after
  FROM workspace.default.zip_service_gap_index z
),
reasons AS (
  SELECT
    c.*,
    concat_ws('; ',
      CASE WHEN fail_total THEN concat(COALESCE(complaints_all, 0), ' complaints in total, needs 30') END,
      CASE WHEN fail_rest THEN concat(COALESCE(restaurants, 0), ' inspected restaurants, needs 10') END,
      CASE WHEN fail_before THEN concat(COALESCE(complaints_before_apr2026, 0), ' complaints filed before April 20, 2026, needs 20, so the share auto-closed is unreliable') END,
      CASE WHEN fail_after THEN concat(COALESCE(complaints_after_apr2026, 0), ' complaints filed April 20 to July 31, 2026, needs 5, so median time to close is unreliable') END
    ) AS reason_text,
    CAST(fail_total AS INT) + CAST(fail_rest AS INT) + CAST(fail_before AS INT) + CAST(fail_after AS INT) AS n_fail,
    GREATEST(
      30 - COALESCE(complaints_all, 0),
      10 - COALESCE(restaurants, 0),
      20 - COALESCE(complaints_before_apr2026, 0),
      5 - COALESCE(complaints_after_apr2026, 0)
    ) AS max_shortfall
  FROM checks c
),
labeled AS (
  SELECT
    r.*,
    CASE WHEN r.has_enough_data THEN NULL
         ELSE concat('Not scored: ', COALESCE(NULLIF(r.reason_text, ''), 'insufficient data'), '.')
    END AS not_scored_reason
  FROM reasons r
)
SELECT
  l.* EXCEPT (fail_total, fail_rest, fail_before, fail_after, reason_text, n_fail, max_shortfall),
  (NOT l.has_enough_data AND l.n_fail = 1 AND l.max_shortfall <= 3) AS is_borderline,
  t.typical_pct_auto_closed,
  t.typical_median_days_to_close,
  t.typical_rodent_violation_rate,
  CASE WHEN l.has_enough_data
    THEN concat('ZIP ', l.zip, ' (', l.borough, ') scores ', round(l.service_gap_index, 1),
                ' out of 100 (higher means a bigger gap), ranked ', l.service_gap_rank, ' of ', l.zips_ranked, '.')
    ELSE concat('ZIP ', l.zip, ' (', l.borough, ') is not scored. ', l.not_scored_reason, ' Figures below are context only.')
  END AS summary_sentence,
  CASE WHEN l.has_population
    THEN concat(format_number(l.population, 0), ' residents (margin of error ', l.population_moe_pct, '%)')
    ELSE 'No Census population estimate for this ZIP'
  END AS population_text
FROM labeled l
CROSS JOIN typical t;

-- COMMAND ----------

CREATE OR REPLACE VIEW workspace.default.borough_metric_shares_v (
  ord,
  metric,
  borough,
  raw_value,
  share_of_metric)
WITH SCHEMA COMPENSATION
AS WITH idx AS (
  SELECT initcap(borough) AS borough,
    CAST(sum(CASE WHEN has_population THEN complaints_all END)
         / sum(CASE WHEN has_population THEN population END) * 10000 AS DOUBLE) AS complaints_per_10k,
    CAST(100.0 * sum(auto_closed_before_apr2026) / sum(complaints_before_apr2026) AS DOUBLE) AS pct_closed_in_minute,
    CAST(100.0 * sum(restaurants_with_rodent_violation) / sum(restaurants) AS DOUBLE) AS pct_cited,
    CAST(sum(inspections) / sum(restaurants) AS DOUBLE) AS insp_per_restaurant
  FROM workspace.default.zip_service_gap_index
  WHERE borough IS NOT NULL
  GROUP BY initcap(borough)
),
days AS (
  SELECT initcap(borough) AS borough,
    CAST(percentile_approx(
      CASE WHEN closed_date >= created_date
           THEN (unix_timestamp(closed_date) - unix_timestamp(created_date)) / 86400.0 END, 0.5) AS DOUBLE) AS median_days
  FROM workspace.default.rat_sightings
  WHERE created_date >= '2026-04-20' AND created_date < '2026-08-01' AND borough <> 'Unspecified'
  GROUP BY initcap(borough)
),
wide AS (
  SELECT i.borough, i.complaints_per_10k, i.pct_closed_in_minute, d.median_days, i.pct_cited, i.insp_per_restaurant
  FROM idx i JOIN days d ON i.borough = d.borough
),
long AS (
  SELECT borough, stack(5,
    1, '311 complaints per 10k residents', complaints_per_10k,
    2, 'Closed within a minute (filed before Apr 20)', pct_closed_in_minute,
    3, 'Median days to close (filed after Apr 20)', median_days,
    4, 'Restaurants cited for rats or mice', pct_cited,
    5, 'Inspections per restaurant', insp_per_restaurant
  ) AS (ord, metric, raw_value)
  FROM wide
)
SELECT ord, metric, borough,
       round(raw_value, 1) AS raw_value,
       round(100 * raw_value / sum(raw_value) OVER (PARTITION BY metric), 1) AS share_of_metric
FROM long;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## CELL 4c: Genie view
-- MAGIC The Genie space also lists `rats_clean`, a thin typed view over the raw `rat_sightings` table. Definition copied from the source workspace.

-- COMMAND ----------

CREATE OR REPLACE VIEW workspace.default.rats_clean (
  created_date,
  closed_date,
  status,
  descriptor,
  borough,
  incident_zip)
WITH SCHEMA COMPENSATION
AS SELECT 
  CAST(`created_date` AS TIMESTAMP) AS `created_date`,
  CAST(`closed_date` AS TIMESTAMP) AS `closed_date`,
  `status`,
  `descriptor`,
  `borough`,
  LPAD(CAST(`incident_zip` AS STRING), 5, '0') AS `incident_zip`
FROM `workspace`.`default`.`rat_sightings`
WHERE 
  `incident_zip` IS NOT NULL
  AND (
    CAST(`incident_zip` AS STRING) RLIKE '^[0-9]{5}$'
    OR (CAST(`incident_zip` AS STRING) RLIKE '^[0-9]{1,4}$' 
        AND CAST(`incident_zip` AS INT) BETWEEN 1 AND 99999)
  );

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## CELL 5: Sanity checks (expected values from local profiling of the CSVs)

-- COMMAND ----------

SELECT 'complaints' AS check_name, COUNT(*) AS actual, 50954 AS expected FROM workspace.default.rodent_complaints_clean
UNION ALL SELECT 'complaints with valid zip', COUNT(*), 50953 FROM workspace.default.rodent_complaints_clean WHERE zip IS NOT NULL
UNION ALL SELECT 'auto-closed complaints', COUNT(*), 22547 FROM workspace.default.rodent_complaints_clean WHERE is_auto_closed
UNION ALL SELECT 'auto-closed after 2026-04-20', COUNT(*), 1 FROM workspace.default.rodent_complaints_clean WHERE is_auto_closed AND policy_era = 'after_2026-04-20'
UNION ALL SELECT 'violation rows', COUNT(*), 158083 FROM workspace.default.restaurant_violations_clean
UNION ALL SELECT 'restaurants', COUNT(*), 26114 FROM workspace.default.restaurants_clean
UNION ALL SELECT 'restaurants with rodent violation', COUNT(*), 5966 FROM workspace.default.restaurants_clean WHERE had_rodent_violation
UNION ALL SELECT 'zips in index', COUNT(*), 227 FROM workspace.default.zip_service_gap_index
UNION ALL SELECT 'zips ranked', COUNT(*), 155 FROM workspace.default.zip_service_gap_index WHERE has_enough_data
UNION ALL SELECT 'population rows', COUNT(*), 231 FROM workspace.default.nyc_population_clean
UNION ALL SELECT 'population usable', COUNT(*), 183 FROM workspace.default.nyc_population_clean WHERE usable_for_per_capita
UNION ALL SELECT 'ranked zips with population', COUNT(*), 155 FROM workspace.default.zip_service_gap_index WHERE has_enough_data AND has_population
UNION ALL SELECT 'zip_lookup_v rows', COUNT(*), 227 FROM workspace.default.zip_lookup_v
UNION ALL SELECT 'borough_metric_shares_v rows', COUNT(*), 25 FROM workspace.default.borough_metric_shares_v
UNION ALL SELECT 'rats_clean rows', COUNT(*), 50953 FROM workspace.default.rats_clean;

-- COMMAND ----------

SHOW TABLES IN workspace.default;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## CELL 6: Dashboard query (one ZIP parameter drives everything)
-- MAGIC In the dashboard, create a text parameter named zip_param.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC These are the dashboard dataset queries; `:zip_param` is a text parameter in the dashboard.
-- MAGIC Shown verbatim as a comment block, then as runnable cells with ZIP 11423.

-- COMMAND ----------

/*
-- Tile A: this ZIP's card
SELECT * FROM workspace.default.zip_service_gap_index WHERE zip = :zip_param;

-- Tile B: this ZIP vs its borough vs city
SELECT 'This ZIP' AS scope, pct_auto_closed_before_apr2026, median_days_to_close_after_apr2026, rodent_violation_rate_pct
FROM workspace.default.zip_service_gap_index WHERE zip = :zip_param
UNION ALL
SELECT 'Borough', ROUND(AVG(pct_auto_closed_before_apr2026),1), ROUND(AVG(median_days_to_close_after_apr2026),1), ROUND(AVG(rodent_violation_rate_pct),1)
FROM workspace.default.zip_service_gap_index WHERE has_enough_data AND borough = (SELECT borough FROM workspace.default.zip_service_gap_index WHERE zip = :zip_param)
UNION ALL
SELECT 'NYC', ROUND(AVG(pct_auto_closed_before_apr2026),1), ROUND(AVG(median_days_to_close_after_apr2026),1), ROUND(AVG(rodent_violation_rate_pct),1)
FROM workspace.default.zip_service_gap_index WHERE has_enough_data;

-- Tile C: monthly complaints and outcome for this ZIP
SELECT created_month, outcome, COUNT(*) AS complaints
FROM workspace.default.rodent_complaints_clean WHERE zip = :zip_param GROUP BY 1,2 ORDER BY 1,2;

-- Tile D: the citywide story chart (no parameter): auto-close share by month
SELECT created_month, ROUND(100.0 * SUM(CASE WHEN is_auto_closed THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_auto_closed,
       MEDIAN(CASE WHEN NOT is_auto_closed THEN days_to_close END) AS median_days_worked
FROM workspace.default.rodent_complaints_clean GROUP BY 1 ORDER BY 1;
*/

-- COMMAND ----------

-- Tile A: this ZIP's card
SELECT * FROM workspace.default.zip_service_gap_index WHERE zip = '11423';

-- COMMAND ----------

-- Tile B: this ZIP vs its borough vs city
SELECT 'This ZIP' AS scope, pct_auto_closed_before_apr2026, median_days_to_close_after_apr2026, rodent_violation_rate_pct
FROM workspace.default.zip_service_gap_index WHERE zip = '11423'
UNION ALL
SELECT 'Borough', ROUND(AVG(pct_auto_closed_before_apr2026),1), ROUND(AVG(median_days_to_close_after_apr2026),1), ROUND(AVG(rodent_violation_rate_pct),1)
FROM workspace.default.zip_service_gap_index WHERE has_enough_data AND borough = (SELECT borough FROM workspace.default.zip_service_gap_index WHERE zip = '11423')
UNION ALL
SELECT 'NYC', ROUND(AVG(pct_auto_closed_before_apr2026),1), ROUND(AVG(median_days_to_close_after_apr2026),1), ROUND(AVG(rodent_violation_rate_pct),1)
FROM workspace.default.zip_service_gap_index WHERE has_enough_data;

-- COMMAND ----------

-- Tile C: monthly complaints and outcome for this ZIP
SELECT created_month, outcome, COUNT(*) AS complaints
FROM workspace.default.rodent_complaints_clean WHERE zip = '11423' GROUP BY 1,2 ORDER BY 1,2;

-- COMMAND ----------

-- Tile D: the citywide story chart (no parameter): auto-close share by month
SELECT created_month, ROUND(100.0 * SUM(CASE WHEN is_auto_closed THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_auto_closed,
       MEDIAN(CASE WHEN NOT is_auto_closed THEN days_to_close END) AS median_days_worked
FROM workspace.default.rodent_complaints_clean GROUP BY 1 ORDER BY 1;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Done
-- MAGIC If every row of the sanity check shows `actual = expected`, the tables are ready for Genie and the dashboard.