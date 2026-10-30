-- =====================================================================
-- SOLUTIONS — Lesson 07 (run lesson 07 first — it creates schema dw)
-- =====================================================================
SET search_path TO retro;

-- Q1. dim_rig
DROP TABLE IF EXISTS dw.dim_rig;
CREATE TABLE dw.dim_rig AS
SELECT r.rig_id, r.user_id, c.model AS cpu_model, r.ram_mb, r.gpu, r.built_on
FROM rigs r
JOIN cpus c USING (cpu_id);
ALTER TABLE dw.dim_rig ADD PRIMARY KEY (rig_id);

-- Q2. Idempotent per-user summary (run it twice — still 300 rows)
CREATE TABLE IF NOT EXISTS dw.user_stats (
    user_id     INT PRIMARY KEY,
    sessions    INT       NOT NULL,
    hours       NUMERIC(8,1) NOT NULL,
    last_played TIMESTAMP NOT NULL
);

INSERT INTO dw.user_stats (user_id, sessions, hours, last_played)
SELECT user_id, count(*), round(sum(duration_min) / 60.0, 1), max(started_at)
FROM game_sessions
GROUP BY user_id
ON CONFLICT (user_id) DO UPDATE
    SET sessions    = EXCLUDED.sessions,
        hours       = EXCLUDED.hours,
        last_played = EXCLUDED.last_played;

SELECT count(*) FROM dw.user_stats;

-- Q3. Celeron 300A price on 2000-01-01 (answer: 79.00)
SELECT c.model, h.price_usd
FROM dw.dim_cpu_price_history h
JOIN cpus c USING (cpu_id)
WHERE c.model = 'Celeron 300A'
  AND DATE '2000-01-01' >= h.valid_from
  AND DATE '2000-01-01' <  h.valid_to;

-- Q4. Duration data-quality check (expect 0)
SELECT 'session duration out of range' AS check_name, count(*) AS failures
FROM game_sessions
WHERE duration_min > 180 OR duration_min < 10;

-- Q5. Materialized view per CPU family per year
DROP MATERIALIZED VIEW IF EXISTS dw.mv_cpu_family_yearly;
CREATE MATERIALIZED VIEW dw.mv_cpu_family_yearly AS
SELECT c.family,
       extract(year FROM f.started_at)::int     AS yr,
       count(*)                                 AS sessions,
       round(100.0 * avg(f.is_perfect::int), 1) AS pct_perfect
FROM dw.fact_session f
JOIN dw.dim_cpu c USING (cpu_id)
GROUP BY 1, 2;

REFRESH MATERIALIZED VIEW dw.mv_cpu_family_yearly;
SELECT * FROM dw.mv_cpu_family_yearly ORDER BY family, yr;
