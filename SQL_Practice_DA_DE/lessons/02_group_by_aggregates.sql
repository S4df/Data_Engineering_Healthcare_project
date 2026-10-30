-- =====================================================================
-- LESSON 02 — GROUP BY, aggregates, HAVING, FILTER, ROLLUP
-- =====================================================================
-- Goal: turn thousands of rows into a summary.
-- DBA link: "how many failed jobs per server per day?" is a GROUP BY.
--           Your 44-server dashboard tiles are aggregates.
--
-- Golden rule: every column in SELECT is either in GROUP BY
--              or wrapped in an aggregate (count, sum, avg, ...).
-- Order of execution:  FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY
-- =====================================================================
SET search_path TO retro;

-- 2.1  The five classics
SELECT count(*)                       AS sessions,
       count(DISTINCT user_id)        AS players,
       sum(duration_min) / 60         AS hours_played,
       round(avg(avg_fps), 1)         AS mean_fps,
       min(started_at)                AS first_session,
       max(started_at)                AS last_session
FROM game_sessions;

-- 2.2  count(*) vs count(column): count(column) skips NULLs
SELECT count(*)                AS all_cpus,
       count(launch_price_usd) AS cpus_with_price,
       count(codename)         AS cpus_with_codename
FROM cpus;

-- 2.3  GROUP BY one column
SELECT manufacturer,
       count(*)                 AS cpu_count,
       max(clock_mhz)           AS fastest_mhz
FROM cpus
GROUP BY manufacturer
ORDER BY cpu_count DESC;

-- 2.4  GROUP BY an expression (year of a date)
SELECT extract(year FROM signup_date)::int AS signup_year,
       count(*)                             AS new_users
FROM users
GROUP BY signup_year                         -- Postgres lets you group by the alias
ORDER BY signup_year;

-- 2.5  WHERE vs HAVING
--      WHERE filters ROWS before grouping, HAVING filters GROUPS after.
SELECT genre, count(*) AS games, round(avg(fan_rating), 2) AS avg_rating
FROM games
WHERE release_year >= 1997          -- rows
GROUP BY genre
HAVING count(*) >= 3                -- groups
ORDER BY avg_rating DESC;

-- 2.6  FILTER — conditional aggregates (Postgres). Same as SUM(CASE WHEN ...) in SQL Server.
SELECT g.title,
       count(*)                                     AS sessions,
       count(*) FILTER (WHERE s.avg_fps >= 60)      AS perfect_runs,
       count(*) FILTER (WHERE s.crashed)            AS crashes,
       round(100.0 * count(*) FILTER (WHERE s.avg_fps >= 60) / count(*), 1) AS pct_perfect
FROM game_sessions s
JOIN games g USING (game_id)
GROUP BY g.title
ORDER BY pct_perfect DESC;

-- 2.7  string_agg / array_agg — collapse many rows into one
SELECT manufacturer,
       string_agg(model, ', ' ORDER BY release_date) AS lineup
FROM cpus
GROUP BY manufacturer;

-- 2.8  Statistical aggregates: median and most common value
SELECT g.genre,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY s.duration_min) AS median_minutes,
       mode()               WITHIN GROUP (ORDER BY g.title)        AS most_played_title
FROM game_sessions s
JOIN games g USING (game_id)
GROUP BY g.genre;

-- 2.9  ROLLUP — subtotals + grand total in ONE query (NULL = "all")
SELECT c.region,
       c.country_name,
       count(*) AS users
FROM users u
JOIN countries c USING (country_id)
GROUP BY ROLLUP (c.region, c.country_name)
ORDER BY c.region NULLS LAST, c.country_name NULLS FIRST;

-- 2.10 GROUPING SETS + GROUPING() to label the subtotal rows
SELECT CASE WHEN GROUPING(manufacturer) = 1 THEN 'ALL' ELSE manufacturer END AS manufacturer,
       CASE WHEN GROUPING(cores) = 1        THEN 'ALL' ELSE cores::text  END AS cores,
       count(*)
FROM cpus
GROUP BY GROUPING SETS ((manufacturer, cores), (manufacturer), ())
ORDER BY 1, 2;


-- =====================================================================
-- YOUR TURN  (answers in solutions/02_solutions.sql)
-- =====================================================================

-- Q1. Number of games per genre, only genres with an average fan_rating above 9.
--     L1: the rating condition is about the GROUP, not a single row.
--     L2: SELECT genre, count(*), avg(____) FROM games GROUP BY ____ HAVING avg(____) > ____;

-- Q2. For each manufacturer and release YEAR: how many CPUs and the average MHz.
--     L1: group by two things; one of them is extracted from a date.
--     L2: SELECT manufacturer, extract(year FROM ____) AS yr, count(*), avg(____)
--         FROM cpus GROUP BY ____, ____ ORDER BY ____, ____;

-- Q3. Top 10 games by total HOURS played.
--     L1: duration_min is minutes. Join to games for the title.
--     L2: SELECT g.title, sum(s.duration_min) / 60.0 AS hours FROM ____ s JOIN ____ g USING (____)
--         GROUP BY ____ ORDER BY ____ DESC LIMIT ____;

-- Q4. Crash rate (%) per CPU family. Which family crashed the most?
--     L1: game_sessions → rigs → cpus. crashed is boolean; FILTER (WHERE crashed) counts the trues.
--     L2: ... count(*) FILTER (WHERE s.crashed) * 100.0 / count(*) AS crash_pct ... GROUP BY c.____

-- Q5. One row per country: total users, active users, inactive users.
--     L1: three counts in one query — think FILTER.
--     L2: count(*) FILTER (WHERE ____) AS active, count(*) FILTER (WHERE NOT ____) AS inactive

-- Q6. Sessions per year AND per genre, plus a subtotal per year and a grand total.
--     L1: ROLLUP gives hierarchical subtotals.
--     L2: GROUP BY ROLLUP (extract(year FROM s.started_at), g.genre)
