-- =====================================================================
-- LESSON 03 — JOINs: inner, left, anti, self, cross, range, LATERAL
-- =====================================================================
-- Goal: combine tables correctly — and know when a join duplicates rows.
-- DBA link: joining sys.databases to backup history to find
--           "databases with NO backup" is exactly the anti-join in 3.4.
-- =====================================================================
SET search_path TO retro;

-- 3.1  INNER JOIN — only rows that match on both sides
SELECT u.username, c.country_name
FROM users u
JOIN countries c ON c.country_id = u.country_id
LIMIT 10;

-- 3.2  USING — shorthand when the column name is the same on both sides
SELECT u.username, c.country_name
FROM users u
JOIN countries c USING (country_id)
LIMIT 10;

-- 3.3  LEFT JOIN — keep every country, even with zero users
SELECT c.country_name, count(u.user_id) AS users      -- count(u.user_id), NOT count(*)!
FROM countries c
LEFT JOIN users u USING (country_id)
GROUP BY c.country_name
ORDER BY users, c.country_name;

-- 3.4  ANTI-JOIN — "which CPUs did nobody ever put in a rig?"
--      Option A: LEFT JOIN ... WHERE right side IS NULL
SELECT c.model
FROM cpus c
LEFT JOIN rigs r ON r.cpu_id = c.cpu_id
WHERE r.rig_id IS NULL;
--      Option B: NOT EXISTS (usually the clearest, and the planner loves it)
SELECT c.model
FROM cpus c
WHERE NOT EXISTS (SELECT 1 FROM rigs r WHERE r.cpu_id = c.cpu_id);

-- 3.5  Multi-table join: who played what, on which CPU
SELECT u.username, g.title, cp.model AS cpu, s.avg_fps, s.started_at
FROM game_sessions s
JOIN users u  ON u.user_id  = s.user_id
JOIN games g  ON g.game_id  = s.game_id
JOIN rigs  r  ON r.rig_id   = s.rig_id
JOIN cpus  cp ON cp.cpu_id  = r.cpu_id
ORDER BY s.started_at
LIMIT 20;

-- 3.6  SELF JOIN — users and the friend who referred them
SELECT newbie.username   AS new_user,
       referrer.username AS referred_by,
       newbie.signup_date,
       referrer.signup_date AS referrer_signup
FROM users newbie
JOIN users referrer ON referrer.user_id = newbie.referred_by
ORDER BY newbie.user_id;

-- 3.7  NON-EQUI / range join — which games could a CPU even launch?
SELECT cp.model, count(g.game_id) AS games_it_can_launch
FROM cpus cp
LEFT JOIN games g ON cp.clock_mhz >= g.min_cpu_mhz
GROUP BY cp.model, cp.clock_mhz
ORDER BY cp.clock_mhz;

-- 3.8  CROSS JOIN — every combination (here: a compatibility matrix)
SELECT cp.model, g.title,
       CASE WHEN cp.clock_mhz >= g.rec_cpu_mhz THEN 'perfect'
            WHEN cp.clock_mhz >= g.min_cpu_mhz THEN 'playable'
            ELSE 'no way' END AS verdict
FROM cpus cp
CROSS JOIN games g
WHERE cp.model IN ('Pentium MMX 233', 'Athlon 600')
  AND g.title ILIKE 'need for speed%'
ORDER BY cp.model, g.release_year;

-- 3.9  LATERAL — "for each user, give me their LATEST rig" (a per-row subquery)
SELECT u.username, latest.built_on, cp.model
FROM users u
CROSS JOIN LATERAL (
    SELECT r.cpu_id, r.built_on
    FROM rigs r
    WHERE r.user_id = u.user_id
    ORDER BY r.built_on DESC
    LIMIT 1
) latest
JOIN cpus cp USING (cpu_id)
ORDER BY u.user_id
LIMIT 20;

-- 3.10 The FAN-OUT TRAP — joining two "many" tables multiplies rows
--      Wrong: sessions × rigs per user explodes the counts
SELECT u.user_id, count(*) AS looks_like_sessions_but_isnt
FROM users u
JOIN rigs r          ON r.user_id = u.user_id
JOIN game_sessions s ON s.user_id = u.user_id
WHERE u.user_id = 5
GROUP BY u.user_id;
--      Right: aggregate each side first, THEN join
SELECT u.user_id, r.rigs, s.sessions
FROM users u
JOIN (SELECT user_id, count(*) AS rigs     FROM rigs          GROUP BY user_id) r USING (user_id)
JOIN (SELECT user_id, count(*) AS sessions FROM game_sessions GROUP BY user_id) s USING (user_id)
WHERE u.user_id = 5;


-- =====================================================================
-- YOUR TURN  (answers in solutions/03_solutions.sql)
-- =====================================================================

-- Q1. Every region with its number of users and number of sessions.
--     L1: countries → users → game_sessions. Watch out for 3.10 (fan-out)!
--     L2: count(DISTINCT u.user_id) AS users, count(s.session_id) AS sessions ... GROUP BY c.region

-- Q2. Games that were NEVER played on a Cyrix CPU.
--     L1: anti-join. The subquery needs sessions → rigs → cpus.
--     L2: WHERE NOT EXISTS (SELECT 1 FROM game_sessions s JOIN rigs r ____ JOIN cpus c ____
--                           WHERE s.game_id = g.game_id AND c.manufacturer = '____')

-- Q3. Referral data-quality check: users whose referrer signed up AFTER them
--     (impossible in real life — a bug in the source system!)
--     L1: self join like 3.6, then compare two dates.
--     L2: ... JOIN users ref ON ref.user_id = u.referred_by WHERE ref.signup_date > ____

-- Q4. For each user, their FIRST rig's CPU and their LATEST rig's CPU side by side.
--     L1: two LATERAL subqueries, one sorted ASC, one DESC.
--     L2: CROSS JOIN LATERAL (SELECT cpu_id FROM rigs r WHERE r.user_id = u.user_id ORDER BY built_on ____ LIMIT 1) first_rig ...

-- Q5. Sessions where the game was played on a CPU BELOW the game's minimum MHz.
--     How many, and what was their average fps?
--     L1: join sessions → rigs → cpus and → games, then compare clock_mhz to min_cpu_mhz.
--     L2: WHERE cp.clock_mhz < g.____
