-- =====================================================================
-- SOLUTIONS — Lesson 05 (window functions)
-- =====================================================================
SET search_path TO retro;

-- Q1. Fastest CPU per manufacturer with ROW_NUMBER
WITH r AS (
    SELECT manufacturer, model, clock_mhz,
           row_number() OVER (PARTITION BY manufacturer ORDER BY clock_mhz DESC, model) AS rn
    FROM cpus
)
SELECT manufacturer, model, clock_mhz
FROM r
WHERE rn = 1;

-- Q2. Top 3 most-played games per year (ties share a rank)
WITH per_year AS (
    SELECT extract(year FROM s.started_at)::int AS yr, g.title, count(*) AS sessions,
           dense_rank() OVER (PARTITION BY extract(year FROM s.started_at)::int
                              ORDER BY count(*) DESC) AS rnk
    FROM game_sessions s
    JOIN games g USING (game_id)
    GROUP BY 1, 2
)
SELECT yr, rnk, title, sessions
FROM per_year
WHERE rnk <= 3
ORDER BY yr, rnk, title;

-- Q3. Each user's first game ever
WITH ordered AS (
    SELECT s.user_id, g.title, s.started_at,
           row_number() OVER (PARTITION BY s.user_id ORDER BY s.started_at) AS rn
    FROM game_sessions s
    JOIN games g USING (game_id)
)
SELECT u.username, o.title AS first_game, o.started_at
FROM ordered o
JOIN users u USING (user_id)
WHERE o.rn = 1
ORDER BY o.started_at;

-- Q4. Year-over-year session growth
WITH yearly AS (
    SELECT extract(year FROM started_at)::int AS yr, count(*) AS sessions
    FROM game_sessions
    GROUP BY 1
)
SELECT yr, sessions,
       lag(sessions) OVER (ORDER BY yr) AS prev_year,
       round(100.0 * (sessions - lag(sessions) OVER (ORDER BY yr))
             / lag(sessions) OVER (ORDER BY yr), 1) AS growth_pct
FROM yearly
ORDER BY yr;

-- Q5. Running total of minutes for user 42
SELECT session_id, started_at, duration_min,
       sum(duration_min) OVER (ORDER BY started_at) AS running_minutes
FROM game_sessions
WHERE user_id = 42
ORDER BY started_at;

-- Q6. MHz gained at each upgrade
WITH upgrades AS (
    SELECT r.user_id, r.rig_id, r.built_on, c.model, c.clock_mhz,
           lag(c.model)     OVER w            AS prev_model,
           c.clock_mhz - lag(c.clock_mhz) OVER w AS mhz_gain
    FROM rigs r
    JOIN cpus c USING (cpu_id)
    WINDOW w AS (PARTITION BY r.user_id ORDER BY r.built_on)
)
SELECT user_id, built_on, prev_model, model, mhz_gain
FROM upgrades
WHERE mhz_gain IS NOT NULL
ORDER BY mhz_gain DESC;
-- Interesting: some "upgrades" have a NEGATIVE gain (e.g. Pentium 4 → Core 2).
-- Clock speed isn't everything — that's the "megahertz myth".

-- Q7. Rating bands with NTILE
SELECT title, fan_rating,
       CASE ntile(4) OVER (ORDER BY fan_rating DESC)
            WHEN 1 THEN 'top 25%'
            WHEN 4 THEN 'bottom 25%'
            ELSE        'middle 50%'
       END AS band
FROM games
ORDER BY fan_rating DESC;
