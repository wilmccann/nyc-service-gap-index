# Is My Block Cursed?

*An NYC Open Data Challenge. Participant Guide.*

> This is a Markdown conversion of the participant guide handed out at the AI Hackathon + Networking NYC (September 18–20, 2026). The original Word document is in [`hackathon-materials/`](../hackathon-materials/). It is reproduced here so anyone reading this repo understands the problem the project was trying to solve.

## The question

When a New Yorker sees a rat, they call 311. When the Health Department inspects a restaurant, every violation gets a code. Both records are public. Nobody has told you whether they agree.

You are not building a rat map. You are answering one question: **when someone calls for help, does the city show up?**

**Your deliverable:** a Service Gap Index for every ZIP code in New York City, and a dashboard where anyone can type in their own ZIP and find out how their block is served.

## What you are given

- **`rat_sightings.csv`**: about 51,000 rodent complaints filed with 311, January 2025 to present.
- **`restaurant_inspections.csv`**: about 158,000 restaurant health violations over the same period. One row per violation, not per restaurant.

Both files are downloaded and ready. You will not spend a minute hunting for data. You will spend it making the data trustworthy, which is the harder skill and the one that gets people hired.

## Agenda

### Before the event (45 minutes)

1. Create a free Databricks account at [databricks.com/learn/free-edition](https://www.databricks.com/learn/free-edition)
2. Upload `rat_sightings.csv` and run one query
3. Confirm your whole team can see the shared workspace

Do not skip this. Account problems discovered here cost nothing. Discovered at kickoff they cost two hours.

### Block one: ingest

1. Upload the two large CSVs, one at a time
2. Answer for each table: how many rows, what date range, which columns are unusable as delivered
3. Checkpoint question: how many restaurants are in your inspections table?

### Block two: clean and join

1. Normalize ZIP codes in both tables so they can be joined
2. Decide what counts as a rodent complaint, and write your decision down
3. Build your index table, one row per ZIP code
4. Write a description on every table and every column

**Hard rule:** no dashboard work in this block. Teams that start on visuals early ship beautiful charts of wrong numbers.

### Block three: make it interactive

1. Build a Genie space over your clean tables
2. Build a dashboard with a working ZIP code filter
3. Test it on a ZIP with almost no data. Decide what it should show.

### Block four: demos

1. Setup and screens up
2. The ZIP Code Challenge, open floor
3. The Live Question Round, five minutes per team
4. Scoring and awards

## How you are judged

Two things happen at demo time that you cannot rehearse.

**The ZIP Code Challenge.** Anyone in the room walks up to your screen and types in their own ZIP code. Where they live. Where they grew up. Your dashboard has to say something true and useful about it, including the ZIP that is mostly an airport.

**The Live Question Round.** Judges sit down at your Genie space and ask five questions. Three you will get in advance. Two you will not. You do not get to touch the keyboard.

Genie can only answer well if your tables are clean and your columns are described. It reads your metadata. If your column is called `val_2` with no description, Genie will guess, and it will guess wrong, confidently, in front of everyone.

**There is no way to cram for this the night before. The boring work you do in Block Two is the demo.**

### Scoring

| Criterion | Weight |
| --- | --- |
| Live question accuracy | 30% |
| Data quality and modeling | 25% |
| Interactive dashboard | 20% |
| Defensible metric | 15% |
| Story | 10% |

## Three warnings

### One row per violation, not per restaurant

A restaurant cited for eight things is eight rows. If you count rows, every number you produce will be wrong. Count restaurants with `COUNT(DISTINCT camis)`.

### Counting is not measuring

The ZIP with the most complaints is probably just the ZIP with the most people in it. A raw count is a popularity contest. Divide by something (restaurants, complaints, population) and be ready to say why you chose it.

### 311 measures who calls 311

It does not measure where rats are. People call more when they trust government, when they speak English, when they have time, when they have lived somewhere long enough to know 311 exists. A neighborhood with few complaints might be spotless, or it might be a neighborhood that gave up on calling.

If you build a map of complaints and label it "worst rat neighborhoods", you have not measured rats. You have measured civic trust and mislabeled it. That mistake, made by well-meaning people with good data, is how resources get sent to the neighborhoods that were already getting attention.

**A team that says this out loud will score higher than a team with a prettier map that does not.**

## One more thing

The obvious analysis is wrong.

There is something hidden in this data that will lead a careless team to publish a conclusion that is the opposite of the truth. It is discoverable in about three queries by anyone who stops to ask what these records actually are.

**Nobody is going to tell you what it is. Finding it is the work.**

## Roles

Pick one each. Swap at the halfway point so everybody learns more than one thing.

- **Ingest**: gets the files in, owns the raw tables
- **Modeler**: designs the clean tables and writes the descriptions. Owns whether Genie works.
- **Builder**: dashboard and Genie space
- **Narrator**: owns your four minutes, runs the handoff when judges sit down

## What to submit

- [ ] Link to your dashboard, or three screenshots filtered to three different ZIP codes
- [ ] Exported notebook or SQL file with your queries
- [ ] One paragraph: what you found, what you excluded, and the biggest limitation of your work
- [ ] Your closing sentence, filled in:

  > "If I worked for the city, I would ______, because our data shows ______."

A chart is not a finding. A finding is something somebody could act on.

## Survival notes

- Your tables live under **Catalog**, not in your Home folder. An empty Home folder is normal.
- Always write table names in full: `workspace.default.table_name`
- `CREATE VIEW` returns no visible output. That does not mean it failed. Check with `SHOW TABLES`.
- Rebuilding a table erases all your column descriptions. Re-run them, or your Genie space quietly gets worse.
- Select all and delete before pasting a new query. Most errors are leftover text, not bad SQL.
- The assistant can tell you what your dashboard will do. Click it anyway.
- Do not leave heavy queries running while you debug. Your team shares one daily compute quota.

## One last thing

Nobody in the room knows the answer to this, including the people running it. The data is real, it is current, and it has never been looked at this way.

Whatever you find today is a genuinely new thing about the city you live in.

Go find something out.
