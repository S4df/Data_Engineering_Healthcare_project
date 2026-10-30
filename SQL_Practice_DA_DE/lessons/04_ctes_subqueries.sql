-- =====================================================================
-- LESSON 04 — Subqueries, CTEs (WITH), recursive CTEs, date spines
-- =====================================================================
-- Goal: break a hard question into small named steps.
-- DE link: a CTE chain is a mini pipeline — staging → clean → aggregate.
--          The same shape as a dbt model or a Databricks notebook.
-- =====================================================================
SET search_path TO retro;

-- 4.1  Scalar subquery — compare each row to an overall number
SELECT model, clock_mhz
FROM cpus
WHERE clock_mhz > (SELECT avg(clock_mhz) FROM cpus);

-- 4.2  IN (subquery) — users who ever played Project IGI
SELECT username
FROM users
WHERE user_id IN (SELECT s.user_id
                  FROM game_sessions s
                  JOIN games g USING (game_id)
                  WHERE g.title ILIKE 'Project IGI%');

-- 4.3  Correlated subquery — runs "per row" of the outer query
--      Each game vs the average rating of its own genre
SELECT g.title, g.genre, g.fan_rating,
       (SELECT round(avg(g2.fan_rating), 2)
        FROM games g2
        WHERE g2.genre = g.genre) AS genre_avg
FROM games g
ORDER BY g.genre, g.fan_rating DESC;

-- 4.4  Derived table (subquery in FROM)
SELECT genre, avg_rating
FROM (SELECT genre, avg(fan_rating) AS avg_rating FROM games GROUP BY genre) t
WHERE avg_rating > 9;

-- 4.5  CTE — same thing, but readable top-to-bottom
WITH genre_stats AS (
    SELECT genre, avg(fan_rating) AS avg_rating
    FROM games
    GROUP BY genre
)
SELECT * FROM genre_stats WHERE avg_rating > 9;

-- 4.6  CTE chain — a mini pipeline
--      "Which country's gamers had the smoothest experience?"
WITH sessions_enriched AS (          -- step 1: join
    SELECT s.session_id, s.avg_fps, s.crashed, u.country_id
    FROM game_sessions s
    JOIN users u USING (user_id)
),
per_country AS (                     -- step 2: aggregate
    SELECT country_id,
           count(*)                         AS sessions,
           avg(avg_fps)                     AS mean_fps,
           avg(crashed::int) * 100          AS crash_pct
    FROM sessions_enriched
    GROUP BY country_id
)
SELECT c.country_name,                -- step 3: present
       p.sessions,
       round(p.mean_fps, 1)  AS mean_fps,
       round(p.crash_pct, 1) AS crash_pct
FROM per_country p
JOIN countries c USING (country_id)
WHERE p.sessions >= 100
ORDER BY p.mean_fps DESC;

-- 4.7  RECURSIVE CTE — walk the referral tree from user 1 downward
WITH RECURSIVE referral_tree AS (
    SELECT user_id, username, referred_by, 0 AS depth, username::text AS path
    FROM users
    WHERE user_id = 1                                   -- anchor
    UNION ALL
    SELECT u.user_id, u.username, u.referred_by, t.depth + 1,
           t.path || ' -> ' || u.username
    FROM users u
    JOIN referral_tree t ON u.referred_by = t.user_id   -- recursive step
)
SELECT * FROM referral_tree ORDER BY depth, user_id;

-- 4.8  generate_series date spine — fill the gaps so empty months show 0
WITH months AS (
    SELECT generate_series(DATE '2000-01-01', DATE '2000-12-01', INTERVAL '1 month')::date AS month
),
monthly AS (
    SELECT date_trunc('month', started_at)::date AS month, count(*) AS sessions
    FROM game_sessions
    WHERE started_at >= '2000-01-01' AND started_at < '2001-01-01'
    GROUP BY 1
)
SELECT m.month, COALESCE(x.sessions, 0) AS sessions
FROM months m
LEFT JOIN monthly x USING (month)
ORDER BY m.month;

-- 4.9  EXISTS vs IN with NULLs (a classic interview trap)
--      NOT IN returns NOTHING if the subquery contains a single NULL.
SELECT count(*) AS not_in_result
FROM users
WHERE user_id NOT IN (SELECT referred_by FROM users);          -- referred_by has NULLs → 0 rows!

SELECT count(*) AS not_exists_result
FROM users u
WHERE NOT EXISTS (SELECT 1 FROM users x WHERE x.referred_by = u.user_id);  -- correct


-- =====================================================================
-- YOUR TURN  (answers in solutions/04_solutions.sql)
-- =====================================================================

-- Q1. Games whose fan_rating is ABOVE the average rating of all games.
--     L1: like 4.1.
--     L2: WHERE fan_rating > (SELECT ____ FROM ____)

-- Q2. Users who have NEVER played a Racing game.
--     L1: NOT EXISTS with sessions joined to games.
--     L2: WHERE NOT EXISTS (SELECT 1 FROM game_sessions s JOIN games g USING (game_id)
--                           WHERE s.user_id = u.user_id AND g.genre = '____')

-- Q3. Using a CTE chain: for each CPU family, the average fps on games
--     released in 2003 or later. Only families with 50+ such sessions.
--     L1: step 1 join sessions/games/rigs/cpus + filter year, step 2 group by family.
--     L2: WITH s AS (SELECT c.family, s.avg_fps FROM ... WHERE g.release_year >= ____)
--         SELECT family, count(*), avg(avg_fps) FROM s GROUP BY family HAVING count(*) >= ____

-- Q4. Recursive CTE: print the numbers 1..10 and their running product (factorial).
--     L1: anchor row is (1, 1). Each step adds 1 to n and multiplies.
--     L2: WITH RECURSIVE f(n, fact) AS (SELECT 1, 1::bigint UNION ALL SELECT n + 1, fact * (____) FROM f WHERE n < ____) SELECT * FROM f;

-- Q5. Daily sessions for March 2005 including days with 0 sessions.
--     L1: date spine with generate_series + LEFT JOIN (4.8), but by day.
--     L2: generate_series(DATE '2005-03-01', DATE '2005-03-31', INTERVAL '1 ____')
