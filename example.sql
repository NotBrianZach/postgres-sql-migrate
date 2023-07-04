-- Give each migration a unique name:
SELECT _v.apply_patch('woofs_schema'::text,
                   NULL::text[],
                   NULL::text[],
                   $$
                   create schema woofs authorization anon;

                   grant usage on schema woofs to anon;

                   -- GRANT INSERT,SELECT, UPDATE, DELETE ON ALL TABLES IN SCHEMA woofs TO anon;

                   create extension if not exists pg_jsonschema with schema extensions;
                   $$::text,
                   $$
                    drop schema woofs cascade;
                   $$::text
);

-- SELECT apply_patch('woofs_tables',
--                    ['woofs_schema'],
--                     NULL,
--                    $$
--                    -- SQL to apply goes here
--                    CREATE TABLE things (
--                      name TEXT
--                    );
--                    $$,
--                    $$
--                     DROP TABLE things;
--                    $$
-- );


-- SELECT apply_patch('woofs_views',
-- $$
--   -- SQL to apply goes here
--   CREATE TABLE things (
--     name TEXT
--   );
-- $$);
