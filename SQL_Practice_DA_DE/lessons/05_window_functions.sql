-- =====================================================================
-- LESSON 05 — WINDOW FUNCTIONS (the #1 interview topic)
-- =====================================================================
-- Goal: calculate across related rows WITHOUT collapsing them.
--   GROUP BY  → many rows become 1 row per group
--   WINDOW    → every row stays, and gets an extra calculated column
--
--   function() OVER (PARTITION BY <group>  ORDER BY <sort>  <frame>)
--                    └ restart per group    └ order inside  └ which rows to look at
--
-- DBA link: "CPU % vs previous sample" on your dashboard = LAG().
--           "Top 3 slowest queries per server" = ROW_NUMBER() per partition.
-- =====================================================================
SET search_path TO retro;

-- 5.1  Aggregate as a window: every CPU + its manufacturer's average
SELECT model, manufacturer, clock_mhz,
       round(avg(clock_mhz) OVER (PARTITION BY manufacturer)) AS mfr_avg_mhz,
       count(*)              OVER (PARTITION BY manufacturer) AS mfr_cpu_count
FROM cpus
ORDER BY manufacturer, clock_mhz;

-- 5.2  ROW_NUMBER vs RANK vs DENSE_RANK (watch the ties!)
SELECT title, fan_rating,
       row_number() OVER (ORDER BY fan_rating DESC) AS row_num,    -- 1,2,3,4  (always unique)
       rank()       OVER (ORDER BY fan_rating DESC) AS rnk,        -- 1,2,2,4  (gaps after ties)
       dense_rank() OVER (ORDER BY fan_rating DESC) AS dense_rnk   -- 1,2,2,3  (no gaps)
FROM games
ORDER BY fan_rating DESC
LIMIT 15;

-- 5.3  TOP-N PER GROUP — the 2 highest-rated games in each genre
WITH ranked AS (
    SELECT title, genre, fan_rating,
           row_number() OVER (PARTITION BY genre ORDER BY fan_rating DESC, title) AS rn
    FROM games
)
SELECT genre, rn, title, fan_rating
FROM ranked
WHERE rn <= 2                 -- you can't filter a window function in WHERE directly → wrap it
ORDER BY genre, rn;

-- 5.4  LAG / LEAD — compare with the previous/next row
--      How big was each manufacturer's MHz jump vs their previous release?
SELECT manufacturer, model, release_date, clock_mhz,
       lag(clock_mhz)  OVER w                                AS prev_mhz,
       clock_mhz - lag(clock_mhz) OVER w                     AS jump_mhz,
       lead(model)     OVER w                                AS next_model,
       release_date - lag(release_date) OVER w               AS days_since_prev
FROM cpus
WINDOW w AS (PARTITION BY manufacturer ORDER BY release_date)  -- named window: write it once
ORDER BY manufacturer, release_date;

-- 5.5  RUNNING TOTAL — cumulative users over time
SELECT signup_year, new_users,
       sum(new_users) OVER (ORDER BY signup_year) AS total_users_so_far
FROM (SELECT extract(year FROM signup_date)::int AS signup_year, count(*) AS new_users
      FROM users GROUP BY 1) t
ORDER BY signup_year;

-- 5.6  MOVING AVERAGE with an explicit frame — 3-month rolling sessions
WITH monthly AS (
    SELECT date_trunc('month', started_at)::date AS month, count(*) AS sessions
    FROM game_sessions
    GROUP BY 1
)
SELECT month, sessions,
       round(avg(sessions) OVER (ORDER BY month
                                 ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1) AS rolling_3m
FROM monthly
ORDER BY month;

-- 5.7  % OF TOTAL and % of group
SELECT g.genre, g.title, count(*) AS sessions,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2)                       AS pct_of_all,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY g.genre), 2)   AS pct_of_genre
FROM game_sessions s
JOIN games g USING (game_id)
GROUP BY g.genre, g.title                 -- window runs AFTER group by: sum(count(*)) is legal
ORDER BY g.genre, sessions DESC;

-- 5.8  FIRST_VALUE / LAST_VALUE — and the frame gotcha
--      Default frame with ORDER BY is "start → current row", so last_value looks wrong.
SELECT manufacturer, model, release_date,
       first_value(model) OVER (PARTITION BY manufacturer ORDER BY release_date) AS first_cpu,
       last_value(model)  OVER (PARTITION BY manufacturer ORDER BY release_date) AS last_cpu_WRONG,
       last_value(model)  OVER (PARTITION BY manufacturer ORDER BY release_date
                                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_cpu_RIGHT
FROM cpus
ORDER BY manufacturer, release_date;

-- 5.9  NTILE / PERCENT_RANK / CUME_DIST — bucketing & percentiles
SELECT model, clock_mhz,
       ntile(4)       OVER (ORDER BY clock_mhz)                   AS speed_quartile,
       round(percent_rank() OVER (ORDER BY clock_mhz)::numeric, 2) AS pct_rank,
       round(cume_dist()    OVER (ORDER BY clock_mhz)::numeric, 2) AS cume_dist
FROM cpus
ORDER BY clock_mhz;

-- 5.10 ROWS vs RANGE — what counts as "the previous rows" when there are ties
SELECT model, clock_mhz,
       sum(clock_mhz) OVER (ORDER BY clock_mhz ROWS  UNBOUNDED PRECEDING) AS rows_running,
       sum(clock_mhz) OVER (ORDER BY clock_mhz RANGE UNBOUNDED PRECEDING) AS range_running  -- ties added together
FROM cpus
WHERE clock_mhz BETWEEN 100 AND 233
ORDER BY clock_mhz;

-- 5.11 Per-user session numbering + time since previous session
SELECT user_id, session_id, started_at,
       row_number() OVER (PARTITION BY user_id ORDER BY started_at)                AS nth_session,
       started_at - lag(started_at) OVER (PARTITION BY user_id ORDER BY started_at) AS gap
FROM game_sessions
WHERE user_id = 7
ORDER BY started_at;


-- =====================================================================
-- YOUR TURN  (answers in solutions/05_solutions.sql)
-- =====================================================================

-- Q1. The FASTEST CPU per manufacturer, using ROW_NUMBER (not DISTINCT ON).
--     L1: partition by manufacturer, order by MHz, keep rn = 1.
--     L2: WITH r AS (SELECT *, row_number() OVER (PARTITION BY ____ ORDER BY ____ DESC) AS rn FROM cpus)
--         SELECT ... FROM r WHERE rn = ____;

-- Q2. The 3 most-played games per YEAR (by session count). Ties should share a rank.
--     L1: GROUP BY year+title first, then rank inside each year. Which ranking function keeps ties?
--     L2: dense_rank() OVER (PARTITION BY ____ ORDER BY count(*) DESC)

-- Q3. Each user's FIRST game ever played (title + date).
--     L1: row_number per user ordered by started_at.
--     L2: row_number() OVER (PARTITION BY s.user_id ORDER BY s.started_at) = 1

-- Q4. Year-over-year growth of sessions: year, sessions, previous year, % growth.
--     L1: aggregate per year, then LAG.
--     L2: round(100.0 * (sessions - lag(sessions) OVER (ORDER BY yr)) / lag(sessions) OVER (ORDER BY yr), 1)

-- Q5. For every session of user 42: a running total of minutes played.
--     L1: sum() OVER with ORDER BY started_at.
--     L2: sum(duration_min) OVER (ORDER BY ____) AS running_minutes

-- Q6. Rigs: for each user's rig, how many MHz did they gain vs their previous rig?
--     Show only upgrades (rigs that have a previous rig).
--     L1: join rigs → cpus, LAG(clock_mhz) partitioned by user ordered by built_on.
--     L2: clock_mhz - lag(clock_mhz) OVER (PARTITION BY r.user_id ORDER BY r.built_on) AS mhz_gain ... WHERE mhz_gain IS NOT NULL

-- Q7. Label each game "top 25%", "middle 50%" or "bottom 25%" by fan_rating.
--     L1: ntile(4) then a CASE on the bucket number.
--     L2: CASE ntile(4) OVER (ORDER BY fan_rating DESC) WHEN 1 THEN '____' WHEN 4 THEN '____' ELSE '____' END
