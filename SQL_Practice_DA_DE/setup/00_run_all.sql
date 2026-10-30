-- =====================================================================
-- 00_run_all.sql — Build the whole practice database in one go
-- =====================================================================
--   createdb sql_practice
--   psql -d sql_practice -f setup/00_run_all.sql
--
-- Safe to re-run any time: it drops and rebuilds schema "retro".
-- =====================================================================
\set ON_ERROR_STOP on
\echo '>> 1/4 schema'
\ir 01_schema.sql
\echo '>> 2/4 countries, cpus, games'
\ir 02_seed_reference.sql
\echo '>> 3/4 users, rigs, game_sessions (generated)'
\ir 03_seed_generated.sql
\echo '>> 4/4 messy staging data'
\ir 04_seed_staging_messy.sql

-- So you can type "users" instead of "retro.users" in every new session
DO $$ BEGIN
    EXECUTE format('ALTER DATABASE %I SET search_path = retro, public', current_database());
END $$;

-- Let the non-superuser login "shahed" (used by pgAdmin / VS Code explorer) see and use retro.
-- Rebuilding drops the schema, so the grants are re-applied here every time.
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'shahed') THEN
        EXECUTE format('GRANT CONNECT, CREATE ON DATABASE %I TO shahed', current_database());
        GRANT USAGE, CREATE ON SCHEMA retro TO shahed;
        GRANT ALL ON ALL TABLES    IN SCHEMA retro TO shahed;
        GRANT ALL ON ALL SEQUENCES IN SCHEMA retro TO shahed;
        GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA retro TO shahed;
    END IF;
END $$;

\echo ''
\echo '>> Row counts:'
SELECT 'countries'          AS table_name, count(*) AS rows FROM retro.countries
UNION ALL SELECT 'cpus',               count(*) FROM retro.cpus
UNION ALL SELECT 'games',              count(*) FROM retro.games
UNION ALL SELECT 'users',              count(*) FROM retro.users
UNION ALL SELECT 'rigs',               count(*) FROM retro.rigs
UNION ALL SELECT 'game_sessions',      count(*) FROM retro.game_sessions
UNION ALL SELECT 'stg_signups_raw',    count(*) FROM retro.stg_signups_raw
UNION ALL SELECT 'stg_cpu_price_feed', count(*) FROM retro.stg_cpu_price_feed;
