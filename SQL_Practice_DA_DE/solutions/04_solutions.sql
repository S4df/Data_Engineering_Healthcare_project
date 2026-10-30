-- =====================================================================
-- SOLUTIONS — Lesson 04
-- =====================================================================
SET search_path TO retro;

-- Q1. Games rated above the overall average
SELECT title, fan_rating
FROM games
WHERE fan_rating > (SELECT avg(fan_rating) FROM games)
ORDER BY fan_rating DESC;

-- Q2. Users who never played a Racing game
SELECT u.username
FROM users u
WHERE NOT EXISTS (
    SELECT 1
    FROM game_sessions s
    JOIN games g USING (game_id)
    WHERE s.user_id = u.user_id
      AND g.genre = 'Racing'
)
ORDER BY u.username;

-- Q3. Avg fps per CPU family on 2003+ games (50+ sessions)
WITH modern_sessions AS (
    SELECT c.family, s.avg_fps
    FROM game_sessions s
    JOIN games g USING (game_id)
    JOIN rigs r  USING (rig_id)
    JOIN cpus c  ON c.cpu_id = r.cpu_id
    WHERE g.release_year >= 2003
)
SELECT family, count(*) AS sessions, round(avg(avg_fps), 1) AS mean_fps
FROM modern_sessions
GROUP BY family
HAVING count(*) >= 50
ORDER BY mean_fps DESC;

-- Q4. Factorial with a recursive CTE
WITH RECURSIVE f(n, fact) AS (
    SELECT 1, 1::bigint
    UNION ALL
    SELECT n + 1, fact * (n + 1)
    FROM f
    WHERE n < 10
)
SELECT * FROM f;

-- Q5. Daily sessions for March 2005, zeros included
WITH days AS (
    SELECT generate_series(DATE '2005-03-01', DATE '2005-03-31', INTERVAL '1 day')::date AS day
),
daily AS (
    SELECT started_at::date AS day, count(*) AS sessions
    FROM game_sessions
    WHERE started_at >= '2005-03-01' AND started_at < '2005-04-01'
    GROUP BY 1
)
SELECT d.day, COALESCE(x.sessions, 0) AS sessions
FROM days d
LEFT JOIN daily x USING (day)
ORDER BY d.day;
