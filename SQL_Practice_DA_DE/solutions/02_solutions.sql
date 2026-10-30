-- =====================================================================
-- SOLUTIONS — Lesson 02
-- =====================================================================
SET search_path TO retro;

-- Q1. Genres with avg rating > 9
SELECT genre, count(*) AS games, round(avg(fan_rating), 2) AS avg_rating
FROM games
GROUP BY genre
HAVING avg(fan_rating) > 9
ORDER BY avg_rating DESC;

-- Q2. CPUs per manufacturer per release year
SELECT manufacturer,
       extract(year FROM release_date)::int AS yr,
       count(*)                             AS cpus,
       round(avg(clock_mhz))                AS avg_mhz
FROM cpus
GROUP BY manufacturer, yr
ORDER BY manufacturer, yr;

-- Q3. Top 10 games by hours played
SELECT g.title, round(sum(s.duration_min) / 60.0, 1) AS hours
FROM game_sessions s
JOIN games g USING (game_id)
GROUP BY g.title
ORDER BY hours DESC
LIMIT 10;

-- Q4. Crash rate per CPU family
SELECT c.family,
       count(*)                                                      AS sessions,
       round(count(*) FILTER (WHERE s.crashed) * 100.0 / count(*), 2) AS crash_pct
FROM game_sessions s
JOIN rigs r USING (rig_id)
JOIN cpus c ON c.cpu_id = r.cpu_id
GROUP BY c.family
ORDER BY crash_pct DESC;

-- Q5. Users per country: total / active / inactive
SELECT c.country_name,
       count(*)                                AS total,
       count(*) FILTER (WHERE u.is_active)     AS active,
       count(*) FILTER (WHERE NOT u.is_active) AS inactive
FROM users u
JOIN countries c USING (country_id)
GROUP BY c.country_name
ORDER BY total DESC;

-- Q6. Sessions per year + genre with subtotals
SELECT extract(year FROM s.started_at)::int AS yr,
       coalesce(g.genre, '— year total —')   AS genre,
       count(*)                              AS sessions
FROM game_sessions s
JOIN games g USING (game_id)
GROUP BY ROLLUP (extract(year FROM s.started_at)::int, g.genre)
ORDER BY yr NULLS LAST, g.genre NULLS LAST;
-- The row where yr is NULL too is the grand total.
