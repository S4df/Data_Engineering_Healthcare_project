-- =====================================================================
-- SOLUTIONS — Lesson 03
-- =====================================================================
SET search_path TO retro;

-- Q1. Users and sessions per region
--     count(*) would count SESSIONS for both, because the join fans out.
SELECT c.region,
       count(DISTINCT u.user_id) AS users,
       count(s.session_id)       AS sessions
FROM countries c
LEFT JOIN users u         USING (country_id)
LEFT JOIN game_sessions s ON s.user_id = u.user_id
GROUP BY c.region
ORDER BY sessions DESC;

-- Q2. Games never played on a Cyrix CPU
SELECT g.title
FROM games g
WHERE NOT EXISTS (
    SELECT 1
    FROM game_sessions s
    JOIN rigs r  ON r.rig_id  = s.rig_id
    JOIN cpus c  ON c.cpu_id  = r.cpu_id
    WHERE s.game_id = g.game_id
      AND c.manufacturer = 'Cyrix'
)
ORDER BY g.title;

-- Q3. Referrer signed up AFTER the user they referred (source bug)
SELECT u.username   AS new_user,   u.signup_date,
       ref.username AS referrer,   ref.signup_date AS referrer_signup
FROM users u
JOIN users ref ON ref.user_id = u.referred_by
WHERE ref.signup_date > u.signup_date
ORDER BY u.user_id;

-- Q4. First and latest rig CPU per user
SELECT u.username,
       c1.model AS first_cpu,  first_rig.built_on  AS first_built,
       c2.model AS latest_cpu, latest_rig.built_on AS latest_built
FROM users u
CROSS JOIN LATERAL (SELECT cpu_id, built_on FROM rigs r
                    WHERE r.user_id = u.user_id ORDER BY built_on ASC  LIMIT 1) first_rig
CROSS JOIN LATERAL (SELECT cpu_id, built_on FROM rigs r
                    WHERE r.user_id = u.user_id ORDER BY built_on DESC LIMIT 1) latest_rig
JOIN cpus c1 ON c1.cpu_id = first_rig.cpu_id
JOIN cpus c2 ON c2.cpu_id = latest_rig.cpu_id
ORDER BY u.user_id;

-- Q5. Sessions on a CPU below the game's minimum
SELECT count(*)                 AS sessions_below_min,
       round(avg(s.avg_fps), 1) AS mean_fps
FROM game_sessions s
JOIN games g  ON g.game_id  = s.game_id
JOIN rigs r   ON r.rig_id   = s.rig_id
JOIN cpus cp  ON cp.cpu_id  = r.cpu_id
WHERE cp.clock_mhz < g.min_cpu_mhz;
