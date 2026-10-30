-- =====================================================================
-- 04_seed_staging_messy.sql — Dirty raw data, just like real life
-- =====================================================================
-- stg_signups_raw    : a forum sign-up CSV that nobody validated.
--   problems hidden inside: extra spaces, MiXeD case, duplicate people,
--   5 different date formats, invalid dates, bad emails, NULLs,
--   country written as code / native name / typo.
--
-- stg_cpu_price_feed : 3 nightly batches of CPU street prices.
--   used for UPSERT, MERGE, SCD Type 2 and incremental loads (Lesson 07).
--   prices are illustrative.
-- =====================================================================
SET search_path TO retro;

INSERT INTO stg_signups_raw (full_name, email, country, signup_date, favourite_cpu, favourite_game, source_file, loaded_at) VALUES
('  shahed FAROOQUI ',  'Shahed.F@HOTMAIL.com ',      'india',          '2001-03-05',    'pentium iii 500',      'Project IGI',            'signups_2001_03_a.csv','2001-03-06 02:00'),
('Ayesha Siddiqui',     'ayesha.s@yahoo.com',         'PK',             '05/03/2001',    'Celeron 300A',         'need for speed 2',       'signups_2001_03_a.csv','2001-03-06 02:00'),
('ayesha  siddiqui',    'AYESHA.S@YAHOO.COM',         'Pakistan',       '2001-03-05',    'celeron 300a',         'NFS II',                 'signups_2001_03_b.csv','2001-03-07 02:00'),
('John   Smith',        'john_smith@aol',             'USA',            'March 7 2001',  'Athlon 600',           'Quake III',              'signups_2001_03_a.csv','2001-03-06 02:00'),
('Ravi Kumar',          NULL,                         'India ',         '2001-03-08',    'P2 450',               'Age of Empires 2',       'signups_2001_03_a.csv','2001-03-06 02:00'),
('Maria Garcia',        'maria.g@lycos.com',          'Spain',          '2001/03/09',    'K6-2 300',             'Carmageddon',            'signups_2001_03_a.csv','2001-03-06 02:00'),
('Kenji Tanaka',        'kenji@tanaka.jp',            'Japan',          '09-03-2001',    'pentium ii 300',       'StarCraft',              'signups_2001_03_a.csv','2001-03-06 02:00'),
('Fatima Zahra',        'fatima.zahra@gmail.com',     'U.A.E',          '2001-03-10',    'Duron 800',            'Diablo 2',               'signups_2001_03_a.csv','2001-03-06 02:00'),
('',                    'blank@hotmail.com',          'Germany',        '2001-03-10',    'Pentium 4 1.5GHz',     'Half-Life',              'signups_2001_03_a.csv','2001-03-06 02:00'),
('Omar Abdullah',       'omar.a@hotmail.com',         'Saudia',         '2001-13-45',    'athlon 1000',          'Counter Strike',         'signups_2001_03_a.csv','2001-03-06 02:00'),
('Chloe Martin',        'chloe.martin@hotmail.fr',    'France',         '2001-03-11',    'Pentium III 733',      'The Sims',               'signups_2001_03_a.csv','2001-03-06 02:00'),
('Lukas Muller',        'lukas.mueller@web.de',       'Deutschland',    '2001-03-11',    'Athlon 1000 Thunderbird','Unreal Tournament',    'signups_2001_03_a.csv','2001-03-06 02:00'),
('Ahmed Khan',          'ahmed.khan@rediffmail.com',  'IN',             '2001-03-12',    'Pentium III 1000',     'Project IGI',            'signups_2001_03_a.csv','2001-03-06 02:00'),
('Ahmed Khan',          'ahmed.khan@rediffmail.com',  'IN',             '2001-03-12',    'Pentium III 1000',     'Project IGI',            'signups_2001_03_b.csv','2001-03-07 02:00'),
('Priya Sharma',        'priya.sharma@rediffmail.com','india',          '12-Mar-2001',   'pentium 4 1.5ghz',     'Red Alert 2',            'signups_2001_03_b.csv','2001-03-07 02:00'),
('Wei Chen',            'wei.chen@yahoo.com',         'N/A',            '2001-03-12',    NULL,                   'StarCraft',              'signups_2001_03_b.csv','2001-03-07 02:00'),
('Emeka Obi',           'emeka.obi@yahoo.com',        'nigeria',        '2001-03-13',    'athlon 1000',          'counter strike',         'signups_2001_03_b.csv','2001-03-07 02:00'),
('Sofia Rossi',         'sofia.rossi@libero.it',      'Italy',          ' 2001-03-13 ',  ' pentium   iii 1000 ', 'Diablo II',              'signups_2001_03_b.csv','2001-03-07 02:00'),
('Tom O''Brien',        'tom.obrien@aol.com',         'United Kingdom', '2001-03-14',    'AMD K6-III 450',       'Unreal Tournament',      'signups_2001_03_b.csv','2001-03-07 02:00'),
('Ana Silva',           'ana.silva@bol.com.br',       'Brasil',         '14/03/2001',    'Celeron 300A',         'Age of Empires',         'signups_2001_03_b.csv','2001-03-07 02:00'),
('Noah Wilson',         'noah.wilson@hotmail.com',    'canada',         '2001-03-15',    'pentium mmx 233',      'NFS 3',                  'signups_2001_03_b.csv','2001-03-07 02:00'),
('Zainab Hussain',      'zainab.h@hotmail.co.uk',     'UK',             '2001-03-15',    'Cyrix MII-300',        'Roller Coaster Tycoon',  'signups_2001_03_b.csv','2001-03-07 02:00'),
('Bilal   Qureshi',     'bilal.q@@hotmail.com',       'pakistan',       '15.03.2001',    'K6-2 450',             'Need For Speed II',      'signups_2001_03_b.csv','2001-03-07 02:00'),
(NULL,                  NULL,                         NULL,             NULL,            NULL,                   NULL,                     'signups_2001_03_b.csv','2001-03-07 02:00');

INSERT INTO stg_cpu_price_feed (cpu_model, price_usd, price_date, batch_id, loaded_at) VALUES
-- batch 1 — spring 1999
('Pentium II 450',   669.00, '1999-03-01', 1, '1999-03-02 01:00'),
('Pentium III 500',  696.00, '1999-03-01', 1, '1999-03-02 01:00'),
('Celeron 300A',     149.00, '1999-03-01', 1, '1999-03-02 01:00'),
('K6-2 300',         129.00, '1999-03-01', 1, '1999-03-02 01:00'),
-- batch 2 — autumn 1999 (prices drop, Athlon arrives)
('Pentium II 450',   400.00, '1999-09-01', 2, '1999-09-02 01:00'),
('Pentium III 500',  450.00, '1999-09-01', 2, '1999-09-02 01:00'),
('Celeron 300A',      79.00, '1999-09-01', 2, '1999-09-02 01:00'),
('K6-2 300',          69.00, '1999-09-01', 2, '1999-09-02 01:00'),
('Athlon 600',       615.00, '1999-09-01', 2, '1999-09-02 01:00'),
-- batch 3 — spring 2000 (K6-2 unchanged, Celeron row sent twice, 1 GHz arrives)
('Pentium III 500',  239.00, '2000-03-01', 3, '2000-03-02 01:00'),
('Celeron 300A',      59.00, '2000-03-01', 3, '2000-03-02 01:00'),
('Celeron 300A',      59.00, '2000-03-01', 3, '2000-03-02 01:05'),
('K6-2 300',          69.00, '2000-03-01', 3, '2000-03-02 01:00'),
('Athlon 600',       349.00, '2000-03-01', 3, '2000-03-02 01:00'),
('Pentium III 1000', 990.00, '2000-03-01', 3, '2000-03-02 01:00');
