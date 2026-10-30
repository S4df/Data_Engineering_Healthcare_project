-- =====================================================================
-- LESSON 06 — Data CLEANING & TRANSFORMATION
-- =====================================================================
-- Goal: turn the dirty stg_signups_raw into a clean, typed table,
--       then practise reshaping data (pivot, unpivot, JSON, buckets).
-- DE link: this is the "Silver" layer in a Bronze → Silver → Gold lakehouse.
--          Same steps you'd do in a Databricks notebook — just in SQL.
-- =====================================================================
SET search_path TO retro;

-- ---------------------------------------------------------------------
-- PART A — Profile first, clean second
-- ---------------------------------------------------------------------

-- 6.1  Look at the mess
SELECT * FROM stg_signups_raw ORDER BY raw_id;

-- 6.2  Profile: NULLs / blanks / distinct values per column
SELECT count(*)                                              AS total_rows,
       count(*) FILTER (WHERE nullif(trim(full_name), '') IS NULL) AS missing_name,
       count(*) FILTER (WHERE email IS NULL)                 AS missing_email,
       count(DISTINCT lower(trim(email)))                    AS distinct_emails,
       count(DISTINCT country)                               AS distinct_country_spellings
FROM stg_signups_raw;

-- ---------------------------------------------------------------------
-- PART B — Column-by-column cleaning recipes
-- ---------------------------------------------------------------------

-- 6.3  Names: trim, squash repeated spaces, Proper Case, split first/last
SELECT full_name                                                        AS raw,
       initcap(regexp_replace(trim(full_name), '\s+', ' ', 'g'))        AS clean_name,
       split_part(initcap(regexp_replace(trim(full_name), '\s+', ' ', 'g')), ' ', 1) AS first_name,
       substring(initcap(regexp_replace(trim(full_name), '\s+', ' ', 'g')) FROM '\s(.*)$') AS last_name
FROM stg_signups_raw;

-- 6.4  Emails: lower + trim, then validate with a regex
SELECT email                                   AS raw,
       lower(trim(email))                      AS clean_email,
       lower(trim(email)) ~ '^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$' AS is_valid
FROM stg_signups_raw;

-- 6.5  Dates in 5+ formats. Postgres has no TRY_CONVERT, so we build one.
--      (SQL Server DBA: this is your TRY_CONVERT(date, x, 103) equivalent.)
CREATE OR REPLACE FUNCTION try_to_date(txt TEXT, fmt TEXT) RETURNS DATE
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    RETURN to_date(txt, fmt);
EXCEPTION WHEN others THEN
    RETURN NULL;                 -- bad value → NULL instead of crashing the whole load
END $$;

SELECT signup_date AS raw,
       CASE
           WHEN s ~ '^\d{4}-\d{2}-\d{2}$'         THEN try_to_date(s, 'YYYY-MM-DD')
           WHEN s ~ '^\d{4}/\d{2}/\d{2}$'         THEN try_to_date(s, 'YYYY/MM/DD')
           WHEN s ~ '^\d{2}/\d{2}/\d{4}$'         THEN try_to_date(s, 'DD/MM/YYYY')   -- assume day-first
           WHEN s ~ '^\d{2}-\d{2}-\d{4}$'         THEN try_to_date(s, 'DD-MM-YYYY')
           WHEN s ~ '^\d{2}\.\d{2}\.\d{4}$'       THEN try_to_date(s, 'DD.MM.YYYY')
           WHEN s ~ '^\d{1,2}-[A-Za-z]{3}-\d{4}$' THEN try_to_date(s, 'DD-Mon-YYYY')
           WHEN s ~ '^[A-Za-z]+ \d{1,2} \d{4}$'   THEN try_to_date(s, 'FMMonth FMDD YYYY')
       END AS clean_date
FROM stg_signups_raw
CROSS JOIN LATERAL (SELECT trim(signup_date) AS s) t;

-- 6.6  Countries: a mapping (alias) table is the professional fix — not 20 CASE lines
WITH country_alias(alias, iso2) AS (
    VALUES ('usa','US'), ('uk','GB'), ('uae','AE'), ('saudia','SA'),
           ('deutschland','DE'), ('brasil','BR')
)
SELECT DISTINCT s.country AS raw,
       c.country_name     AS matched
FROM stg_signups_raw s
CROSS JOIN LATERAL (
    SELECT nullif(lower(regexp_replace(trim(s.country), '[.\s]', '', 'g')), 'n/a') AS key
) k
LEFT JOIN country_alias a ON a.alias = k.key
LEFT JOIN countries c
       ON c.iso2 = coalesce(a.iso2, upper(k.key))
       OR lower(replace(c.country_name, ' ', '')) = k.key
ORDER BY matched NULLS FIRST;

-- 6.7  Match free-text CPU names to the cpus dimension
SELECT DISTINCT s.favourite_cpu AS raw, c.model AS matched_model
FROM stg_signups_raw s
LEFT JOIN cpus c
       ON lower(c.model) = regexp_replace(lower(regexp_replace(trim(s.favourite_cpu), '\s+', ' ', 'g')), '^(amd|intel|cyrix|idt) ', '')
ORDER BY matched_model NULLS FIRST;      -- the NULLs are your "needs a human" list

-- ---------------------------------------------------------------------
-- PART C — Put it together: one CTE pipeline → clean table + rejects
-- ---------------------------------------------------------------------

-- 6.8  Build clean_signups (re-runnable: drop + create)
DROP TABLE IF EXISTS clean_signups;

CREATE TABLE clean_signups AS
WITH country_alias(alias, iso2) AS (
    VALUES ('usa','US'), ('uk','GB'), ('uae','AE'), ('saudia','SA'),
           ('deutschland','DE'), ('brasil','BR')
),
cleaned AS (
    SELECT
        s.raw_id,
        nullif(initcap(regexp_replace(trim(s.full_name), '\s+', ' ', 'g')), '')      AS full_name,
        lower(trim(s.email))                                                        AS email,
        c.country_id,
        CASE
            WHEN d ~ '^\d{4}-\d{2}-\d{2}$'         THEN try_to_date(d, 'YYYY-MM-DD')
            WHEN d ~ '^\d{4}/\d{2}/\d{2}$'         THEN try_to_date(d, 'YYYY/MM/DD')
            WHEN d ~ '^\d{2}/\d{2}/\d{4}$'         THEN try_to_date(d, 'DD/MM/YYYY')
            WHEN d ~ '^\d{2}-\d{2}-\d{4}$'         THEN try_to_date(d, 'DD-MM-YYYY')
            WHEN d ~ '^\d{2}\.\d{2}\.\d{4}$'       THEN try_to_date(d, 'DD.MM.YYYY')
            WHEN d ~ '^\d{1,2}-[A-Za-z]{3}-\d{4}$' THEN try_to_date(d, 'DD-Mon-YYYY')
            WHEN d ~ '^[A-Za-z]+ \d{1,2} \d{4}$'   THEN try_to_date(d, 'FMMonth FMDD YYYY')
        END                                                                          AS signup_date,
        cp.cpu_id                                                                    AS favourite_cpu_id,
        s.source_file,
        s.loaded_at
    FROM stg_signups_raw s
    CROSS JOIN LATERAL (
        SELECT trim(s.signup_date) AS d,
               nullif(lower(regexp_replace(trim(s.country), '[.\s]', '', 'g')), 'n/a') AS ckey
    ) t
    LEFT JOIN country_alias a ON a.alias = t.ckey
    LEFT JOIN countries c
           ON c.iso2 = coalesce(a.iso2, upper(t.ckey))
           OR lower(replace(c.country_name, ' ', '')) = t.ckey
    LEFT JOIN cpus cp
           ON lower(cp.model) = regexp_replace(lower(regexp_replace(trim(s.favourite_cpu), '\s+', ' ', 'g')), '^(amd|intel|cyrix|idt) ', '')
),
deduped AS (
    SELECT *,
           row_number() OVER (PARTITION BY coalesce(email, 'raw-' || raw_id)
                              ORDER BY loaded_at, raw_id) AS dup_rank
    FROM cleaned
)
SELECT *,
       -- data-quality flags: one array of reasons per row
       array_remove(ARRAY[
           CASE WHEN full_name IS NULL   THEN 'missing_name'  END,
           CASE WHEN email IS NULL       THEN 'missing_email' END,
           CASE WHEN email !~ '^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$' THEN 'bad_email' END,
           CASE WHEN country_id IS NULL  THEN 'unknown_country' END,
           CASE WHEN signup_date IS NULL THEN 'bad_date' END,
           CASE WHEN dup_rank > 1        THEN 'duplicate' END
       ], NULL) AS dq_issues
FROM deduped;

-- 6.9  Good rows vs rejected rows
SELECT raw_id, full_name, email, country_id, signup_date
FROM clean_signups
WHERE cardinality(dq_issues) = 0
ORDER BY raw_id;

SELECT raw_id, full_name, email, dq_issues
FROM clean_signups
WHERE cardinality(dq_issues) > 0
ORDER BY raw_id;

-- 6.10 Data-quality summary — one row per issue type (unnest the arrays)
SELECT issue, count(*)
FROM clean_signups, unnest(dq_issues) AS issue
GROUP BY issue
ORDER BY count(*) DESC;

-- ---------------------------------------------------------------------
-- PART D — Reshaping & transformation recipes
-- ---------------------------------------------------------------------

-- 6.11 CASE bucketing — age at signup, and a generation label
SELECT username, birth_year, signup_date,
       extract(year FROM signup_date)::int - birth_year AS age_at_signup,
       CASE
           WHEN extract(year FROM signup_date)::int - birth_year < 13 THEN 'kid'
           WHEN extract(year FROM signup_date)::int - birth_year < 18 THEN 'teen'
           WHEN extract(year FROM signup_date)::int - birth_year < 25 THEN 'young adult'
           ELSE 'adult'
       END AS age_band,
       CASE WHEN birth_year < 1981 THEN 'Gen X' ELSE 'Millennial' END AS generation
FROM users
LIMIT 20;

-- 6.12 PIVOT (rows → columns) with FILTER — sessions per genre per year
SELECT extract(year FROM s.started_at)::int AS yr,
       count(*) FILTER (WHERE g.genre = 'Racing')           AS racing,
       count(*) FILTER (WHERE g.genre = 'FPS')              AS fps,
       count(*) FILTER (WHERE g.genre = 'RTS')              AS rts,
       count(*) FILTER (WHERE g.genre = 'Action')           AS action,
       count(*) FILTER (WHERE g.genre = 'Tactical Shooter') AS tactical,
       count(*)                                             AS total
FROM game_sessions s
JOIN games g USING (game_id)
GROUP BY yr
ORDER BY yr;

-- 6.13 UNPIVOT (columns → rows) with LATERAL VALUES — CPU specs as key/value
SELECT c.model, kv.spec, kv.value
FROM cpus c
CROSS JOIN LATERAL (VALUES
    ('clock_mhz',   c.clock_mhz::text),
    ('cores',       c.cores::text),
    ('process_nm',  c.process_nm::text),
    ('socket',      c.socket)
) AS kv(spec, value)
WHERE c.model = 'Pentium III 500';

-- 6.14 JSON out — one document per user with a nested array of rigs (API / NoSQL export)
SELECT jsonb_pretty(jsonb_build_object(
           'user',    u.username,
           'country', c.country_name,
           'rigs',    jsonb_agg(jsonb_build_object('cpu', cp.model, 'ram_mb', r.ram_mb,
                                                   'gpu', r.gpu,  'built', r.built_on)
                                ORDER BY r.built_on)))
FROM users u
JOIN countries c USING (country_id)
JOIN rigs r      USING (user_id)
JOIN cpus cp     USING (cpu_id)
WHERE u.user_id IN (5, 10)
GROUP BY u.username, c.country_name;

-- 6.15 JSON in — parse a JSON payload back into columns
WITH payload AS (
    SELECT '{"user":"ahmed_igi","rigs":[{"cpu":"Pentium III 500","ram_mb":128},
                                        {"cpu":"Athlon XP 1800+","ram_mb":512}]}'::jsonb AS doc
)
SELECT doc ->> 'user'           AS username,
       rig ->> 'cpu'            AS cpu,
       (rig ->> 'ram_mb')::int  AS ram_mb
FROM payload, jsonb_array_elements(doc -> 'rigs') AS rig;

-- 6.16 PII masking / pseudonymisation — share data without exposing emails
SELECT user_id,
       left(email, 2) || '***@' || split_part(email, '@', 2) AS masked_email,
       md5(email)                                             AS email_hash   -- stable join key
FROM users
LIMIT 10;


-- =====================================================================
-- YOUR TURN  (answers in solutions/06_solutions.sql)
-- =====================================================================

-- Q1. From stg_signups_raw, extract the email DOMAIN (after the @) in lower case,
--     and count signups per domain. Ignore NULL emails.
--     L1: split_part(text, delimiter, n) is your friend.
--     L2: SELECT split_part(lower(trim(email)), '____', ____) AS domain, count(*) ... WHERE email IS NOT NULL GROUP BY ____

-- Q2. Normalise favourite_game to a game_id from the games table.
--     'NFS II', 'need for speed 2', 'Need For Speed II' should ALL map to Need for Speed II.
--     L1: build an alias table with VALUES (like 6.6), then fall back to a case-insensitive title match.
--     L2: WITH game_alias(alias, title) AS (VALUES ('nfs ii','Need for Speed II'), ('need for speed 2', '____'), ...)

-- Q3. Pivot: for each manufacturer, count CPUs released per "era" as columns:
--     era_90s (before 2000), era_00_04 (2000–2004), era_05_08 (2005+).
--     L1: count(*) FILTER (WHERE ...) three times.
--     L2: count(*) FILTER (WHERE release_date < '____') AS era_90s, ...

-- Q4. Unpivot the games table so each game becomes 3 rows: min_cpu_mhz, rec_cpu_mhz, min_ram_mb.
--     L1: CROSS JOIN LATERAL (VALUES ...) like 6.13.
--     L2: CROSS JOIN LATERAL (VALUES ('min_cpu_mhz', g.min_cpu_mhz), ('____', g.____), ('____', g.____)) AS kv(metric, value)

-- Q5. Build a JSON object per GAME: title, genre, and an array of the 3 CPUs it was played on most.
--     L1: rank CPUs per game in a CTE first, keep top 3, then jsonb_agg.
--     L2: ... row_number() OVER (PARTITION BY game_id ORDER BY count(*) DESC) AS rn ... WHERE rn <= 3 ... jsonb_agg(model ORDER BY rn)
