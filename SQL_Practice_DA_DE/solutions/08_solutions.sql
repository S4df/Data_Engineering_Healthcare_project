-- =====================================================================
-- SOLUTIONS — Lesson 08 (analytics patterns)
-- =====================================================================
SET search_path TO retro;

-- Q1. Best CPU per NFS game (min 10 sessions)
WITH per_cpu AS (
    SELECT g.title, cp.model, count(*) AS sessions,
           round(100.0 * avg((s.avg_fps >= 60)::int), 1) AS pct_perfect
    FROM game_sessions s
    JOIN games g ON g.game_id = s.game_id
    JOIN rigs r  ON r.rig_id  = s.rig_id
    JOIN cpus cp ON cp.cpu_id = r.cpu_id
    WHERE g.title ILIKE 'need for speed%'
    GROUP BY g.title, cp.model
    HAVING count(*) >= 10
)
SELECT DISTINCT ON (title) title, model, sessions, pct_perfect
FROM per_cpu
ORDER BY title, pct_perfect DESC, sessions DESC;

-- Q2. Peak hours
SELECT extract(hour FROM started_at)::int               AS hour_of_day,
       count(*)                                         AS sessions,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct_of_total
FROM game_sessions
GROUP BY 1
ORDER BY 1;

-- Q3. First rig vs latest rig fps (users with 2+ rigs)
WITH rr AS (
    SELECT rig_id, user_id,
           row_number() OVER (PARTITION BY user_id ORDER BY built_on ASC)  AS rn_asc,
           row_number() OVER (PARTITION BY user_id ORDER BY built_on DESC) AS rn_desc,
           count(*)     OVER (PARTITION BY user_id)                        AS rig_count
    FROM rigs
)
SELECT r.user_id,
       round(avg(s.avg_fps) FILTER (WHERE r.rn_asc  = 1), 1) AS first_rig_fps,
       round(avg(s.avg_fps) FILTER (WHERE r.rn_desc = 1), 1) AS latest_rig_fps
FROM rr r
JOIN game_sessions s USING (rig_id)
WHERE r.rig_count >= 2
GROUP BY r.user_id
ORDER BY r.user_id;
-- Latest-rig fps is often LOWER — newer rig, but people play newer, heavier games on it.
-- That's a confounder: always ask "compared to what?"

-- Q4. Longest gap between sessions per user
WITH gaps AS (
    SELECT user_id, started_at,
           started_at - lag(started_at) OVER (PARTITION BY user_id ORDER BY started_at) AS gap
    FROM game_sessions
)
SELECT u.username, max(g.gap) AS longest_gap
FROM gaps g
JOIN users u USING (user_id)
GROUP BY u.username
ORDER BY longest_gap DESC NULLS LAST
LIMIT 10;

-- Q5. Top country per region by hours per user
WITH per_country AS (
    SELECT c.region, c.country_name,
           sum(s.duration_min) / 60.0 / count(DISTINCT u.user_id) AS hours_per_user
    FROM game_sessions s
    JOIN users u     USING (user_id)
    JOIN countries c USING (country_id)
    GROUP BY c.region, c.country_name
),
ranked AS (
    SELECT *, rank() OVER (PARTITION BY region ORDER BY hours_per_user DESC) AS rnk
    FROM per_country
)
SELECT region, country_name, round(hours_per_user, 1) AS hours_per_user
FROM ranked
WHERE rnk = 1
ORDER BY region;
