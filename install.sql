DO
$body$
BEGIN
  CREATE SCHEMA IF NOT EXISTS _v;
  COMMENT ON SCHEMA _v IS 'Schema for versioning data and functionality.';

  IF NOT EXISTS (SELECT FROM pg_catalog.pg_tables WHERE tablename = 'patches') THEN

    CREATE TABLE _v.rollbacked_patches (
      patch_name TEXT NOT NULL PRIMARY KEY,
      ddl TEXT NOT NULL,
      rollback_ddl TEXT NOT NULL,
      rollbacked_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
    );

    -- if a patch is found in this table, it should already be applied to the database
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
      var_dep_ddl TEXT;
      var_conflict TEXT;
      var_dep_rollback_ddl TEXT;
      var_dep_conflicts TEXT[];
      var_dep_dependencies TEXT[];
      -- debug_var text;
    BEGIN
      LOCK TABLE _v.patches IN EXCLUSIVE MODE;

      IF
        EXISTS (SELECT 1 FROM _v.patches p WHERE p.patch_name = in_patch_name)
      THEN
        RAISE EXCEPTION 'Patch % already applied', in_patch_name;
      END IF;

      IF conflicts IS NOT NULL THEN
        foreach var_conflict IN ARRAY conflicts LOOP
          IF EXISTS (SELECT 1 FROM _v.patches p WHERE p.patch_name = var_conflict) THEN
            RAISE EXCEPTION 'Conflicting patch currently applied % ', var_conflict;
          END IF;

          INSERT INTO _v.patch_conflicts (patch_name, conflict_name) VALUES (in_patch_name, var_conflict);
        END LOOP;
      END IF;

      IF dependencies IS NOT NULL THEN
          FOREACH var_dep IN ARRAY dependencies LOOP
            RAISE NOTICE 'Checking if patch dependency % is applied', var_dep;
            -- SELECT patch_name INTO debug_var FROM _v.patches LIMIT 1;
            -- IF debug_var IS NOT NULL THEN
            --   RAISE NOTICE 'The patch name is: %', debug_var;
            -- ELSE
            --   RAISE NOTICE 'No patch name found.';
            -- END IF;
            IF NOT EXISTS (SELECT 1 FROM _v.patches p WHERE p.patch_name = var_dep) THEN
                IF NOT EXISTS (SELECT 1 FROM _v.rollbacked_patches r WHERE r.patch_name = var_dep) THEN
                    RAISE EXCEPTION 'No rollback patch found for unapplied patch dependency %, need to apply manually', var_dep;
                END IF;

                SELECT ddl, rollback_ddl INTO var_dep_ddl, var_dep_rollback_ddl FROM _v.rollbacked_patches WHERE patch_name = var_dep;

                RAISE NOTICE 'Rollbacked patch found; applying patch dependency: %', var_dep;

                -- Getting dependencies of the rollbacked patch
                SELECT ARRAY_AGG(depend_name) INTO var_dep_dependencies FROM _v.patch_deps WHERE patch_name = var_dep;

                SELECT ARRAY_AGG(conflict_name) INTO var_dep_conflicts FROM _v.patch_conflicts WHERE patch_name = var_dep;

                PERFORM _v.apply_patch(var_dep, var_dep_dependencies, var_dep_conflicts, var_dep_ddl, var_dep_rollback_ddl);

                RAISE NOTICE 'Deleting relevant entry from rollback table: %', var_dep;
                DELETE FROM _v.rollbacked_patches WHERE patch_name = var_dep;
            END IF;
          END LOOP;
      END IF;

      RAISE NOTICE 'Applying patch: %', in_patch_name;
      EXECUTE in_ddl;

      INSERT INTO _v.patches (patch_name, ddl, rollback_ddl) VALUES (in_patch_name, in_ddl, in_rollback_ddl);
      IF dependencies IS NOT NULL THEN
        FOREACH var_dep IN ARRAY dependencies LOOP
          INSERT INTO _v.patch_deps (patch_name, depend_name) VALUES (in_patch_name, var_dep);
        END LOOP;
      END IF;

      RETURN TRUE;
    END;
    $$ LANGUAGE plpgsql;
  END IF;

  IF NOT EXISTS (SELECT FROM pg_catalog.pg_proc WHERE proname = 'rollback_patch') THEN
    CREATE FUNCTION _v.rollback_patch (in_patch_name TEXT) RETURNS BOOLEAN
    AS $$
      DECLARE
        var_dep TEXT;
        var_rollback_ddl TEXT;
        var_ddl TEXT;
        var_dep_ddl TEXT;
        var_dep_rollback_ddl TEXT;
        var_dependencies TEXT[];
        var_dep_dependencies TEXT[];
      BEGIN
        LOCK TABLE _v.rollbacked_patches IN EXCLUSIVE MODE;

        SELECT ddl,rollback_ddl INTO var_ddl,var_rollback_ddl FROM _v.patches WHERE patch_name = in_patch_name;

        IF var_rollback_ddl IS NULL THEN
          RAISE EXCEPTION 'Rollback ddl for patch % not found', in_patch_name;
        END IF;

        IF var_ddl IS NULL THEN
          RAISE EXCEPTION 'DDL for patch % not found when trying to transition into rollback_table', in_patch_name;
        END IF;

        SELECT ARRAY_AGG(patch_name) INTO var_dependencies FROM _v.patch_deps WHERE depend_name = in_patch_name;
        IF var_dependencies IS NOT NULL THEN
            FOREACH var_dep IN ARRAY var_dependencies LOOP
                IF EXISTS (SELECT 1 FROM _v.patches p WHERE p.patch_name = var_dep) THEN
                    SELECT ddl, rollback_ddl INTO var_dep_ddl, var_dep_rollback_ddl FROM _v.rollbacked_patches WHERE patch_name = var_dep;
                    RAISE NOTICE 'Rollback patch dependency found; initiating dependency roll back for: %', var_dep;
                    delete from _v.patch_deps where patch_name = var_dep;
                    PERFORM _v.rollback_patch(var_dep);
                END IF;
            END LOOP;
        END IF;

        -- Execute rollback ddl for in_patch_name
        RAISE NOTICE 'Rolling back patch: %', in_patch_name;
        EXECUTE var_rollback_ddl;

        DELETE FROM _v.patches WHERE patch_name = in_patch_name;

        INSERT INTO _v.rollbacked_patches (patch_name, ddl, rollback_ddl) VALUES (in_patch_name, var_ddl, var_rollback_ddl);
        RAISE NOTICE 'patch rolled back, tables updated: %', in_patch_name;

        RETURN TRUE;
      END;
    $$ LANGUAGE plpgsql;
  END IF;
END
$body$;
