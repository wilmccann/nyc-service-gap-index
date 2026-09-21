# Genie space setup

## Tables to add (clean tables only, NOT the raw ones)
- `workspace.default.zip_service_gap_index`  (the main one; one row per ZIP)
- `workspace.default.rodent_complaints_clean`
- `workspace.default.restaurants_clean`
- `workspace.default.restaurant_violations_clean`
- `workspace.default.nyc_population_clean`

## General instructions (paste into the Genie space "Instructions" box)
```
This space answers questions about NYC rodent complaints (311) and restaurant rodent violations, Jan 2025 to Sep 2026.

Definitions:
- A "rodent complaint" or "rodent sighting" means rodent_complaints_clean rows where is_rodent_sighting = TRUE (Rat Sighting, Mouse Sighting, Signs of Rodents). "Condition Attracting Rodents" is not a sighting.
- "Rat sighting" means descriptor = 'Rat Sighting'.
- A complaint was "auto-closed" or "closed without a visit" or "the city did not show up" when is_auto_closed = TRUE (closed within 60 seconds of filing). Auto-closing stopped on 2026-04-20.
- "Response time" or "time to close" means MEDIAN(days_to_close) over rows where is_auto_closed = FALSE. Never use AVG. Never include auto-closed rows.
- A "rodent violation" at a restaurant means violation_code in ('04K','04L'). 04K = rats, 04L = mice, 08A = harborage conditions (not a rodent violation).
- To count restaurants ALWAYS use COUNT(DISTINCT camis) or the restaurants_clean table. restaurant_violations_clean has one row per violation, so COUNT(*) on it counts violations, not restaurants or inspections.
- To count inspections use COUNT(DISTINCT camis, inspection_date).
- ZIP codes are 5-digit strings. Compare zip = '11423', not zip = 11423.
- For "worst served", "biggest service gap", or "how is my ZIP served" use zip_service_gap_index.service_gap_index (higher = worse) and service_gap_rank (1 = worst), only where has_enough_data = TRUE.
- If a ZIP has has_enough_data = FALSE, say it does not have enough data to rank and report its raw counts.
- Do not rank ZIPs by raw complaint counts; complaints measure who calls 311, not where rats are. If asked for the "most rats", explain this and offer rodent_violation_rate_pct instead.
- Borough values: Manhattan, Brooklyn, Queens, Bronx, Staten Island.
- "Per capita" or "per resident" means per 10,000 residents: use complaints_per_10k_residents or rodent_sightings_per_10k_residents in zip_service_gap_index, or join nyc_population_clean on zip and divide by population only where usable_for_per_capita = TRUE. Never divide by a population under 1,000.
- A "quiet ZIP" (is_quiet_zip = TRUE) is one where inspectors find rodents at an above-median share of restaurants but residents call 311 below the median per-capita rate. These are likely under-reporting.
```

## Sample questions to add as example SQL (add the 3 advance questions here too)

**How many restaurants are in the data?**
```sql
SELECT COUNT(*) AS restaurants FROM workspace.default.restaurants_clean;
```

**Which ZIP code has the biggest service gap?**
```sql
SELECT zip, borough, service_gap_index, service_gap_rank, pct_auto_closed_before_apr2026, median_days_to_close_after_apr2026, rodent_violation_rate_pct
FROM workspace.default.zip_service_gap_index WHERE has_enough_data ORDER BY service_gap_rank LIMIT 10;
```

**How is ZIP 11367 served?**
```sql
SELECT zip, borough, service_gap_label, service_gap_index, service_gap_rank, zips_ranked, complaints_all, pct_auto_closed_before_apr2026, median_days_to_close_after_apr2026, restaurants, rodent_violation_rate_pct
FROM workspace.default.zip_service_gap_index WHERE zip = '11367';
```

**What share of rodent complaints were closed without a visit, by month?**
```sql
SELECT created_month, COUNT(*) AS complaints, ROUND(100.0 * SUM(CASE WHEN is_auto_closed THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_auto_closed
FROM workspace.default.rodent_complaints_clean GROUP BY 1 ORDER BY 1;
```

**What is the median time to close a rodent complaint in Brooklyn since April 2026?**
```sql
SELECT MEDIAN(days_to_close) AS median_days
FROM workspace.default.rodent_complaints_clean
WHERE borough = 'Brooklyn' AND created_at >= '2026-04-20' AND NOT is_auto_closed;
```

**Which borough has the highest share of restaurants with rodent violations?**
```sql
SELECT borough, COUNT(*) AS restaurants, ROUND(100.0 * SUM(CASE WHEN had_rodent_violation THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_with_rodent_violation
FROM workspace.default.restaurants_clean WHERE borough IS NOT NULL GROUP BY 1 ORDER BY 3 DESC;
```

**Which cuisine has the most rat violations?**
```sql
SELECT cuisine, COUNT(*) AS restaurants, SUM(CASE WHEN had_rat_violation THEN 1 ELSE 0 END) AS with_rat_violation,
       ROUND(100.0 * SUM(CASE WHEN had_rat_violation THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct
FROM workspace.default.restaurants_clean GROUP BY 1 HAVING COUNT(*) >= 100 ORDER BY pct DESC LIMIT 10;
```

**Which ZIP has the most rat sightings?** (answer with the caveat)
```sql
SELECT zip, borough, rat_sightings, distinct_locations, top_location_share_pct
FROM workspace.default.zip_service_gap_index ORDER BY rat_sightings DESC LIMIT 10;
```

**Which ZIPs call 311 about rats the most per resident?**
```sql
SELECT zip, borough, population, rodent_sightings_per_10k_residents
FROM workspace.default.zip_service_gap_index WHERE has_population ORDER BY rodent_sightings_per_10k_residents DESC LIMIT 10;
```

**Which ZIPs are quiet: lots of rodent evidence but few calls?**
```sql
SELECT zip, borough, rodent_violation_rate_pct, rodent_sightings_per_10k_residents, service_gap_index
FROM workspace.default.zip_service_gap_index WHERE is_quiet_zip ORDER BY service_gap_index DESC;
```

## Questions to test yourselves before the judges do
1. How many rodent complaints were filed in 2025?
2. What percent of complaints in Queens were closed without a visit?
3. Which 5 ZIPs are the best served?
4. How many restaurants in 10025 have been cited for mice?
5. Did response time get better or worse in 2026? (the trap question: Genie should say auto-closing stopped)
6. Which ZIP has the most complaints and why is that misleading?
7. What is the average inspection score for restaurants with a rat violation?
8. How many complaints are still open?
9. What is the most common location type for rat sightings?
10. Compare 11423 to the Queens average.
