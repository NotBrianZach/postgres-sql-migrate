-- This file provides a method for applying incremental schema changes
-- to a PostgreSQL database.

-- Add your migrations at the end of the file, and run "psql -v ON_ERROR_STOP=1 -1f
-- migrations.sql yourdbname" to apply all pending migrations. The
-- "-1" causes all the changes to be applied atomically

-- Most Rails (ie. ActiveRecord) migrations are run by a user with
-- full read-write access to both the schema and its contents, which
-- isn't ideal. You'd generally run this file as a database owner, and
-- the contained migrations would grant access to less-privileged
-- application-level users as appropriate.
DO
$body$
BEGIN
  -- This file adds versioning support to database it will be loaded to.
  -- It requires that PL/pgSQL is already loaded - will raise exception otherwise.
  -- All versioning "stuff" (tables, functions) is in "_v" schema.

  CREATE SCHEMA IF NOT EXISTS _v;
  COMMENT ON SCHEMA _v IS 'Schema for versioning data and functionality.';

  IF NOT EXISTS (SELECT FROM pg_catalog.pg_tables WHERE tablename = 'patches') THEN
    -- CREATE TABLE applied_migrations (
    --   id TEXT NOT NULL PRIMARY KEY
    --   , ddl TEXT NOT NULL
    --   , applied_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
    -- );

    CREATE TABLE _v.rollbacked_patches (
      patch_name TEXT NOT NULL PRIMARY KEY,
      ddl TEXT NOT NULL,
      rollback_ddl TEXT NOT NULL,
      rollbacked_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
    );
    CREATE TABLE _v.patches (
      patch_name TEXT NOT NULL PRIMARY KEY,
      ddl TEXT NOT NULL,
      rollback_ddl TEXT NOT NULL,
      -- applied_by TEXT NOT NULL,
      -- author TEXT NOT NULL,
      -- COMMENT ON COLUMN _v.patches.applied_by  IS 'Who applied this patch (PostgreSQL username)';
      -- COMMENT ON COLUMN _v.patches.author_email  IS 'Who wrote this patch';
      applied_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS _v.patch_deps (
      patch_name TEXT NOT NULL REFERENCES _v.patches(patch_name),
      depend_name TEXT NOT NULL REFERENCES _v.patches(patch_name)
    );

    CREATE TABLE IF NOT EXISTS _v.patch_conflicts (
      patch_name TEXT NOT NULL REFERENCES _v.patches(patch_name),
      conflict_name TEXT NOT NULL REFERENCES _v.patches(patch_name)
    );
  END IF;

  IF NOT EXISTS (SELECT FROM pg_catalog.pg_proc WHERE proname = 'apply_patch') THEN
    CREATE FUNCTION _v.apply_patch (in_patch_name TEXT,
                                    dependencies TEXT[],
                                    conflicts TEXT[],
                                    in_ddl TEXT,
                                    in_rollback_ddl TEXT) RETURNS BOOLEAN
    AS $$
          DECLARE
          var_dep TEXT;
          var_conflict TEXT;
    BEGIN
      LOCK TABLE _v.patches IN EXCLUSIVE MODE;
      IF
        NOT EXISTS (SELECT 1 FROM _v.patches p WHERE p.patch_name = in_patch_name)
          AND
        NOT EXISTS (SELECT 1 FROM _v.patch_conflicts c WHERE c.patch_name = in_patch_name)
      THEN
        RAISE NOTICE 'Applying patch: %', in_patch_name;
        EXECUTE in_ddl;
        INSERT INTO _v.patches (patch_name, ddl, rollback_ddl) VALUES (in_patch_name, in_ddl, in_rollback_ddl);
        IF dependencies IS NOT NULL THEN
          foreach var_dep IN ARRAY dependencies LOOP
            INSERT INTO _v.patch_deps (patch_name, depend_name) VALUES (in_patch_name, var_dep);
          END LOOP;
        END IF;

        IF conflicts IS NOT NULL THEN
          IF EXISTS (SELECT 1 FROM _v.patches p WHERE p.patch_name = ANY(conflicts)) THEN
            RAISE NOTICE 'Patch % already applied', in_patch_name;
            RETURN FALSE;
          END IF;
          foreach var_conflict IN ARRAY conflicts LOOP
            INSERT INTO _v.patch_conflicts (patch_name, conflict_name) VALUES (in_patch_name, var_conflict);
          END LOOP;
        END IF;
        RETURN TRUE;
      END IF;
      RETURN FALSE;
    END;
    $$ LANGUAGE plpgsql;
  END IF;

  IF NOT EXISTS (SELECT FROM pg_catalog.pg_proc WHERE proname = 'rollback_patch') THEN
CREATE FUNCTION _v.rollback_patch (in_patch_name TEXT) RETURNS BOOLEAN
AS $$
  DECLARE
    var_dependent_patch TEXT;
    var_rollback_ddl TEXT;
    dependent_patches CURSOR FOR
      SELECT depend_name FROM _v.patch_deps WHERE depend_name = in_patch_name;
  BEGIN
    SELECT rollback_ddl INTO var_rollback_ddl FROM _v.patches WHERE patch_name = in_patch_name;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Patch % not found', in_patch_name;
    END IF;

    -- Retrieve dependent patches
    OPEN dependent_patches;
    LOOP
      FETCH dependent_patches INTO var_dependent_patch;
      EXIT WHEN NOT FOUND;

      -- Rollback and raise notice for each dependent patch
      RAISE NOTICE 'Rolling back dependent patch: %', var_dependent_patch;
      PERFORM _v.rollback_patch(var_dependent_patch);
    END LOOP;
    CLOSE dependent_patches;

    -- Execute rollback ddl for in_patch_name
    RAISE NOTICE 'Rolling back patch: %', in_patch_name;
    EXECUTE var_rollback_ddl;
    DELETE FROM _v.patches WHERE patch_name = in_patch_name;
    RETURN TRUE;
  END;
$$ LANGUAGE plpgsql;
  END IF;

END
$body$;

