-- =====================================================================
-- LESSON 07 — DATA ENGINEERING PATTERNS
-- =====================================================================
-- Goal: the SQL patterns behind real pipelines.
--   star schema · idempotent loads · UPSERT · MERGE · SCD Type 2 ·
--   incremental (watermark) loads · data-quality checks ·
--   materialized views · indexes + EXPLAIN · partitioning
--
-- Everything is built in a separate schema "dw" (data warehouse),
-- reading from "retro" (the source system). Re-runnable top to bottom.
-- DBA link: you already know indexes, EXPLAIN plans and maintenance —
--           this lesson is where your DBA brain gives you an unfair advantage.
-- =====================================================================
SET search_path TO retro;

DROP SCHEMA IF EXISTS dw CASCADE;
CREATE SCHEMA dw;

-- ---------------------------------------------------------------------
-- 7.1  STAR SCHEMA — dimensions (who/what/when) around one fact (events)
-- ---------------------------------------------------------------------
--               dim_date
--                  │
--   dim_user ── fact_session ── dim_game
--                  │
--               dim_cpu
-- ---------------------------------------------------------------------

-- Date dimension, generated — every warehouse has one
CREATE TABLE dw.dim_date AS
SELECT to_char(d, 'YYYYMMDD')::int        AS date_key,
       d::date                            AS full_date,
       extract(year    FROM d)::int       AS year,
       extract(quarter FROM d)::int       AS quarter,
       extract(month   FROM d)::int       AS month,
       to_char(d, 'Mon')                  AS month_name,
       extract(isodow  FROM d)::int       AS day_of_week,     -- 1 = Monday
       to_char(d, 'Dy')                   AS day_name,
       extract(isodow  FROM d) IN (6, 7)  AS is_weekend
FROM generate_series(DATE '1996-01-01', DATE '2008-12-31', INTERVAL '1 day') AS d;
ALTER TABLE dw.dim_date ADD PRIMARY KEY (date_key);

-- User dimension — denormalised: country columns copied in (fewer joins for BI)
CREATE TABLE dw.dim_user AS
SELECT u.user_id, u.username, u.first_name || ' ' || u.last_name AS full_name,
       c.country_name, c.region, u.birth_year, u.signup_date, u.is_active
FROM users u
JOIN countries c USING (country_id);
ALTER TABLE dw.dim_user ADD PRIMARY KEY (user_id);

CREATE TABLE dw.dim_game AS SELECT game_id, title, genre, release_year, publisher, multiplayer FROM games;
ALTER TABLE dw.dim_game ADD PRIMARY KEY (game_id);

CREATE TABLE dw.dim_cpu AS SELECT cpu_id, model, manufacturer, family, clock_mhz, cores FROM cpus;
ALTER TABLE dw.dim_cpu ADD PRIMARY KEY (cpu_id);

-- Fact table: one row per session, only keys + measures
CREATE TABLE dw.fact_session (
    session_id    BIGINT PRIMARY KEY,
    date_key      INT      NOT NULL REFERENCES dw.dim_date,
    user_id       INT      NOT NULL REFERENCES dw.dim_user,
    game_id       SMALLINT NOT NULL REFERENCES dw.dim_game,
    cpu_id        SMALLINT NOT NULL REFERENCES dw.dim_cpu,
    started_at    TIMESTAMP NOT NULL,
    duration_min  INT      NOT NULL,
    avg_fps       NUMERIC(5,1) NOT NULL,
    is_perfect    BOOLEAN  NOT NULL,         -- derived measure: fps >= 60
    crashed       BOOLEAN  NOT NULL
);

-- ---------------------------------------------------------------------
-- 7.2  IDEMPOTENT FULL LOAD — run it 10 times, get the same result
--      TRUNCATE + INSERT inside ONE transaction: readers never see it half-empty
-- ---------------------------------------------------------------------
BEGIN;
TRUNCATE dw.fact_session;
INSERT INTO dw.fact_session
SELECT s.session_id,
       to_char(s.started_at, 'YYYYMMDD')::int,
       s.user_id, s.game_id, r.cpu_id,
       s.started_at, s.duration_min, s.avg_fps,
       s.avg_fps >= 60,
       s.crashed
FROM game_sessions s
JOIN rigs r USING (rig_id);
COMMIT;

-- A typical BI query on the star: weekend vs weekday smoothness per CPU family
SELECT c.family, d.is_weekend,
       count(*)                                         AS sessions,
       round(100.0 * avg(f.is_perfect::int), 1)          AS pct_perfect
FROM dw.fact_session f
JOIN dw.dim_cpu  c USING (cpu_id)
JOIN dw.dim_date d USING (date_key)
GROUP BY c.family, d.is_weekend
ORDER BY c.family, d.is_weekend;

-- ---------------------------------------------------------------------
-- 7.3  UPSERT with INSERT ... ON CONFLICT — "latest known price per CPU"
-- ---------------------------------------------------------------------
CREATE TABLE dw.cpu_price_latest (
    cpu_id      SMALLINT PRIMARY KEY REFERENCES dw.dim_cpu,
    price_usd   NUMERIC(7,2) NOT NULL,
    price_date  DATE NOT NULL,
    updated_at  TIMESTAMP NOT NULL DEFAULT now()
);

-- Load batch 1, 2, 3 in order. Re-running a batch changes nothing (idempotent).
-- NOTE the DISTINCT ON: batch 3 sends the Celeron row TWICE. Without dedup you get
--   ERROR: ON CONFLICT DO UPDATE command cannot affect row a second time
-- → always dedupe the source before an upsert.
INSERT INTO dw.cpu_price_latest AS t (cpu_id, price_usd, price_date)
SELECT DISTINCT ON (c.cpu_id) c.cpu_id, f.price_usd, f.price_date
FROM stg_cpu_price_feed f
JOIN cpus c ON c.model = f.cpu_model
WHERE f.batch_id = 1
ORDER BY c.cpu_id, f.loaded_at DESC
ON CONFLICT (cpu_id) DO UPDATE
    SET price_usd  = EXCLUDED.price_usd,
        price_date = EXCLUDED.price_date,
        updated_at = now()
    WHERE EXCLUDED.price_date > t.price_date;      -- never overwrite newer data with older

SELECT * FROM dw.cpu_price_latest ORDER BY cpu_id;   -- after batch 1
-- 👉 Change batch_id to 2, run the INSERT again, look. Then 3. Then 3 again (nothing changes).

-- ---------------------------------------------------------------------
-- 7.4  MERGE (Postgres 15+) — insert / update / delete in one statement
--      Same as SQL Server MERGE. Here: load batches 2 and 3 together.
-- ---------------------------------------------------------------------
MERGE INTO dw.cpu_price_latest AS t
USING (
    SELECT DISTINCT ON (c.cpu_id) c.cpu_id, f.price_usd, f.price_date
    FROM stg_cpu_price_feed f
    JOIN cpus c ON c.model = f.cpu_model
    WHERE f.batch_id IN (2, 3)
    ORDER BY c.cpu_id, f.price_date DESC, f.loaded_at DESC
) AS s
ON t.cpu_id = s.cpu_id
WHEN MATCHED AND s.price_date > t.price_date THEN
    UPDATE SET price_usd = s.price_usd, price_date = s.price_date, updated_at = now()
WHEN NOT MATCHED THEN
    INSERT (cpu_id, price_usd, price_date) VALUES (s.cpu_id, s.price_usd, s.price_date);

SELECT c.model, p.price_usd, p.price_date
FROM dw.cpu_price_latest p JOIN cpus c USING (cpu_id)
ORDER BY c.model;

-- ---------------------------------------------------------------------
-- 7.5  SCD TYPE 2 — keep FULL history of price changes
--      Each change closes the old row (valid_to) and opens a new one.
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_cpu_price_history (
    price_sk    SERIAL PRIMARY KEY,              -- surrogate key
    cpu_id      SMALLINT NOT NULL,
    price_usd   NUMERIC(7,2) NOT NULL,
    valid_from  DATE NOT NULL,
    valid_to    DATE NOT NULL DEFAULT '9999-12-31',
    is_current  BOOLEAN NOT NULL DEFAULT true
);
CREATE UNIQUE INDEX ux_price_current ON dw.dim_cpu_price_history (cpu_id) WHERE is_current;  -- max 1 current row

-- Wrap the load in a PROCEDURE so an orchestrator (Airflow, ADF, cron) can CALL it
CREATE OR REPLACE PROCEDURE dw.load_cpu_price_scd2(p_batch INT)
LANGUAGE plpgsql AS $$
BEGIN
    CREATE TEMP TABLE src ON COMMIT DROP AS
    SELECT DISTINCT ON (c.cpu_id) c.cpu_id, f.price_usd, f.price_date
    FROM retro.stg_cpu_price_feed f
    JOIN retro.cpus c ON c.model = f.cpu_model
    WHERE f.batch_id = p_batch
    ORDER BY c.cpu_id, f.loaded_at DESC;

    -- step 1: expire current rows whose price changed
    UPDATE dw.dim_cpu_price_history t
    SET valid_to = s.price_date, is_current = false
    FROM src s
    WHERE t.cpu_id = s.cpu_id AND t.is_current AND t.price_usd <> s.price_usd;

    -- step 2: insert a new current row for new CPUs and for the ones just expired
    INSERT INTO dw.dim_cpu_price_history (cpu_id, price_usd, valid_from)
    SELECT s.cpu_id, s.price_usd, s.price_date
    FROM src s
    WHERE NOT EXISTS (SELECT 1 FROM dw.dim_cpu_price_history t
                      WHERE t.cpu_id = s.cpu_id AND t.is_current);

    RAISE NOTICE 'SCD2 batch % loaded', p_batch;
END $$;

CALL dw.load_cpu_price_scd2(1);
CALL dw.load_cpu_price_scd2(2);
CALL dw.load_cpu_price_scd2(3);   -- K6-2 300 price unchanged → no new version (check it!)

SELECT c.model, h.price_usd, h.valid_from, h.valid_to, h.is_current
FROM dw.dim_cpu_price_history h JOIN cpus c USING (cpu_id)
ORDER BY c.model, h.valid_from;

-- Point-in-time ("as of") query: what did each CPU cost on Christmas 1999?
SELECT c.model, h.price_usd
FROM dw.dim_cpu_price_history h JOIN cpus c USING (cpu_id)
WHERE DATE '1999-12-25' >= h.valid_from AND DATE '1999-12-25' < h.valid_to;

-- ---------------------------------------------------------------------
-- 7.6  INCREMENTAL LOAD with a WATERMARK — only load what's new
--      Pretend "today" moves forward; each run picks up where the last stopped.
-- ---------------------------------------------------------------------
CREATE TABLE dw.etl_watermark (
    pipeline     TEXT PRIMARY KEY,
    last_value   TIMESTAMP NOT NULL,
    rows_loaded  INT,
    run_at       TIMESTAMP
);
INSERT INTO dw.etl_watermark VALUES ('fact_session_incr', '1900-01-01', 0, NULL);

CREATE TABLE dw.fact_session_incr (LIKE dw.fact_session INCLUDING ALL);

CREATE OR REPLACE PROCEDURE dw.load_sessions_incremental(p_now TIMESTAMP)
LANGUAGE plpgsql AS $$
DECLARE
    v_from TIMESTAMP;
    v_rows INT;
BEGIN
    SELECT last_value INTO v_from FROM dw.etl_watermark WHERE pipeline = 'fact_session_incr' FOR UPDATE;

    INSERT INTO dw.fact_session_incr
    SELECT s.session_id, to_char(s.started_at, 'YYYYMMDD')::int, s.user_id, s.game_id, r.cpu_id,
           s.started_at, s.duration_min, s.avg_fps, s.avg_fps >= 60, s.crashed
    FROM retro.game_sessions s
    JOIN retro.rigs r USING (rig_id)
    WHERE s.started_at >  v_from          -- after the watermark
      AND s.started_at <= p_now           -- up to "now"
    ON CONFLICT (session_id) DO NOTHING;  -- safety net if windows ever overlap
    GET DIAGNOSTICS v_rows = ROW_COUNT;

    UPDATE dw.etl_watermark
    SET last_value  = greatest(v_from, coalesce((SELECT max(started_at) FROM dw.fact_session_incr), v_from)),
        rows_loaded = v_rows,
        run_at      = clock_timestamp()
    WHERE pipeline = 'fact_session_incr';

    RAISE NOTICE 'loaded % rows (window % → %)', v_rows, v_from, p_now;
END $$;

CALL dw.load_sessions_incremental('2003-01-01');   -- first run: history up to 2003
CALL dw.load_sessions_incremental('2006-01-01');   -- next run: only 2003–2005
CALL dw.load_sessions_incremental('2006-01-01');   -- rerun: 0 rows (idempotent ✔)
CALL dw.load_sessions_incremental('2009-01-01');   -- catch up to the end
SELECT * FROM dw.etl_watermark;
SELECT (SELECT count(*) FROM dw.fact_session_incr) AS incr_rows,
       (SELECT count(*) FROM game_sessions)         AS source_rows;   -- must match

-- ---------------------------------------------------------------------
-- 7.7  DATA QUALITY CHECKS — every check should return 0 failures
-- ---------------------------------------------------------------------
SELECT 'session played before rig was built' AS check_name, count(*) AS failures
FROM game_sessions s JOIN rigs r USING (rig_id)
WHERE s.started_at::date < r.built_on
UNION ALL
SELECT 'session uses another user''s rig', count(*)
FROM game_sessions s JOIN rigs r USING (rig_id)
WHERE s.user_id <> r.user_id
UNION ALL
SELECT 'game played before its release year', count(*)
FROM game_sessions s JOIN games g USING (game_id)
WHERE extract(year FROM s.started_at) < g.release_year
UNION ALL
SELECT 'fps outside 0–100', count(*)
FROM game_sessions WHERE avg_fps NOT BETWEEN 0 AND 100
UNION ALL
SELECT 'fact row count != source', abs((SELECT count(*) FROM dw.fact_session) - (SELECT count(*) FROM game_sessions))
UNION ALL
SELECT 'referrer signed up after referee (known source bug)', count(*)
FROM users u JOIN users r ON r.user_id = u.referred_by
WHERE r.signup_date > u.signup_date;

-- ---------------------------------------------------------------------
-- 7.8  MATERIALIZED VIEW — pre-computed "Gold" table for a dashboard
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW dw.mv_monthly_game_kpis AS
SELECT date_trunc('month', f.started_at)::date AS month,
       g.title,
       count(*)                                AS sessions,
       count(DISTINCT f.user_id)               AS players,
       round(sum(f.duration_min) / 60.0, 1)    AS hours,
       round(100.0 * avg(f.is_perfect::int), 1) AS pct_perfect
FROM dw.fact_session f
JOIN dw.dim_game g USING (game_id)
GROUP BY 1, 2;

CREATE UNIQUE INDEX ON dw.mv_monthly_game_kpis (month, title);   -- needed for CONCURRENTLY
REFRESH MATERIALIZED VIEW CONCURRENTLY dw.mv_monthly_game_kpis;  -- refresh without locking readers

SELECT * FROM dw.mv_monthly_game_kpis WHERE title = 'Need for Speed II' ORDER BY month LIMIT 12;

-- ---------------------------------------------------------------------
-- 7.9  INDEXES + EXPLAIN ANALYZE — your DBA home turf
-- ---------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT count(*) FROM dw.fact_session WHERE started_at >= '2004-06-01' AND started_at < '2004-07-01';
-- → Seq Scan (reads the whole table)

CREATE INDEX ix_fact_started ON dw.fact_session (started_at);
ANALYZE dw.fact_session;

EXPLAIN ANALYZE
SELECT count(*) FROM dw.fact_session WHERE started_at >= '2004-06-01' AND started_at < '2004-07-01';
-- → Index Only Scan / Bitmap Index Scan. Compare "Execution Time".

-- ---------------------------------------------------------------------
-- 7.10 PARTITIONING — one physical table per year, pruned at query time
-- ---------------------------------------------------------------------
CREATE TABLE dw.fact_session_part (LIKE dw.fact_session) PARTITION BY RANGE (started_at);

DO $$
DECLARE y INT;
BEGIN
    FOR y IN 1996..2008 LOOP
        EXECUTE format(
            'CREATE TABLE dw.fact_session_p%s PARTITION OF dw.fact_session_part
             FOR VALUES FROM (%L) TO (%L)', y, make_date(y, 1, 1), make_date(y + 1, 1, 1));
    END LOOP;
END $$;

INSERT INTO dw.fact_session_part SELECT * FROM dw.fact_session;

-- Rows per partition
SELECT tableoid::regclass AS partition, count(*)
FROM dw.fact_session_part
GROUP BY 1 ORDER BY 1;

-- Partition pruning: the plan only touches fact_session_p2004
EXPLAIN SELECT count(*) FROM dw.fact_session_part
WHERE started_at >= '2004-06-01' AND started_at < '2004-07-01';


-- =====================================================================
-- YOUR TURN  (answers in solutions/07_solutions.sql)
-- =====================================================================

-- Q1. Add a dw.dim_rig dimension (rig_id, user_id, cpu model, ram_mb, gpu, built_on)
--     and give it a primary key.
--     L1: CREATE TABLE ... AS SELECT, then ALTER TABLE ... ADD PRIMARY KEY (like dim_user).
--     L2: CREATE TABLE dw.dim_rig AS SELECT r.rig_id, r.user_id, c.model, ... FROM rigs r JOIN cpus c USING (____);

-- Q2. Write an UPSERT that keeps a per-user summary table up to date:
--     dw.user_stats(user_id PK, sessions, hours, last_played). Running it twice must not duplicate.
--     L1: CREATE TABLE first, then INSERT ... SELECT ... GROUP BY ... ON CONFLICT (user_id) DO UPDATE.
--     L2: ON CONFLICT (user_id) DO UPDATE SET sessions = EXCLUDED.____, hours = EXCLUDED.____, last_played = EXCLUDED.____

-- Q3. SCD2 point-in-time: what was the price of 'Celeron 300A' on 2000-01-01?
--     L1: valid_from <= date < valid_to.
--     L2: WHERE c.model = '____' AND DATE '2000-01-01' >= h.valid_from AND DATE '2000-01-01' < h.____

-- Q4. Add your own data-quality check: sessions longer than 3 hours OR shorter than 10 minutes.
--     L1: one SELECT returning a check_name and a count, like 7.7.
--     L2: SELECT 'session duration out of range', count(*) FROM game_sessions WHERE duration_min ____ OR duration_min ____;

-- Q5. Create a materialized view dw.mv_cpu_family_yearly: per CPU family per year,
--     sessions and % perfect. Refresh it.
--     L1: copy the shape of 7.8, group by family + year.
--     L2: CREATE MATERIALIZED VIEW dw.mv_cpu_family_yearly AS SELECT c.family, extract(year FROM f.started_at) AS yr, ... GROUP BY 1, 2;
