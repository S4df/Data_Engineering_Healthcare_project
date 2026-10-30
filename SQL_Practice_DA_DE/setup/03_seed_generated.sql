-- =====================================================================
-- 03_seed_generated.sql — 300 dummy users, their rigs, ~9k game sessions
-- =====================================================================
-- Everything is generated with a *deterministic* pseudo-random function,
-- so every run (and every machine) produces exactly the same rows.
-- That means your query answers are reproducible.
--
-- Bonus: this file is itself SQL practice — generate_series, LATERAL,
-- arrays, window functions. Read it after Lesson 05.
-- =====================================================================
SET search_path TO retro;

-- Deterministic "random" number in [0, 1) from any text seed.
CREATE OR REPLACE FUNCTION prand(seed TEXT) RETURNS DOUBLE PRECISION
LANGUAGE sql IMMUTABLE AS $$
    SELECT (abs(hashtext(seed)::bigint) % 1000000) / 1000000.0
$$;

-- ---------------------------------------------------------------------
-- USERS (300) — dummy names, era-appropriate email domains
-- ---------------------------------------------------------------------
WITH pools AS (
    SELECT
        ARRAY['Ahmed','Ayesha','Bilal','Fatima','Imran','Zainab','Omar','Sana','Hamza','Mariam',
              'Rahul','Priya','Arjun','Neha','Vikram','Ananya','Kenji','Yuki','Wei','Mei',
              'John','Emily','Michael','Sarah','David','Laura','Lukas','Anna','Pierre','Chloe',
              'Carlos','Sofia','Ivan','Olga','Emeka','Amara','Kwame','Lerato','Tom','Noah']        AS first_names,
        ARRAY['Khan','Siddiqui','Farooqui','Sheikh','Qureshi','Ansari','Sharma','Patel','Iyer','Reddy',
              'Tanaka','Sato','Chen','Wang','Smith','Johnson','Brown','Miller','Muller','Schmidt',
              'Dubois','Martin','Garcia','Rossi','Silva','Ivanov','Kowalski','Obi','Mensah','Nkosi',
              'OBrien','Wilson','Anderson','Kim','Park','Yilmaz','Hassan','Rahman','Nguyen','Lopez'] AS last_names,
        ARRAY['nfs','igi','doom','quake','pentium','voodoo','winamp','nero','crt','xp',
              'athlon','dialup','floppy','cstrike','aoe']                                          AS tags,
        ARRAY['hotmail.com','yahoo.com','rediffmail.com','aol.com','lycos.com','gmail.com']        AS domains
)
INSERT INTO users (user_id, username, first_name, last_name, email,
                   country_id, birth_year, signup_date, is_active, referred_by)
SELECT
    i,
    lower(fn) || '_' || tag || i,
    fn,
    ln,
    lower(fn) || '.' || lower(ln) || i || '@' || dom,
    1 + floor(30 * power(prand('country' || i), 1.8))::int,     -- skewed: low ids (India, Pakistan, USA…) most common
    1975 + floor(prand('birth' || i) * 21)::int,
    DATE '1997-01-01' + floor(prand('signup' || i) * 3650)::int, -- 1997 → 2006
    prand('active' || i) > 0.12,
    CASE WHEN i > 20 AND prand('ref' || i) < 0.25
         THEN 1 + floor(prand('refby' || i) * (i - 1))::int END
FROM generate_series(1, 300) AS i
CROSS JOIN pools p
CROSS JOIN LATERAL (
    SELECT p.first_names[1 + floor(prand('fn' || i) * array_length(p.first_names, 1))::int] AS fn,
           p.last_names [1 + floor(prand('ln' || i) * array_length(p.last_names,  1))::int] AS ln,
           p.tags       [1 + floor(prand('tg' || i) * array_length(p.tags,        1))::int] AS tag,
           p.domains    [1 + floor(prand('dm' || i) * array_length(p.domains,     1))::int] AS dom
) pick;

-- ---------------------------------------------------------------------
-- RIGS — every user builds 1 PC; most upgrade later (rig 2, rig 3)
-- CPU = something released in the 3 years before the build date
-- ---------------------------------------------------------------------
WITH builds AS (
    SELECT user_id, 1 AS rig_no, signup_date - floor(prand('rb1' || user_id) * 200)::int AS built_on
    FROM users
    UNION ALL
    SELECT user_id, 2, signup_date + 700 + floor(prand('rb2' || user_id) * 700)::int
    FROM users WHERE user_id % 3 <> 0
    UNION ALL
    SELECT user_id, 3, signup_date + 1800 + floor(prand('rb3' || user_id) * 700)::int
    FROM users WHERE user_id % 5 = 0
)
INSERT INTO rigs (rig_id, user_id, cpu_id, ram_mb, gpu, built_on)
SELECT
    row_number() OVER (ORDER BY b.built_on, b.user_id),
    b.user_id,
    c.cpu_id,
    (ARRAY[16,32,64,128,256,512,1024,2048])[
        greatest(1, least(8, (yr - 1995) * 2 / 3 + 1 - floor(prand('ram' || b.user_id || b.rig_no) * 2)::int))],
    CASE
        WHEN yr <= 1996 THEN (ARRAY['S3 Trio64V+','Cirrus Logic GD5446'])[1 + floor(prand('gpu' || b.user_id || b.rig_no) * 2)::int]
        WHEN yr =  1997 THEN (ARRAY['3dfx Voodoo','ATI Rage Pro'])        [1 + floor(prand('gpu' || b.user_id || b.rig_no) * 2)::int]
        WHEN yr =  1998 THEN (ARRAY['3dfx Voodoo2','NVIDIA RIVA TNT'])    [1 + floor(prand('gpu' || b.user_id || b.rig_no) * 2)::int]
        WHEN yr =  1999 THEN (ARRAY['NVIDIA RIVA TNT2','3dfx Voodoo3'])   [1 + floor(prand('gpu' || b.user_id || b.rig_no) * 2)::int]
        WHEN yr =  2000 THEN (ARRAY['NVIDIA GeForce 256','GeForce2 MX'])  [1 + floor(prand('gpu' || b.user_id || b.rig_no) * 2)::int]
        WHEN yr =  2001 THEN (ARRAY['GeForce2 GTS','ATI Radeon 7500'])    [1 + floor(prand('gpu' || b.user_id || b.rig_no) * 2)::int]
        WHEN yr =  2002 THEN (ARRAY['GeForce4 MX 440','GeForce4 Ti 4200'])[1 + floor(prand('gpu' || b.user_id || b.rig_no) * 2)::int]
        WHEN yr =  2003 THEN (ARRAY['ATI Radeon 9600 Pro','GeForce FX 5200'])[1 + floor(prand('gpu' || b.user_id || b.rig_no) * 2)::int]
        WHEN yr =  2004 THEN (ARRAY['GeForce FX 5700','ATI Radeon 9800 Pro'])[1 + floor(prand('gpu' || b.user_id || b.rig_no) * 2)::int]
        WHEN yr =  2005 THEN (ARRAY['GeForce 6600 GT','ATI Radeon X800'])  [1 + floor(prand('gpu' || b.user_id || b.rig_no) * 2)::int]
        WHEN yr =  2006 THEN (ARRAY['GeForce 7600 GT','ATI Radeon X1650']) [1 + floor(prand('gpu' || b.user_id || b.rig_no) * 2)::int]
        ELSE                 (ARRAY['GeForce 8800 GT','ATI Radeon HD 3870'])[1 + floor(prand('gpu' || b.user_id || b.rig_no) * 2)::int]
    END,
    b.built_on
FROM builds b
CROSS JOIN LATERAL (SELECT extract(year FROM b.built_on)::int AS yr) y
CROSS JOIN LATERAL (
    SELECT cpu_id
    FROM cpus
    WHERE release_date BETWEEN b.built_on - 1100 AND b.built_on
    ORDER BY prand(b.user_id || '-' || b.rig_no || '-' || cpu_id)
    LIMIT 1
) c
WHERE b.built_on <= DATE '2008-12-31';

-- ---------------------------------------------------------------------
-- GAME SESSIONS — ~9k sessions between each user's first build and 2008
--   * evenings (18:00–23:59) are peak time
--   * popular + recent games are picked more often
--   * avg_fps is SIMULATED from CPU speed vs game needs + RAM
-- ---------------------------------------------------------------------
WITH first_rig AS (
    SELECT user_id, min(built_on) AS first_built
    FROM rigs
    GROUP BY user_id
),
candidates AS (
    SELECT
        n,
        f.user_id,
        (f.first_built + floor(prand('day' || n) * (DATE '2008-12-31' - f.first_built))::int)::timestamp
          + make_interval(
                hours => CASE WHEN prand('peak' || n) < 0.65
                              THEN 18 + floor(prand('hr' || n) * 6)::int
                              ELSE floor(prand('hr' || n) * 24)::int END,
                mins  => floor(prand('min' || n) * 60)::int) AS started_at
    FROM generate_series(1, 9000) AS n
    JOIN first_rig f ON f.user_id = 1 + floor(300 * power(prand('user' || n), 1.3))::int
)
INSERT INTO game_sessions (session_id, user_id, game_id, rig_id, started_at, duration_min, avg_fps, crashed)
SELECT
    row_number() OVER (ORDER BY c.started_at, c.n),
    c.user_id,
    g.game_id,
    r.rig_id,
    c.started_at,
    10 + floor(prand('len' || c.n) * 170)::int,
    perf.fps,
    (perf.fps < 20 AND prand('crash' || c.n) < 0.40) OR prand('crash2' || c.n) < 0.01
FROM candidates c
CROSS JOIN LATERAL (                      -- the rig the user owned on that day
    SELECT rig_id, cpu_id, ram_mb
    FROM rigs
    WHERE user_id = c.user_id AND built_on <= c.started_at::date
    ORDER BY built_on DESC
    LIMIT 1
) r
JOIN cpus cp ON cp.cpu_id = r.cpu_id
CROSS JOIN LATERAL (                      -- weighted pick of a game already released
    SELECT game_id, rec_cpu_mhz, min_ram_mb
    FROM games
    WHERE release_year <= extract(year FROM c.started_at)
    ORDER BY -ln(1.0 - prand(c.n || 'g' || game_id))
             / (power(fan_rating, 3) * exp(-(extract(year FROM c.started_at) - release_year) / 3.0))
    LIMIT 1
) g
CROSS JOIN LATERAL (
    SELECT greatest(5, least(100, round((
            60 * power(cp.clock_mhz * (1 + 0.25 * (cp.cores - 1)) / g.rec_cpu_mhz::numeric, 0.7)
               * power(least(1.0, r.ram_mb / (g.min_ram_mb * 2.0)), 0.5)
            + (prand('jit' || c.n) - 0.5) * 10)::numeric, 1))) AS fps
) perf;

ANALYZE users;
ANALYZE rigs;
ANALYZE game_sessions;
