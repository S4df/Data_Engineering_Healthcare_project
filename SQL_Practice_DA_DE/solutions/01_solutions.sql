-- =====================================================================
-- SOLUTIONS — Lesson 01 (only open after you've tried L1 and L2!)
-- =====================================================================
SET search_path TO retro;

-- Q1. AMD CPUs released in 1999, fastest first
SELECT model, release_date, clock_mhz
FROM cpus
WHERE manufacturer = 'AMD'
  AND release_date >= DATE '1999-01-01'
  AND release_date <  DATE '2000-01-01'
ORDER BY clock_mhz DESC;
-- Why half-open (>= and <) instead of extract(year ...) = 1999?
-- Both work, but extract() on the column stops an index on release_date being used.

-- Q2. Racing games before 2000 needing <= 16 MB RAM
SELECT title, release_year, min_ram_mb
FROM games
WHERE genre = 'Racing'
  AND release_year < 2000
  AND min_ram_mb <= 16;

-- Q3. Price or 'not recorded'
SELECT model,
       COALESCE(launch_price_usd::text, 'not recorded') AS price
FROM cpus
ORDER BY launch_price_usd DESC NULLS LAST;
-- Note: we sort by the ORIGINAL numeric column, not the text alias.
-- Sorting text would put '990.00' above '1981.00'.

-- Q4. Inactive hotmail users
SELECT username, email, is_active
FROM users
WHERE email LIKE '%@hotmail.com'
  AND NOT is_active;

-- Q5. Oldest CPU per manufacturer
SELECT DISTINCT ON (manufacturer)
       manufacturer, model, release_date
FROM cpus
ORDER BY manufacturer, release_date ASC;

-- Q6. Titles with the whole word II or III
SELECT title
FROM games
WHERE title ~ '\m(II|III)\M';
