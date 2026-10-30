-- =====================================================================
-- LESSON 08 — ANALYTICS PATTERNS (real business questions)
-- =====================================================================
-- Goal: combine everything — CTEs + windows + aggregates — to answer
--       questions a product / data team actually asks.
--   "perfect running" analysis · cohort retention · gaps & islands ·
--   sessionization · Pareto 80/20 · market share · funnel · outliers · churn
-- =====================================================================
SET search_path TO retro;

-- 8.1  PERFECT RUNNING — slowest CPU that ran each game perfectly
--      "perfect" = avg_fps >= 60 in at least 80% of sessions, min 5 sessions
WITH game_cpu AS (
    SELECT g.title, g.release_year, cp.model, cp.clock_mhz,
           count(*)                         AS sessions,
           avg((s.avg_fps >= 60)::int)      AS perfect_share
    FROM game_sessions s
    JOIN games g  USING (game_id)
    JOIN rigs r   USING (rig_id)
    JOIN cpus cp  ON cp.cpu_id = r.cpu_id
    GROUP BY g.title, g.release_year, cp.model, cp.clock_mhz
    HAVING count(*) >= 5
)
SELECT DISTINCT ON (title)
       title, release_year, model AS slowest_perfect_cpu, clock_mhz,
       sessions, round(100 * perfect_share) AS pct_perfect
FROM game_cpu
WHERE perfect_share >= 0.8
ORDER BY title, clock_mhz;

-- 8.2  "Can it run Crysis?" — best CPUs for Crysis, ranked by smoothness
SELECT cp.model, count(*) AS sessions,
       round(avg(s.avg_fps), 1)         AS mean_fps,
       max(s.avg_fps)                   AS best_fps,
       count(*) FILTER (WHERE s.crashed) AS crashes
FROM game_sessions s
JOIN games g USING (game_id)
JOIN rigs r  USING (rig_id)
JOIN cpus cp ON cp.cpu_id = r.cpu_id
WHERE g.title = 'Crysis'
GROUP BY cp.model
ORDER BY mean_fps DESC;

-- 8.3  COHORT RETENTION — of users who first played in year X,
--      what % were still playing 1, 2, 3 years later?
--      (data ends in 2008, so 2006+ cohorts show 0 for years that haven't happened)
WITH activity AS (
    SELECT DISTINCT user_id, extract(year FROM started_at)::int AS yr
    FROM game_sessions
),
cohort AS (
    SELECT user_id, min(yr) AS cohort_year FROM activity GROUP BY user_id
),
joined AS (
    SELECT c.cohort_year, a.yr - c.cohort_year AS years_later, a.user_id
    FROM activity a JOIN cohort c USING (user_id)
)
SELECT cohort_year,
       count(DISTINCT user_id) FILTER (WHERE years_later = 0) AS cohort_size,
       round(100.0 * count(DISTINCT user_id) FILTER (WHERE years_later = 1)
             / count(DISTINCT user_id) FILTER (WHERE years_later = 0)) AS y1_pct,
       round(100.0 * count(DISTINCT user_id) FILTER (WHERE years_later = 2)
             / count(DISTINCT user_id) FILTER (WHERE years_later = 0)) AS y2_pct,
       round(100.0 * count(DISTINCT user_id) FILTER (WHERE years_later = 3)
             / count(DISTINCT user_id) FILTER (WHERE years_later = 0)) AS y3_pct
FROM joined
GROUP BY cohort_year
ORDER BY cohort_year;

-- 8.4  GAPS & ISLANDS — longest streak of consecutive play days per user
--      Trick: date − row_number() is constant inside a streak.
WITH days AS (
    SELECT DISTINCT user_id, started_at::date AS d FROM game_sessions
),
grp AS (
    SELECT user_id, d,
           d - (row_number() OVER (PARTITION BY user_id ORDER BY d))::int AS island
    FROM days
),
streaks AS (
    SELECT user_id, min(d) AS streak_start, max(d) AS streak_end, count(*) AS days
    FROM grp
    GROUP BY user_id, island
)
SELECT u.username, s.streak_start, s.streak_end, s.days
FROM streaks s JOIN users u USING (user_id)
ORDER BY s.days DESC, s.streak_start
LIMIT 10;

-- 8.5  SESSIONIZATION — group sessions into "gaming nights":
--      a new night starts if the previous session began 4+ hours earlier
WITH ordered AS (
    SELECT user_id, session_id, started_at, duration_min,
           CASE WHEN started_at - lag(started_at) OVER w < INTERVAL '4 hours'
                THEN 0 ELSE 1 END AS new_night
    FROM game_sessions
    WINDOW w AS (PARTITION BY user_id ORDER BY started_at)
),
nights AS (
    SELECT *, sum(new_night) OVER (PARTITION BY user_id ORDER BY started_at) AS night_no
    FROM ordered
)
SELECT user_id, night_no, min(started_at) AS night_start,
       count(*) AS sessions, sum(duration_min) AS total_minutes
FROM nights
GROUP BY user_id, night_no
HAVING count(*) > 1
ORDER BY total_minutes DESC
LIMIT 10;

-- 8.6  PARETO 80/20 — what % of users generate 80% of hours played?
WITH per_user AS (
    SELECT user_id, sum(duration_min) AS minutes FROM game_sessions GROUP BY user_id
),
ranked AS (
    SELECT user_id, minutes,
           sum(minutes) OVER (ORDER BY minutes DESC, user_id) / sum(minutes) OVER () AS cum_share,
           row_number() OVER (ORDER BY minutes DESC, user_id)                      AS user_rank,
           count(*)     OVER ()                                                   AS total_users
    FROM per_user
)
SELECT min(user_rank)                                       AS users_needed,
       max(total_users)                                     AS total_users,
       round(100.0 * min(user_rank) / max(total_users), 1)  AS pct_of_users
FROM ranked
WHERE cum_share >= 0.8;

-- 8.7  MARKET SHARE OVER TIME — Intel vs AMD vs others in newly built rigs
WITH built AS (
    SELECT extract(year FROM r.built_on)::int AS yr, cp.manufacturer, count(*) AS rigs_built
    FROM rigs r
    JOIN cpus cp USING (cpu_id)
    GROUP BY 1, 2
)
SELECT yr, manufacturer, rigs_built,
       round(100.0 * rigs_built / sum(rigs_built) OVER (PARTITION BY yr), 1) AS share_pct
FROM built
ORDER BY yr, manufacturer;

-- 8.8  FUNNEL — signed up → upgraded PC → 30+ sessions → 50+ sessions → dared to run Crysis
--      Each step only counts users who also passed every earlier step.
WITH u AS (
    SELECT u.user_id,
           (SELECT count(*) FROM rigs r WHERE r.user_id = u.user_id)           AS rigs,
           (SELECT count(*) FROM game_sessions s WHERE s.user_id = u.user_id)  AS sessions,
           EXISTS (SELECT 1 FROM game_sessions s JOIN games g USING (game_id)
                   WHERE s.user_id = u.user_id AND g.title = 'Crysis')         AS tried_crysis
    FROM users u
)
SELECT step, users,
       round(100.0 * users / first_value(users) OVER (ORDER BY ord), 1) AS pct_of_signups,
       round(100.0 * users / lag(users) OVER (ORDER BY ord), 1)         AS pct_of_prev_step
FROM (
    SELECT 1, '1 signed up',     count(*)                                                     FROM u UNION ALL
    SELECT 2, '2 upgraded PC',   count(*) FILTER (WHERE rigs >= 2)                            FROM u UNION ALL
    SELECT 3, '3 30+ sessions',  count(*) FILTER (WHERE rigs >= 2 AND sessions >= 30)         FROM u UNION ALL
    SELECT 4, '4 50+ sessions',  count(*) FILTER (WHERE rigs >= 2 AND sessions >= 50)         FROM u UNION ALL
    SELECT 5, '5 tried Crysis',  count(*) FILTER (WHERE rigs >= 2 AND sessions >= 50 AND tried_crysis) FROM u
) f(ord, step, users)
ORDER BY ord;

-- 8.9  OUTLIERS — sessions far from the game's normal fps (z-score > 2.5)
WITH stats AS (
    SELECT s.*, avg(avg_fps)    OVER (PARTITION BY game_id) AS game_mean,
                stddev(avg_fps) OVER (PARTITION BY game_id) AS game_sd
    FROM game_sessions s
)
SELECT g.title, st.session_id, st.avg_fps, round(st.game_mean, 1) AS game_mean,
       round((st.avg_fps - st.game_mean) / nullif(st.game_sd, 0), 2) AS z_score
FROM stats st JOIN games g USING (game_id)
WHERE abs((st.avg_fps - st.game_mean) / nullif(st.game_sd, 0)) > 2.5
ORDER BY abs((st.avg_fps - st.game_mean) / nullif(st.game_sd, 0)) DESC
LIMIT 15;

-- 8.10 CHURN — users whose last session was 1+ year before the data ends
WITH last_seen AS (
    SELECT user_id, max(started_at) AS last_session FROM game_sessions GROUP BY user_id
),
data_end AS (SELECT max(started_at) AS end_ts FROM game_sessions)
SELECT count(*) FILTER (WHERE l.last_session < d.end_ts - INTERVAL '1 year') AS churned,
       count(*)                                                              AS players,
       round(100.0 * count(*) FILTER (WHERE l.last_session < d.end_ts - INTERVAL '1 year') / count(*), 1) AS churn_pct
FROM last_seen l CROSS JOIN data_end d;

-- 8.11 MONTHLY ACTIVE USERS + month-over-month change
WITH mau AS (
    SELECT date_trunc('month', started_at)::date AS month, count(DISTINCT user_id) AS active_users
    FROM game_sessions
    GROUP BY 1
)
SELECT month, active_users,
       active_users - lag(active_users) OVER (ORDER BY month) AS mom_change
FROM mau
WHERE month >= '2007-01-01'
ORDER BY month;


-- =====================================================================
-- YOUR TURN  (answers in solutions/08_solutions.sql)
-- =====================================================================

-- Q1. For NFS-series games only (title ILIKE 'need for speed%'): which CPU MODEL
--     gave the highest % perfect runs (min 10 sessions)? One winner per game.
--     L1: aggregate per (game, cpu), then DISTINCT ON or row_number per game.
--     L2: ... GROUP BY g.title, cp.model HAVING count(*) >= ____ ... ORDER BY g.title, pct_perfect DESC

-- Q2. Peak hours: sessions per hour of day (0–23) and each hour's % of total.
--     L1: extract(hour FROM started_at), then the % of total window trick from 5.7.
--     L2: round(100.0 * count(*) / sum(count(*)) OVER (), 1)

-- Q3. Upgrade effect: for users with 2+ rigs, compare mean fps on their FIRST rig vs their LATEST rig.
--     L1: rank rigs per user (row_number ASC and DESC), join sessions, then FILTER by which rig.
--     L2: avg(s.avg_fps) FILTER (WHERE r.rn_asc = 1) AS first_rig_fps, avg(s.avg_fps) FILTER (WHERE r.rn_desc = 1) AS latest_rig_fps

-- Q4. Longest gap (in days) between two consecutive sessions per user. Top 10 users.
--     L1: LAG(started_at) per user, subtract, then max per user.
--     L2: max(started_at - lag_start) ... ORDER BY ____ DESC LIMIT 10   (the LAG must be computed in a CTE first)

-- Q5. Country leaderboard: for each REGION, the country with the most hours played per user.
--     L1: hours per country / users per country, then rank inside region.
--     L2: rank() OVER (PARTITION BY region ORDER BY hours_per_user DESC) = 1
