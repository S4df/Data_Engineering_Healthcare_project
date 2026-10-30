# SQL Practice for Data Analysts & Data Engineers (PostgreSQL)

A practice database themed around retro PC gaming, plus 8 lessons with exercises and solutions.

It's 1997–2008. Gamers from 30 countries join a forum, build PCs with CPUs like the Pentium MMX 233 or the Athlon XP 1800+, and log every session of NFS II, Project IGI, Counter-Strike and Crysis.
The data records which games **ran perfectly** (60+ fps) on which CPUs.

---

## 1. Setup (2 minutes)

You need **PostgreSQL 16 or newer** (tested on 17).

```bash
brew services start postgresql@17          # start Postgres (macOS / Homebrew)
createdb sql_practice                      # create an empty database
psql -d sql_practice -f setup/00_run_all.sql   # build tables + load all data
```

Run these from inside this folder. You should see:

```
     table_name     | rows
--------------------+------
 countries          |   32
 cpus               |   41
 games              |   48
 users              |  300
 rigs               |  512
 game_sessions      | 9000
 stg_signups_raw    |   24
 stg_cpu_price_feed |   15
```

**Broke something? Run `00_run_all.sql` again.** It drops and rebuilds everything in about 2 seconds.
The data is generated deterministically, so you get the same rows (and the same answers) every time.

> **VS Code tip:** if the `.sql` files show red errors, VS Code is checking them as SQL Server (T-SQL).
> Click the language label in the bottom-right corner and change it to **PostgreSQL**,
> or run the files with `psql` / DBeaver / pgAdmin.

---

## 2. The data

```
countries ─┐
           └─< users >─┬─< rigs >── cpus
                       └─< game_sessions >── games
                                │
                                └── rig_id  (which PC the game was played on)
```

| Table | Rows | What it is | Good for practising |
|---|---|---|---|
| `countries` | 32 | Country, region, population, currency. Iceland & Bhutan have **no users** | LEFT JOIN, anti-join |
| `cpus` | 41 | Old-generation processors, 1992–2008: Intel, AMD, Cyrix, IDT. MHz, cores, nm, socket, launch price (some prices are NULL) | NULLs, LAG over releases, ranking |
| `games` | 48 | Retro PC games: Dangerous Dave → NFS II (1997) → Project IGI → Crysis. Min/recommended CPU, RAM, genre | Joins, range joins, bucketing |
| `users` | 300 | Dummy gamers with era-style emails (hotmail, rediffmail, lycos…). `referred_by` points to another user | Self-joins, recursive CTEs |
| `rigs` | 512 | PCs each user built over time (CPU, RAM, GPU, build date). Most users upgrade 1–2 times | LATERAL, "latest row per group", SCD thinking |
| `game_sessions` | 9,000 | Who played what, on which rig, when, for how long, at what **avg_fps**, and whether it crashed | Everything: GROUP BY, windows, cohorts, sessionization |
| `stg_signups_raw` | 24 | **Dirty** CSV import: messy names, 7 date formats, bad emails, duplicates, country typos | Data cleaning |
| `stg_cpu_price_feed` | 15 | 3 nightly price batches, including one duplicate row | UPSERT, MERGE, SCD Type 2 |

**"Runs perfectly"** means `avg_fps >= 60`. Fps is simulated from CPU speed vs. the game's `rec_cpu_mhz`, plus RAM and some random noise.
CPU specs and game requirements are approximate real-world values. Names, ratings and sessions are dummy data.

---

## 3. Lessons — do them in order

Each lesson has worked examples at the top and a **YOUR TURN** section at the bottom.

| # | File | Concepts |
|---|---|---|
| 01 | `lessons/01_select_filter_sort.sql` | SELECT, WHERE, LIKE/ILIKE/regex, NULL, COALESCE, ORDER BY, LIMIT, DISTINCT ON |
| 02 | `lessons/02_group_by_aggregates.sql` | GROUP BY, HAVING, `FILTER`, string_agg, median/mode, ROLLUP, GROUPING SETS |
| 03 | `lessons/03_joins.sql` | INNER/LEFT, anti-join, self-join, range join, CROSS, LATERAL, **the fan-out trap** |
| 04 | `lessons/04_ctes_subqueries.sql` | Subqueries, EXISTS, CTE pipelines, recursive CTE, date spines, the `NOT IN` + NULL trap |
| 05 | `lessons/05_window_functions.sql` | ROW_NUMBER/RANK/DENSE_RANK, top-N per group, LAG/LEAD, running totals, moving averages, frames, NTILE |
| 06 | `lessons/06_data_cleaning_transformation.sql` | TRIM/regex cleaning, safe date parsing (TRY_CONVERT equivalent), alias mapping, dedup, DQ flags, pivot/unpivot, JSON, PII masking |
| 07 | `lessons/07_data_engineering_patterns.sql` | Star schema, idempotent loads, UPSERT, MERGE, **SCD Type 2**, watermark incremental loads, DQ checks, materialized views, EXPLAIN, partitioning |
| 08 | `lessons/08_analytics_patterns.sql` | "Perfect running" analysis, cohort retention, gaps & islands, sessionization, Pareto, market share, funnel, outliers, churn, MAU |

### How the exercises work (ghost-text rules)

Every question has three levels of help:

1. **L1 – hint**, written in the lesson file. It tells you what to think about.
2. **L2 – ghost**, also in the lesson file. It shows the query shape with `____` blanks.
3. **L3 – full answer**, in `solutions/0X_solutions.sql`, with notes on *why*.

Try L1 first. Read L2 only if you're still stuck, and save `solutions/` for last.

---

## 4. Start here — your first task (5 minutes)

After setup, open `psql -d sql_practice` and answer this:

> **Which CPU did gamers use most often to play Need for Speed II?**

L1: you need `game_sessions` → `rigs` → `cpus`, filtered to one game title, then counted.
<details><summary>L2 (ghost)</summary>

```sql
SELECT c.model, count(*)
FROM game_sessions s
JOIN games g ON g.game_id = s.game_id
JOIN rigs  r ON r.rig_id  = s.rig_id
JOIN cpus  c ON c.cpu_id  = ____
WHERE g.title = '____'
GROUP BY ____
ORDER BY ____ DESC;
```
</details>

When it runs, move on to Lesson 01.

---

## 5. Folder layout

```
SQL_Practice_DA_DE/
├── README.md
├── setup/
│   ├── 00_run_all.sql             ← run this one
│   ├── 01_schema.sql              tables, keys, indexes
│   ├── 02_seed_reference.sql      countries, CPUs, games (hand-written)
│   ├── 03_seed_generated.sql      users, rigs, sessions (generated — read it after Lesson 05)
│   └── 04_seed_staging_messy.sql  dirty data for cleaning practice
├── lessons/                       01 → 08, examples + exercises
└── solutions/                     answers for each lesson
```

Lesson 07 builds a separate `dw` schema (the warehouse) on top of `retro` (the source system). It's safe to re-run.
