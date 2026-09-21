# "Is My Block Cursed?" — Team Plan
**Databricks NYC Open Data Hackathon · Saturday, Sept 19, 2026**
Submission due tonight 11:59 PM (Luma says 1:00 AM Sunday; aim for 11:59). Demos are **Sunday after 10 AM**.

---

## 1. What we are building

- **A Service Gap Index, one row per NYC ZIP code**, answering: *when someone calls 311 about rats, does the city show up?*
- **A dashboard** where anyone types their ZIP and gets something true and useful (including the airport ZIPs).
- **A Genie space** over our clean tables that judges will question live on Sunday (5 questions: 3 given in advance, 2 not; we can't touch the keyboard).

Inputs: `rat_sightings.csv` (~51k 311 rodent complaints, Jan 2025–present) and `restaurant_inspections.csv` (~158k rows, **one row per violation, not per restaurant**).

## 2. How we are scored

| Criterion | Weight | What earns it |
|---|---|---|
| Live question accuracy (Genie) | 30% | Clean tables + a description on **every** column |
| Data quality and modeling | 25% | Normalized ZIPs, written-down definitions, correct counting |
| Interactive dashboard | 20% | Working ZIP filter, sensible behavior on low-data ZIPs |
| Defensible metric | 15% | Rates, not raw counts; able to say why we divided by what |
| Story | 10% | Say out loud: 311 measures who calls, violations measure where inspectors go, neither measures rats |

**55% of the score is the "boring" table work.** Organizer hard rule: no dashboard work until the tables are done.

## 3. Roles (team of 2)

- **A = Ingest + Modeler** — raw tables, clean tables, column descriptions, Genie space. Owns whether Genie works.
- **B = Builder + Narrator** — dashboard, the 4-minute story, the judge handoff.
- Swap at ~4:15 PM to test each other's work.

## 4. Timeline for today

| Time | Block | Tasks | Who |
|---|---|---|---|
| 12:30–1:15 | **Profile + find the trap** | Run the discovery queries (Section 5). Record: row counts, date range, `COUNT(DISTINCT camis)`, unusable columns. | Both (split tables) |
| 1:15–2:30 | **Clean + join** | ZIP normalization, rodent-complaint definition (written down), clean tables, index table one row per ZIP. | A: 311 · B: inspections · then index together |
| 2:30–3:00 | **SA checkpoint (they leave at 3)** | `COMMENT` on every table and column. Ask SAs to (a) review index SQL, (b) show Genie space setup with instructions + sample queries, (c) show ZIP parameter on an AI/BI dashboard. **Ask organizers for the 3 advance questions.** | Both |
| 3:00–4:15 | **Genie space** | Add clean tables only, write instructions, add sample SQL for the 3 known questions, test ~10 likely judge questions. | A |
| 3:00–4:15 | **Dashboard** | ZIP parameter drives all tiles. Test 11430 (JFK), 11371 (LaGuardia), 10004. Decide what a low-data ZIP shows. | B |
| 4:15–5:15 | **Cross-test** | A hammers the dashboard with random ZIPs; B asks Genie hard questions. Fix what breaks. | Swap |
| 5:15–6:00 | **Package** | Export notebook/SQL, 3 ZIP screenshots, draft the paragraph + closing sentence, write evening TODO list. | Both |
| Evening | **Finish + submit** | Polish dashboard, finalize paragraph, submit by 11:59. Rehearse Sunday: 4-minute story + Genie handoff. | Split |

## 5. Block One — discovery queries (this is where the hidden trap lives)

The guide says the obvious analysis is wrong and the trap is "discoverable in about three queries by anyone who stops to ask what these records actually are." Replace table names with ours (`workspace.default.…`).

### Inspections: what is a row, really?
```sql
-- rows vs restaurants vs inspections
SELECT COUNT(*) AS rows,
       COUNT(DISTINCT camis) AS restaurants,
       COUNT(DISTINCT camis, inspection_date) AS inspections,
       MIN(inspection_date), MAX(inspection_date)
FROM workspace.default.restaurant_inspections;

-- inspection types and suspicious dates
SELECT inspection_type, COUNT(*) FROM workspace.default.restaurant_inspections GROUP BY 1 ORDER BY 2 DESC;
SELECT COUNT(*) FROM workspace.default.restaurant_inspections WHERE inspection_date = '1900-01-01';

-- which violation codes are actually rodent-related?
SELECT violation_code, violation_description, COUNT(*)
FROM workspace.default.restaurant_inspections
WHERE LOWER(violation_description) RLIKE 'rat|mice|mouse|rodent|vermin'
GROUP BY 1,2 ORDER BY 3 DESC;
```
Look for: `1900-01-01` rows (never-inspected restaurants), re-inspections repeating the same violation, and only a few rodent codes (typically `04K` rats, `04L` mice, `08A` not vermin-proof). Big idea: **a violation is evidence an inspector showed up.** More rodent violations can mean more enforcement, not more rats; zero violations can mean few inspections. Normalize by inspections/restaurants, never by rows.

### 311: what happens after the call?
```sql
SELECT descriptor, COUNT(*) FROM workspace.default.rat_sightings GROUP BY 1 ORDER BY 2 DESC;

SELECT status, resolution_description, COUNT(*)
FROM workspace.default.rat_sightings GROUP BY 1,2 ORDER BY 3 DESC;

SELECT ROUND(AVG(DATEDIFF(closed_date, created_date)),1) AS avg_days,
       PERCENTILE(DATEDIFF(closed_date, created_date), 0.5) AS median_days,
       SUM(CASE WHEN DATEDIFF(closed_date, created_date) = 0 THEN 1 ELSE 0 END) AS closed_same_day
FROM workspace.default.rat_sightings;
```
Look for: descriptors beyond "Rat Sighting" (Mouse Sighting, Signs of Rodents, Condition Attracting Rodents) — **decide which count and write the decision down**. `resolution_description` is where "does the city show up?" lives: count inspected vs closed-without-visit. Bulk same-day closes usually mean nobody visited.

### Duplicates / concentration
```sql
SELECT incident_address, incident_zip, COUNT(*) c
FROM workspace.default.rat_sightings GROUP BY 1,2 ORDER BY c DESC LIMIT 20;
```
If a few addresses generate hundreds of complaints, a ZIP's "rat problem" is one building or one persistent caller.

## 6. Block Two — cleaning and the index

### ZIP normalization (both tables; expect `10001.0`, ZIP+4, blanks, "N/A")
```sql
CASE WHEN LPAD(SUBSTRING(CAST(zip_raw AS STRING), 1, 5), 5, '0') RLIKE '^1[01][0-9]{3}$'
     THEN LPAD(SUBSTRING(CAST(zip_raw AS STRING), 1, 5), 5, '0') END AS zip
```
Record how many rows we dropped as unusable — that is a data-quality point.

### Index table: one row per ZIP
Keep it simple and explainable.

**"Does the city show up" half (from 311):**
- `complaints` — using our written rodent definition
- `complaints_inspected_pct` — from resolution text
- `median_days_to_close`

**Independent rodent signal (from inspections, doesn't depend on who calls):**
- `restaurants` = `COUNT(DISTINCT camis)`, `inspections`
- `rodent_violation_rate` = restaurants with a rodent violation / restaurants inspected

**Gap** = high rodent-violation rate but low complaint rate ("silent" ZIP that may have given up on 311), or high complaints with low inspected % / slow closes (city not showing up). Rank-based or z-score composite is fine; be able to explain the denominators.

Add a `data_sufficiency` flag (e.g. `< 20 complaints OR < 10 restaurants`) so the dashboard says "not enough data to rank — here are raw counts and the borough average" for JFK/LaGuardia instead of a misleading score.

### Descriptions (Genie reads these)
Put `COMMENT ON TABLE` / `ALTER TABLE … ALTER COLUMN … COMMENT` in the **same notebook cell** as each `CREATE OR REPLACE TABLE`, so a rebuild never silently strips them. Write for Genie: plain English, units, and the definition, e.g. *"Number of 311 complaints with descriptor in (Rat Sighting, Signs of Rodents), Jan 2025–present."*

## 7. Block Three — Genie and dashboard

**Genie space**
- Clean tables only (not raw).
- Instructions: what "rodent complaint" means; always count restaurants with `COUNT(DISTINCT camis)`; ZIP is a 5-digit string; which violation codes are rodent.
- Add the 3 advance questions as **sample SQL queries** so they are guaranteed right.
- Test ~10 questions we'd expect judges to ask (worst ZIP, best ZIP, my ZIP vs borough, how many restaurants, trend by month, etc.).

**Dashboard**
- One ZIP text parameter driving every tile.
- Tiles: index score + rank out of N · complaints and inspected % · restaurant rodent-violation rate · comparison to borough/city · sufficiency message.
- Test: 11430 (JFK), 11371 (LaGuardia), 10004, a random Bronx ZIP, an invalid ZIP.
- Take 3 screenshots at 3 ZIPs tonight (accepted substitute for a link).

## 8. Submission checklist
- ☐ Dashboard link, or 3 screenshots filtered to 3 different ZIPs
- ☐ Exported notebook or SQL file with our queries
- ☐ One paragraph: what we found, what we excluded, the biggest limitation
- ☐ Closing sentence: *"If I worked for the city, I would ______, because our data shows ______."*

## 9. Survival notes (from the guide)
- Tables live under **Catalog**, not Home. Always use full names: `workspace.default.table_name`.
- `CREATE VIEW` shows no output; check with `SHOW TABLES`.
- Rebuilding a table erases column descriptions. Re-run them.
- Select-all + delete before pasting a new query.
- Don't leave heavy queries running; the team shares one daily compute quota.
- The assistant can tell you what your dashboard will do. Click it anyway.

## 10. The story we tell on Sunday (draft)
1. The question: when you call about rats, does the city show up?
2. What the records actually are: complaints measure who calls; violations measure where inspectors go; neither measures rats.
3. The trap we found (fill in from Section 5).
4. The index, its denominators, and its limits.
5. One finding someone could act on + the closing sentence.
