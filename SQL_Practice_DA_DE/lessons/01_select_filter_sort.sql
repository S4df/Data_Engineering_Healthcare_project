-- =====================================================================
-- LESSON 01 — SELECT, WHERE, ORDER BY, NULLs
-- =====================================================================
-- Goal: pull exactly the rows and columns you want, in the order you want.
-- DBA link: this is your daily "SELECT TOP 10 ... FROM sys.dm_..." —
--           in Postgres TOP becomes LIMIT.
-- Run one example at a time (highlight it → run).
-- =====================================================================
SET search_path TO retro;

-- 1.1  Peek at a table (always do this first with a new dataset)
SELECT * FROM cpus LIMIT 5;

-- 1.2  Pick columns + rename them with aliases
SELECT model          AS cpu,
       clock_mhz      AS mhz,
       release_date
FROM cpus;

-- 1.3  Calculated columns: GHz, and age of the CPU in years
SELECT model,
       clock_mhz / 1000.0                          AS ghz,      -- 1000.0 (not 1000) avoids integer division!
       date_part('year', age(release_date))::int   AS years_old
FROM cpus;

-- 1.4  WHERE with AND / OR / parentheses
SELECT model, manufacturer, clock_mhz
FROM cpus
WHERE manufacturer = 'AMD'
  AND (clock_mhz >= 1000 OR cores > 1);

-- 1.5  IN, BETWEEN
SELECT title, release_year, genre
FROM games
WHERE genre IN ('Racing', 'FPS')
  AND release_year BETWEEN 1997 AND 2000;

-- 1.6  Pattern matching: LIKE is case-sensitive, ILIKE is not (Postgres-only)
SELECT title FROM games WHERE title ILIKE '%need for speed%';
SELECT model FROM cpus  WHERE model LIKE 'Pentium I%';          -- Pentium II + Pentium III

-- 1.7  Regex match (~* = case-insensitive regex)
SELECT title FROM games WHERE title ~* '^(doom|quake)';

-- 1.8  NULLs: = NULL never works. Use IS NULL / IS NOT NULL.
SELECT model, launch_price_usd FROM cpus WHERE launch_price_usd IS NULL;

-- 1.9  COALESCE: replace NULL with a fallback
SELECT model,
       COALESCE(launch_price_usd::text, 'unknown') AS price,
       COALESCE(codename, family)                  AS codename_or_family
FROM cpus;

-- 1.10 ORDER BY multiple columns, NULLS LAST, LIMIT / OFFSET (paging)
SELECT model, launch_price_usd
FROM cpus
ORDER BY launch_price_usd DESC NULLS LAST, model
LIMIT 10 OFFSET 0;           -- page 1; OFFSET 10 = page 2

-- 1.11 DISTINCT and DISTINCT ON (Postgres superpower: "first row per group")
SELECT DISTINCT manufacturer FROM cpus;

SELECT DISTINCT ON (manufacturer)        -- the fastest CPU per manufacturer
       manufacturer, model, clock_mhz
FROM cpus
ORDER BY manufacturer, clock_mhz DESC;

-- 1.12 Dates: filter users who signed up in 1999
SELECT username, signup_date
FROM users
WHERE signup_date >= DATE '1999-01-01'
  AND signup_date <  DATE '2000-01-01'      -- half-open range = index friendly
ORDER BY signup_date;


-- =====================================================================
-- YOUR TURN  (answers in solutions/01_solutions.sql)
-- Ghost-text rule: read Level 1 first. Only scroll to Level 2 if stuck.
-- =====================================================================

-- Q1. All AMD CPUs released in 1999, fastest first.
--     L1: release_date is a DATE. How did 1.12 filter a single year?
--     L2: SELECT ____ FROM cpus WHERE manufacturer = ____ AND release_date >= ____ AND release_date < ____ ORDER BY ____ DESC;

-- Q2. Racing games released before 2000 that need 16 MB RAM or less.
--     L1: three conditions, all must be true.
--     L2: WHERE genre = ____ AND release_year < ____ AND min_ram_mb <= ____

-- Q3. Every CPU's model and price, but show the text 'not recorded'
--     when the price is missing. Most expensive first, missing ones last.
--     L1: you need COALESCE, but COALESCE needs both sides the same type.
--     L2: COALESCE(launch_price_usd::____, '____') ... ORDER BY launch_price_usd DESC NULLS ____

-- Q4. Users with a hotmail address who are NOT active.
--     L1: email ends with something; is_active is a boolean.
--     L2: WHERE email LIKE '%____' AND ____ is_active

-- Q5. The OLDEST CPU from each manufacturer (one row each).
--     L1: look at 1.11 — which way should you sort?
--     L2: SELECT DISTINCT ON (____) ... ORDER BY ____, release_date ____;

-- Q6. Games whose title contains a Roman numeral II or III as a whole word.
--     L1: ILIKE '%II%' also matches "III" and words like "Hill". Regex has \m and \M (word boundaries).
--     L2: WHERE title ~ '\m(____|____)\M'
