# What the data actually says — profiling results and the trap
*Profiled locally from the two CSVs on Sat Sep 19. Numbers below are what your Databricks sanity checks (Cell 5 in `databricks_build.sql`) should reproduce.*

## The trap: "time to close" is not "time to respond"

**44% of all rodent complaints (22,547 of 50,954) were closed within 60 seconds of being filed.** Nobody visited. The system closed them automatically, at all hours of the night.

| Period | Complaints | Auto-closed within 60s | Median days to close (naive, all rows) | Median days to close (worked complaints only) |
|---|---|---|---|---|
| Jan 2025 – Mar 2026 | ~41,000 | **57–69% every month** | **0.0** | 1–2 |
| Apr 20, 2026 onward | ~12,000 | **0%** | 8–10 | 8–10 |

The auto-closing stopped on **April 20, 2026** (last auto-close was a single row that day).

**The wrong conclusion a careless team will publish:** "In 2025 the city closed rodent complaints in hours; in 2026 it takes 10 days — response got 50x worse."
**The truth:** In 2025, six in ten callers got no visit at all. In 2026, every complaint is worked. The city started showing up, and that is why closing takes longer.

Other things that follow from this:
- Any "median days to close" metric that includes auto-closed rows rewards the ZIPs where the city showed up *least*.
- The auto-close rate varied a lot by ZIP before April 2026: from 11% to 89% (median ZIP 69%). By borough: Manhattan 47%, Brooklyn 63%, Bronx 66%, Queens 74%, Staten Island 77%.
- By location type: 1–2 family homes 74% auto-closed, commercial buildings 76%, 3+ family apartment buildings 53%. The city mostly did not show up for private houses.
- After an auto-close, 84% of locations did not file again within 30 days (16% did). People mostly did not call back. (Worked complaints re-file at ~45%, but those skew to large apartment buildings, so it is not a clean comparison.)

## The second trap: the "worst ZIP" is one building

**10035 (East Harlem) has the most complaints in the city (1,501). 1,227 of them (82%) come from a single lat/long** — one 3+ family building, filed as "Signs of Rodents", ~150 per month, up to 27 in a single day, Jan–Sep 2025, then it stops. Only 5% of those were auto-closed, so this one building was also getting worked. Without it, 10035 has 274 complaints and drops out of the top 40.

Rule: report `distinct_locations` and `top_location_share_pct` next to any complaint count. Never rank ZIPs by raw complaints.

## Third: 311 complaints and rodent evidence are nearly unrelated

Comparing ZIPs, complaint counts vs. the share of restaurants cited for rats/mice has a correlation of **0.16**. The top-10 complaint ZIPs (Upper West Side, Harlem, Bed-Stuy, Crown Heights) rank 47th–135th on restaurant rodent evidence. The highest restaurant rodent rates are in Queens ZIPs with few complaints: 11428 (53% of restaurants cited), 11419 (51%), 11423 (49%), 11355 Flushing (43%).

Also: rodent violation *counts* per ZIP correlate 0.93 with inspection counts. Counting violations is counting inspections.

## What the Service Gap Index shows (from `zip_service_gap_index`)

Index = average of three percentile ranks: (1) % of pre-April-2026 complaints auto-closed with no visit, (2) median days to close a complaint after April 20, 2026, (3) % of restaurants cited for rats or mice. 155 ZIPs have enough data to be ranked; 72 do not (airports, financial district, restaurant-only ZIPs).

| Borough | ZIPs ranked | Avg index | Avg % auto-closed (pre-Apr-2026) | Avg median days (post-Apr-2026) | Avg % restaurants w/ rodents |
|---|---|---|---|---|---|
| Queens | 49 | **63.9** | 73.7 | 16.3 | 27.5 |
| Staten Island | 11 | 61.4 | 76.2 | 15.8 | 21.8 |
| Brooklyn | 38 | 48.7 | 66.6 | 10.9 | 26.3 |
| Bronx | 23 | 47.1 | 70.7 | 8.4 | 26.4 |
| Manhattan | 34 | **28.9** | 54.1 | 7.7 | 23.3 |

- Largest gaps: 11423 Hollis (92% auto-closed, 22 days, 49% of restaurants with rodents), 11416 Ozone Park, 11412 St. Albans, 11421 Woodhaven, 11429 Queens Village. Southeast Queens, almost entirely.
- Smallest gaps: 10027, 10003, 10019, 10032, 10013 — Manhattan.
- **The index is negatively correlated with complaint volume (-0.42).** The ZIPs that call the most are the best served. The quiet ZIPs are the ones the city is not showing up for. A rat map built from complaint counts points resources at exactly the wrong places.

Airport ZIPs: 11430 (JFK) has 2 complaints and 88 restaurants; 11371 (LaGuardia) has 0 complaints and 8 restaurants. Both get `has_enough_data = FALSE` and the label "Not enough data to rank this ZIP" — the dashboard should show their raw counts and the borough comparison instead of a score.

## Decisions we made (write these into the submission)
- **Rodent complaint** = descriptor in (Rat Sighting, Mouse Sighting, Signs of Rodents). "Condition Attracting Rodents" is kept in the table but flagged separately (it is a garbage/harborage report, not a sighting).
- **Rodent violation** = code 04K (rats) or 04L (mice). 08A (harborage) flagged separately, not counted.
- **Auto-closed** = closed within 1 minute of creation. Treated as "no visit".
- **Excluded**: 1 complaint with ZIP 12345; 1,513 violation rows with no ZIP and 54 with non-NYC ZIPs (NJ, Long Island); 166 exact-duplicate violation rows are left in (they do not affect restaurant-level counts).
- **Time windows**: auto-close rate measured Jan 2025–Apr 19 2026; response time measured Apr 20–Jul 31 2026 (Aug/Sep excluded because 27–65% are still open).
- **Not enough data** = fewer than 30 complaints, 10 restaurants, 20 pre-April complaints, or 5 post-April complaints.

## Biggest limitations (say them out loud)
1. No population data, so complaint *rates* per resident are impossible; restaurants are the only denominator we have.
2. "Auto-closed" is inferred from timing. The 311 export we were given has no resolution text, so we cannot see what the city told the caller.
3. Restaurant rodent citations only exist where inspectors went; ZIPs with few restaurants have a noisy rodent signal.
4. 311 measures who calls. A quiet ZIP might be clean or might have given up.

## Draft submission paragraph
> We built a Service Gap Index for 155 NYC ZIP codes from 50,954 rodent complaints and 158,083 restaurant violations (26,114 restaurants). Our first finding is that "time to close" is not "time to respond": 44% of all rodent complaints were closed within 60 seconds by the system with no inspection — about 60% of complaints every month until April 20, 2026, when the practice stopped. A naive analysis shows response time getting 50x worse in 2026; the truth is the city started showing up. Our index averages three percentile ranks: the share of a ZIP's complaints closed with no visit, the median days to close after April 2026, and the share of restaurants cited for rats or mice (an inspector-verified signal that does not depend on who calls). We excluded "Condition Attracting Rodents" from sightings, non-NYC ZIPs, and ZIPs with too little data (including JFK and LaGuardia). The biggest gaps are in Southeast Queens (Hollis, St. Albans, Ozone Park, Queens Village), where up to 92% of complaints were closed with no visit and half of restaurants have rodent citations; the smallest are in Manhattan. The index is negatively correlated with complaint volume: the ZIPs that call the most are the best served. The biggest limitation is that we have no population data and infer "no visit" from closure timing rather than resolution text.

## Draft closing sentence
> "If I worked for the city, I would **audit why 60% of rodent complaints were auto-closed without a visit until April 2026 and send inspectors to the quiet ZIPs in Southeast Queens first**, because our data shows **the neighborhoods that complain the most are the ones already being served, and the ones with the most inspector-verified rodent evidence are the ones nobody visited**."

## Population data (added Sat afternoon)

`nyc_population_by_zip`: 231 ZIPs, total 8.55M (matches NYC's ACS population), all ZIPs valid 5-digit. Issues found and handled in `nyc_population_clean`:
- **18 ZIPs have NULL population** (PO-box / single-building ZIPs like 10121 Penn Plaza, 10281 Brookfield Place) and **27 have 0** (office ZIPs like 10020 Rockefeller Center, 11371 LaGuardia). 11430 (JFK) has 588 residents. All flagged `usable_for_per_capita = FALSE`; per-capita columns are NULL for them so nobody divides by zero or by 7 people.
- **2 ZIPs are labelled "Long Island"** (11001 Floral Park, 11040 New Hyde Park) — border ZIPs, 8 complaints total. Kept, flagged `is_nyc = FALSE`.
- **Margin of error** is over 20% for a handful of tiny ZIPs; exposed as `population_moe_pct` so the dashboard can show it.
- Coverage is excellent: 182 of 190 complaint ZIPs and 50,945 of 50,954 complaints (99.98%) land in a ZIP with usable population. All 155 ranked ZIPs have population.
- The raw column `zip_code` is INT; the clean table casts it to a 5-digit string so it joins to the other tables.

**What per-capita numbers add to the story:**
- Rodent sightings per 10k residents: **Manhattan 69, Brooklyn 55, Bronx 45, Queens 30, Staten Island 27.** Manhattan calls 311 about rats 2.3x as often per resident as Queens.
- Per-capita sightings vs. share of restaurants with rodent citations, across 172 ZIPs: **correlation -0.04**. Zero. How often a neighborhood calls has no relationship to how often inspectors find rodents there.
- The new `is_quiet_zip` flag (above-median restaurant rodent rate, below-median per-capita calls) marks 42 ZIPs. **All of the top-8 service-gap ZIPs are quiet ZIPs**: 11423 Hollis calls at 11 per 10k (city median ~45) while 49% of its restaurants have rodent citations.

**How it is integrated:** the index itself is unchanged (its three components were already rates, none needed population). Population adds context columns (`population`, `complaints_per_10k_residents`, `rodent_sightings_per_10k_residents`, `restaurants_per_10k_residents`) and the `is_quiet_zip` flag. This keeps the metric explainable and means the numbers you've already seen don't move.
