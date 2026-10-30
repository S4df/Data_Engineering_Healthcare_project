-- =====================================================================
-- 01_schema.sql — Tables for the "Retro PC Gaming" practice database
-- =====================================================================
-- Story: it's 1997–2008. Gamers around the world sign up to a forum,
-- build PCs (rigs) with old-school CPUs, and log their gaming sessions.
-- Did NFS II run smooth on your Pentium MMX 233? The data knows.
--
--   countries ─┐
--              └─< users >─┬─< rigs >── cpus
--                          └─< game_sessions >── games
--                                   │
--                                   └── rig_id (which PC it was played on)
--
-- Plus two *messy* staging tables for cleaning / data-engineering practice.
-- =====================================================================

DROP SCHEMA IF EXISTS retro CASCADE;
CREATE SCHEMA retro;
SET search_path TO retro;

-- ---------------------------------------------------------------------
-- Reference / dimension-style tables
-- ---------------------------------------------------------------------
CREATE TABLE countries (
    country_id          SMALLINT     PRIMARY KEY,
    iso2                CHAR(2)      NOT NULL UNIQUE,
    country_name        TEXT         NOT NULL UNIQUE,
    capital             TEXT,
    region              TEXT         NOT NULL,          -- Asia, Europe, Americas, Africa, Oceania
    sub_region          TEXT,
    population_millions NUMERIC(7,2),
    currency_code       CHAR(3)
);

CREATE TABLE cpus (
    cpu_id               SMALLINT     PRIMARY KEY,
    manufacturer         TEXT         NOT NULL CHECK (manufacturer IN ('Intel','AMD','Cyrix','IDT')),
    model                TEXT         NOT NULL UNIQUE,
    family               TEXT         NOT NULL,         -- Pentium, Athlon, K6-2 ...
    codename             TEXT,                          -- Klamath, Thunderbird ... (NULL = unknown)
    release_date         DATE         NOT NULL,
    clock_mhz            INT          NOT NULL,
    cores                SMALLINT     NOT NULL DEFAULT 1,
    process_nm           SMALLINT,                      -- manufacturing process in nanometres
    transistors_millions NUMERIC(6,1),
    socket               TEXT,
    launch_price_usd     NUMERIC(7,2)                   -- NULL = unknown (on purpose: NULL practice)
);

CREATE TABLE games (
    game_id       SMALLINT     PRIMARY KEY,
    title         TEXT         NOT NULL UNIQUE,
    release_year  SMALLINT     NOT NULL,                -- PC release year
    developer     TEXT,
    publisher     TEXT,
    genre         TEXT         NOT NULL,
    min_cpu_mhz   INT          NOT NULL,                -- box "minimum requirements"
    rec_cpu_mhz   INT          NOT NULL,                -- single-core MHz needed to run *perfectly*
    min_ram_mb    INT          NOT NULL,
    multiplayer   BOOLEAN      NOT NULL,
    fan_rating    NUMERIC(3,1)                          -- 1.0–10.0, dummy community score
);

-- ---------------------------------------------------------------------
-- Entity / fact-style tables (generated in 03_seed_generated.sql)
-- ---------------------------------------------------------------------
CREATE TABLE users (
    user_id      INT          PRIMARY KEY,
    username     TEXT         NOT NULL UNIQUE,
    first_name   TEXT         NOT NULL,
    last_name    TEXT         NOT NULL,
    email        TEXT         NOT NULL UNIQUE,
    country_id   SMALLINT     NOT NULL REFERENCES countries,
    birth_year   SMALLINT,
    signup_date  DATE         NOT NULL,
    is_active    BOOLEAN      NOT NULL,
    referred_by  INT          REFERENCES users (user_id)   -- self-join practice
);

CREATE TABLE rigs (
    rig_id    INT       PRIMARY KEY,
    user_id   INT       NOT NULL REFERENCES users,
    cpu_id    SMALLINT  NOT NULL REFERENCES cpus,
    ram_mb    INT       NOT NULL,
    gpu       TEXT      NOT NULL,
    built_on  DATE      NOT NULL
);

CREATE TABLE game_sessions (
    session_id    BIGINT     PRIMARY KEY,
    user_id       INT        NOT NULL REFERENCES users,
    game_id       SMALLINT   NOT NULL REFERENCES games,
    rig_id        INT        NOT NULL REFERENCES rigs,
    started_at    TIMESTAMP  NOT NULL,
    duration_min  INT        NOT NULL,
    avg_fps       NUMERIC(5,1) NOT NULL,                -- 60+ = "runs perfectly"
    crashed       BOOLEAN    NOT NULL
);

-- ---------------------------------------------------------------------
-- Raw staging tables (deliberately dirty — everything is TEXT)
-- ---------------------------------------------------------------------
CREATE TABLE stg_signups_raw (
    raw_id          SERIAL     PRIMARY KEY,
    full_name       TEXT,
    email           TEXT,
    country         TEXT,
    signup_date     TEXT,      -- mixed formats, some invalid
    favourite_cpu   TEXT,
    favourite_game  TEXT,
    source_file     TEXT,
    loaded_at       TIMESTAMP
);

CREATE TABLE stg_cpu_price_feed (
    feed_id     SERIAL     PRIMARY KEY,
    cpu_model   TEXT       NOT NULL,
    price_usd   NUMERIC(7,2),
    price_date  DATE       NOT NULL,
    batch_id    INT        NOT NULL,   -- 1, 2, 3 = three nightly loads
    loaded_at   TIMESTAMP  NOT NULL
);

-- Indexes a DBA would add for the common join paths
CREATE INDEX ix_users_country      ON users (country_id);
CREATE INDEX ix_rigs_user_built    ON rigs (user_id, built_on);
CREATE INDEX ix_sessions_user_time ON game_sessions (user_id, started_at);
CREATE INDEX ix_sessions_game      ON game_sessions (game_id);
