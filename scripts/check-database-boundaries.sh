#!/bin/sh
# Validate service-schema isolation using PostgreSQL's effective privileges.
# Run with the same administrator PG* variables used by the migrator.
#
# WHY THIS RUNS PER DATABASE NOW
#   Until release v55 this was one SQL block against one database, because
#   before the logical-database extraction every service schema lived together
#   in the monolith `warptalk`. v55 pointed the migrator's PGDATABASE at
#   `postgres` — an admin connection belongs in the maintenance database, not in
#   a retired application database — and the old block died on its first
#   privilege assertion:
#
#       ERROR:  schema "subscription" does not exist
#
#   has_schema_privilege() raises when the schema is absent, so a deploy failed
#   on a check that had outlived its own assumption. Nothing was wrong with the
#   cluster: `subscription` had moved into warptalk_billing years of migrations
#   ago, along with every other schema this file names.
#
#   The contract itself changed shape at that same cutover. Isolation BETWEEN
#   two services is now enforced by PostgreSQL and cannot be granted away: their
#   schemas live in different databases, and no foreign key, view or query can
#   cross a database boundary. Restating that as a privilege assertion would be
#   theatre. What is still worth asserting is what extract-logical-databases.sh
#   actually establishes, once per database:
#
#     1. the database carries an extraction marker naming the schemas it owns
#     2. the owning runtime role can read and write every table in them
#     3. no OTHER service's runtime role has been granted anything there
#     4. only the owning login may CONNECT, and PUBLIC may not
#     5. no foreign key or view crosses a bounded context inside the database
#
#   (3) and (4) are the checks that still earn their keep: roles are cluster-wide
#   objects, so a stray GRANT in one database is invisible from every other one,
#   and a leftover grant from the monolith era would never surface on its own.
#
# ORDER NOTE
#   The migrator runs this before extract-logical-databases.sh, so on a cluster
#   that has never been extracted there is nothing here yet. Databases that do
#   not exist are reported and skipped rather than failing the deploy — the
#   check gates drift in a running deployment, and a first deploy has none.
set -eu

PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
PGDATABASE="${PGDATABASE:-postgres}"
: "${PGPASSWORD:?PGPASSWORD is required}"
export PGPASSWORD

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
runner="$script_dir/run-logical-database-migrations.sh"
[ -f "$runner" ] || { echo "Missing $runner" >&2; exit 1; }

# Service -> database -> runtime role, read from the runner's own dispatch table
# rather than restated here. A service added to the runner becomes subject to
# this check automatically, and one removed from it stops being checked; the map
# cannot drift from the thing it describes.
# The override variable is captured alongside the default so this check can be
# pointed at a database the same way the runner can — that is what makes it
# testable against throwaway databases instead of only against the real ones.
#   apply_service auth "${AUTH_DATABASE:-warptalk_auth}" auth warptalk_auth_runtime
services="$(
  sed -n 's/^apply_service \([A-Za-z0-9-]*\) "\${\([A-Z_]*\):-\([A-Za-z0-9_]*\)}" [a-z_]* \([a-z_]*\).*/\2 \3 \4/p' \
    "$runner"
)"
[ -n "$services" ] || {
  echo "Could not read the service dispatch table from $runner" >&2
  exit 1
}

# Every runtime role in the deployment. Check (3) asks whether any role that is
# not this database's owner holds privileges in it, so it needs the whole set.
all_runtime_roles="$(echo "$services" | awk '{print $3}' | paste -sd, -)"

# The LOGIN role each service authenticates as. provision-service-db-users.sh
# creates warptalk_billing and grants it warptalk_billing_runtime, so the login
# is its runtime role without the suffix.
all_login_roles="$(echo "$services" | awk '{sub(/_runtime$/, "", $3); print $3}' | paste -sd, -)"

admin_psql() {
  psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" "$@"
}

checked=0
skipped=0

# Read the dispatch table from a file rather than a pipe: a `while read` on the
# right of a pipe runs in a subshell, and the counters reported at the end would
# be discarded with it.
service_list="$(mktemp)"
trap 'rm -f "$service_list"' EXIT INT TERM
printf '%s\n' "$services" > "$service_list"

while read -r database_var database_default runtime_role; do
  [ -n "$database_default" ] || continue
  database="$(printenv "$database_var" || true)"
  [ -n "$database" ] || database="$database_default"
  login_role="${runtime_role%_runtime}"

  exists="$(admin_psql -Atc "SELECT EXISTS (SELECT 1 FROM pg_database WHERE datname = '$database')")"
  if [ "$exists" != "t" ]; then
    echo "  $database: not extracted yet, skipping."
    skipped=$((skipped + 1))
    continue
  fi

  psql -X -q -v ON_ERROR_STOP=1 \
    -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$database" \
    -v "runtime_role=$runtime_role" \
    -v "login_role=$login_role" \
    -v "all_runtime_roles=$all_runtime_roles" \
    -v "all_login_roles=$all_login_roles" <<'SQL'
-- psql does not interpolate :variables inside a dollar-quoted body, so the
-- parameters are handed to the block through session settings instead.
SELECT set_config('warptalk.runtime_role', :'runtime_role', false),
       set_config('warptalk.login_role', :'login_role', false),
       set_config('warptalk.all_runtime_roles', :'all_runtime_roles', false),
       set_config('warptalk.all_login_roles', :'all_login_roles', false) \g /dev/null

DO $$
DECLARE
    runtime_role    text   := current_setting('warptalk.runtime_role');
    login_role      text   := current_setting('warptalk.login_role');
    all_roles       text[] := string_to_array(
                                  current_setting('warptalk.all_runtime_roles'), ',');
    all_logins      text[] := string_to_array(
                                  current_setting('warptalk.all_login_roles'), ',');
    owned_schemas   text[];
    service_schemas text[];
    problems        text[] := '{}';
    offender        record;
BEGIN
    -- Asked with to_regclass first: selecting from a missing table raises
    -- `relation does not exist`, which describes PostgreSQL's disappointment
    -- rather than the operator's problem. This is the same idiom
    -- extract-logical-databases.sh uses to recognise an extracted database.
    IF to_regclass('public.logical_database_extract') IS NOT NULL THEN
        SELECT extract_marker.owned_schemas INTO owned_schemas
        FROM public.logical_database_extract AS extract_marker
        ORDER BY extract_marker.extracted_at DESC
        LIMIT 1;
    END IF;

    IF owned_schemas IS NULL THEN
        RAISE EXCEPTION
            'database % has no logical_database_extract marker, so what it owns is unknown',
            current_database();
    END IF;

    -- `public` rides along with every extracted database to carry extensions,
    -- enum types and the migration metadata. It is shared infrastructure, not a
    -- bounded context, so no ownership claim is made about it.
    SELECT array_agg(candidate_schema)
    INTO service_schemas
    FROM unnest(owned_schemas) AS candidate_schema
    WHERE candidate_schema <> 'public';

    IF service_schemas IS NULL THEN
        RAISE EXCEPTION 'database % claims no service schema', current_database();
    END IF;

    -- 1. The schemas the marker claims are really here.
    FOR offender IN
        SELECT missing_schema
        FROM unnest(service_schemas) AS missing_schema
        WHERE to_regnamespace(missing_schema) IS NULL
    LOOP
        problems := problems || format('owned schema %I is missing', offender.missing_schema);
    END LOOP;

    IF array_length(problems, 1) > 0 THEN
        RAISE EXCEPTION E'database boundary contract failed in %:\n  - %',
            current_database(), array_to_string(problems, E'\n  - ');
    END IF;

    -- 2. The owning runtime role can actually use its own schemas. Each
    -- privilege is asked for separately on purpose: has_table_privilege with a
    -- comma-separated list answers "any of these", not "all of these", so the
    -- single-call form silently accepts a role that can only SELECT.
    FOR offender IN
        SELECT unusable_schema
        FROM unnest(service_schemas) AS unusable_schema
        WHERE NOT has_schema_privilege(runtime_role, unusable_schema, 'USAGE')
    LOOP
        problems := problems || format(
            '%I cannot USE its own schema %I', runtime_role, offender.unusable_schema);
    END LOOP;

    FOR offender IN
        SELECT owned_schema.nspname AS schema_name, owned_table.relname AS table_name
        FROM pg_class AS owned_table
        JOIN pg_namespace AS owned_schema
            ON owned_schema.oid = owned_table.relnamespace
        WHERE owned_schema.nspname = ANY(service_schemas)
          AND owned_table.relkind IN ('r', 'p')
          AND NOT (
              has_table_privilege(runtime_role, owned_table.oid, 'SELECT')
              AND has_table_privilege(runtime_role, owned_table.oid, 'INSERT')
              AND has_table_privilege(runtime_role, owned_table.oid, 'UPDATE')
              AND has_table_privilege(runtime_role, owned_table.oid, 'DELETE')
          )
    LOOP
        problems := problems || format(
            '%I is missing DML on its own table %I.%I',
            runtime_role, offender.schema_name, offender.table_name);
    END LOOP;

    -- 3. Nobody else's runtime role reaches into this database. Cross-database
    -- access is impossible, but roles are cluster-wide, so a grant made here to
    -- a sibling service is invisible from that service's own database.
    -- Roles are joined from pg_roles and probed by OID rather than by name.
    -- has_schema_privilege() raises on a role that does not exist, and a WHERE
    -- clause is not evaluated left to right, so an EXISTS guard beside the call
    -- does not protect it: a deployment missing one service's role would fail
    -- here with `role does not exist` instead of reporting the boundary.
    FOR offender IN
        SELECT intruder.rolname AS foreign_role, intruded_schema
        FROM pg_roles AS intruder
        CROSS JOIN unnest(service_schemas) AS intruded_schema
        WHERE intruder.rolname = ANY(all_roles)
          AND intruder.rolname <> runtime_role
          AND has_schema_privilege(intruder.oid, intruded_schema, 'USAGE')
    LOOP
        problems := problems || format(
            '%I holds USAGE on %I, which belongs to %I',
            offender.foreign_role, offender.intruded_schema, runtime_role);
    END LOOP;

    FOR offender IN
        SELECT intruder.rolname AS foreign_role,
               intruded_schema.nspname AS schema_name,
               intruded_table.relname AS table_name
        FROM pg_roles AS intruder
        CROSS JOIN pg_class AS intruded_table
        JOIN pg_namespace AS intruded_schema
            ON intruded_schema.oid = intruded_table.relnamespace
        WHERE intruder.rolname = ANY(all_roles)
          AND intruder.rolname <> runtime_role
          AND intruded_schema.nspname = ANY(service_schemas)
          AND intruded_table.relkind IN ('r', 'p', 'v', 'm', 'f')
          AND (
              has_table_privilege(intruder.oid, intruded_table.oid, 'SELECT')
              OR has_table_privilege(intruder.oid, intruded_table.oid, 'INSERT')
              OR has_table_privilege(intruder.oid, intruded_table.oid, 'UPDATE')
              OR has_table_privilege(intruder.oid, intruded_table.oid, 'DELETE')
          )
    LOOP
        problems := problems || format(
            '%I can reach %I.%I, which belongs to %I',
            offender.foreign_role, offender.schema_name,
            offender.table_name, runtime_role);
    END LOOP;

    -- 4. Only the owning login may connect. This is the check that replaced
    -- same-database schema isolation: after the extraction it is what keeps one
    -- service out of another's data. warptalk_monitor is exempt — metrics
    -- collection is not a bounded context, and pg_monitor grants it no table
    -- data. Superusers are exempt because CONNECT cannot be withheld from them.
    IF has_database_privilege('public', current_database(), 'CONNECT') THEN
        problems := problems || format(
            'PUBLIC may CONNECT to %I', current_database());
    END IF;

    FOR offender IN
        SELECT rolname AS foreign_login
        FROM pg_roles
        WHERE rolname = ANY(all_logins)
          AND rolname <> login_role
          AND has_database_privilege(oid, current_database(), 'CONNECT')
    LOOP
        problems := problems || format(
            '%I may CONNECT to %I, which belongs to %I',
            offender.foreign_login, current_database(), login_role);
    END LOOP;

    -- Anything else that can log in and connect here is an operator account,
    -- not a service: production carries warptalk_tablepro_admin, a human's
    -- database-client login holding warptalk_migrator. Those are deliberate, so
    -- they are reported rather than failed — this contract exists to stop one
    -- SERVICE reaching another's data, and refusing to deploy until a DBA gives
    -- up their client would be the check overreaching its subject. Reported and
    -- not silent, so an account nobody remembers creating still shows up in the
    -- deploy log. Superusers are omitted: CONNECT cannot be withheld from them,
    -- so naming them would be noise every single run.
    FOR offender IN
        SELECT rolname AS operator_login
        FROM pg_roles
        WHERE rolcanlogin
          AND NOT rolsuper
          AND NOT (rolname = ANY(all_logins))
          AND rolname <> 'warptalk_monitor'
          AND has_database_privilege(oid, current_database(), 'CONNECT')
    LOOP
        RAISE NOTICE '  % : operator login % may connect (not a service role)',
            current_database(), offender.operator_login;
    END LOOP;

    -- 5. Nothing inside the database crosses a bounded context. Both of these
    -- survive from the monolith-era contract unchanged, because a database that
    -- owns two schemas — auth owns `auth` and `voice` — can still violate them.
    IF EXISTS (
        SELECT 1
        FROM pg_constraint constraint_definition
        JOIN pg_class source_table
            ON source_table.oid = constraint_definition.conrelid
        JOIN pg_namespace source_schema
            ON source_schema.oid = source_table.relnamespace
        JOIN pg_class target_table
            ON target_table.oid = constraint_definition.confrelid
        JOIN pg_namespace target_schema
            ON target_schema.oid = target_table.relnamespace
        WHERE constraint_definition.contype = 'f'
          AND source_schema.nspname <> target_schema.nspname
          AND source_schema.nspname = ANY(service_schemas)
          AND target_schema.nspname = ANY(service_schemas)
    ) THEN
        problems := problems || 'cross-schema foreign keys violate service database boundaries';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_views view_definition
        WHERE view_definition.schemaname = ANY(service_schemas)
          AND EXISTS (
              SELECT 1
              FROM regexp_matches(
                  view_definition.definition,
                  '\m(' || array_to_string(service_schemas, '|') || ')\.',
                  'g'
              ) AS referenced_schema(schema_match)
              WHERE referenced_schema.schema_match[1]
                  <> view_definition.schemaname
          )
    ) THEN
        problems := problems || 'cross-schema views violate service database boundaries';
    END IF;

    IF array_length(problems, 1) > 0 THEN
        RAISE EXCEPTION E'database boundary contract failed in %:\n  - %',
            current_database(), array_to_string(problems, E'\n  - ');
    END IF;

    RAISE NOTICE '  % (%): PASS',
        current_database(), array_to_string(service_schemas, ', ');
END
$$;
SQL

  checked=$((checked + 1))
done < "$service_list"

echo "database boundary contract: PASS ($checked checked, $skipped not extracted yet)"
