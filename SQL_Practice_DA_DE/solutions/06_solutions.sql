-- =====================================================================
-- SOLUTIONS — Lesson 06 (cleaning & transformation)
-- =====================================================================
SET search_path TO retro;

-- Q1. Signups per email domain
SELECT split_part(lower(trim(email)), '@', 2) AS domain,
       count(*)                               AS signups
FROM stg_signups_raw
WHERE email IS NOT NULL
GROUP BY domain
ORDER BY signups DESC, domain;

-- Q2. Map messy favourite_game text to game_id
WITH game_alias(alias, title) AS (
    VALUES ('nfs ii',               'Need for Speed II'),
           ('need for speed 2',     'Need for Speed II'),
           ('nfs 3',                'Need for Speed III: Hot Pursuit'),
           ('project igi',          'Project IGI: I''m Going In'),
           ('diablo 2',             'Diablo II'),
           ('quake iii',            'Quake III Arena'),
           ('age of empires 2',     'Age of Empires II: The Age of Kings'),
           ('red alert 2',          'Command & Conquer: Red Alert 2'),
           ('counter strike',       'Counter-Strike'),
           ('roller coaster tycoon','RollerCoaster Tycoon')
)
SELECT s.raw_id, s.favourite_game AS raw, g.game_id, g.title
FROM stg_signups_raw s
CROSS JOIN LATERAL (SELECT lower(regexp_replace(trim(s.favourite_game), '\s+', ' ', 'g')) AS k) t
LEFT JOIN game_alias a ON a.alias = t.k
LEFT JOIN games g      ON lower(g.title) = coalesce(lower(a.title), t.k)
ORDER BY g.game_id NULLS FIRST, s.raw_id;

-- Q3. CPUs per manufacturer per era (pivot)
SELECT manufacturer,
       count(*) FILTER (WHERE release_date <  '2000-01-01')                               AS era_90s,
       count(*) FILTER (WHERE release_date >= '2000-01-01' AND release_date < '2005-01-01') AS era_00_04,
       count(*) FILTER (WHERE release_date >= '2005-01-01')                               AS era_05_08
FROM cpus
GROUP BY manufacturer
ORDER BY manufacturer;

-- Q4. Unpivot game requirements
SELECT g.title, kv.metric, kv.value
FROM games g
CROSS JOIN LATERAL (VALUES
    ('min_cpu_mhz', g.min_cpu_mhz),
    ('rec_cpu_mhz', g.rec_cpu_mhz),
    ('min_ram_mb',  g.min_ram_mb)
) AS kv(metric, value)
ORDER BY g.game_id, kv.metric;

-- Q5. JSON per game with its top-3 CPUs
WITH cpu_use AS (
    SELECT s.game_id, c.model, count(*) AS sessions,
           row_number() OVER (PARTITION BY s.game_id ORDER BY count(*) DESC, c.model) AS rn
    FROM game_sessions s
    JOIN rigs r USING (rig_id)
    JOIN cpus c ON c.cpu_id = r.cpu_id
    GROUP BY s.game_id, c.model
)
SELECT jsonb_build_object(
           'title',    g.title,
           'genre',    g.genre,
           'top_cpus', jsonb_agg(cu.model ORDER BY cu.rn)) AS doc
FROM cpu_use cu
JOIN games g USING (game_id)
WHERE cu.rn <= 3
GROUP BY g.game_id, g.title, g.genre
ORDER BY g.game_id;
