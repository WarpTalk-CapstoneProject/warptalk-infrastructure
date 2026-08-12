#!/bin/sh
# Exercise check-database-boundaries.sh against a real PostgreSQL cluster.
#
# WHY THIS TEST EXISTS
#   The check it covers runs inside the migrator, second of five steps, before
#   any service is updated. When it is wrong the deploy stops — that is how
#   release v55 died on `schema "subscription" does not exist`, a check whose
#   assumptions had outlived the schema layout it was written against. A static
#   grep contract cannot catch that class of mistake: the SQL was well-formed
#   and the file looked right. Only running it against a cluster shaped like the
#   real one does.
#
#   So this builds two miniature logical databases with the same grants
#   extract-logical-databases.sh establishes, asserts the check passes, then
#   injects each violation the check claims to catch and asserts it fails on
#   that violation and names it. A check that cannot fail is not a check.
set -eu

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
export PGPASSWORD

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
check="$script_dir/check-database-boundaries.sh"

auth_db="warptalk_boundary_auth_test_$$"
billing_db="warptalk_boundary_billing_test_$$"
# Not one of the service logins, so the check must treat it as an operator
# account: reported, not fatal.
operator_role="warptalk_boundary_operator_test_$$"
for candidate in "$auth_db" "$billing_db"; do
  case "$candidate" in
    warptalk_boundary_*_test_[0-9]*) ;;
    *) echo "Unsafe test database name: $candidate" >&2; exit 1 ;;
  esac
done

admin() {
  psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" \
    -d "${PGDATABASE:-postgres}" "$@"
}

in_db() {
  target="$1"
  shift
  psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$target" "$@"
}

cleanup() {
  admin -c "DROP DATABASE IF EXISTS \"$auth_db\" WITH (FORCE);" >/dev/null 2>&1 || true
  admin -c "DROP DATABASE IF EXISTS \"$billing_db\" WITH (FORCE);" >/dev/null 2>&1 || true
  # Safe to drop, unlike the service roles: this one is created by this test and
  # carries the pid in its name.
  admin -c "DROP ROLE IF EXISTS \"$operator_role\";" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

# Roles are cluster-wide and the real deployment already owns these names, so
# create them only when absent and never drop them: a developer pointing this at
# a scratch cluster that also holds real roles must not have them removed.
admin >/dev/null <<'SQL'
SELECT format('CREATE ROLE %I NOLOGIN', missing_role)
FROM unnest(ARRAY['warptalk_auth_runtime', 'warptalk_billing_runtime']) AS missing_role
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = missing_role)
\gexec

SELECT format('CREATE ROLE %I LOGIN INHERIT', missing_role)
FROM unnest(ARRAY['warptalk_auth', 'warptalk_billing']) AS missing_role
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = missing_role)
\gexec

GRANT warptalk_auth_runtime TO warptalk_auth;
GRANT warptalk_billing_runtime TO warptalk_billing;
SQL

admin -c "CREATE ROLE \"$operator_role\" LOGIN;" >/dev/null

# Two databases shaped exactly as extract-logical-databases.sh leaves them,
# including auth's second owned schema — `voice` is why the in-database
# cross-schema checks still have something to protect after the extraction.
# $schemas is a space-separated list and is meant to split into one word per
# schema, in the loop and in every grant below.
# shellcheck disable=SC2086
seed_database() {
  target="$1"
  schemas="$2"
  login="$3"
  runtime_role="$4"

  admin -c "CREATE DATABASE \"$target\";" >/dev/null
  for schema in $schemas; do
    in_db "$target" -c "CREATE SCHEMA $schema;" >/dev/null
    in_db "$target" -c "CREATE TABLE $schema.probe (id integer PRIMARY KEY);" >/dev/null
  done
  in_db "$target" <<SQL >/dev/null
REVOKE CONNECT ON DATABASE "$target" FROM PUBLIC;
GRANT CONNECT ON DATABASE "$target" TO "$login";
GRANT USAGE ON SCHEMA $(printf '%s,' $schemas | sed 's/,$//') TO "$runtime_role";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA $(
    printf '%s,' $schemas | sed 's/,$//'
) TO "$runtime_role";
CREATE TABLE public.logical_database_extract (
    source_database TEXT NOT NULL,
    owned_schemas TEXT[] NOT NULL,
    extracted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO public.logical_database_extract (source_database, owned_schemas)
VALUES ('warptalk', ARRAY[$(printf "'%s'," public $schemas | sed "s/,$//")]);
SQL
}

run_check() {
  AUTH_DATABASE="$auth_db" BILLING_DATABASE="$billing_db" "$check"
}

# A violation must fail the check AND say which one it was. A check that fails
# for the wrong reason passes this test while telling an operator nothing.
expect_failure() {
  description="$1"
  expected="$2"
  output="$(run_check 2>&1)" && {
    echo "FAIL: $description did not fail the boundary check" >&2
    exit 1
  }
  case "$output" in
    *"$expected"*) echo "  caught: $description" ;;
    *)
      echo "FAIL: $description failed for the wrong reason." >&2
      echo "  expected text: $expected" >&2
      printf '  actual:\n%s\n' "$output" >&2
      exit 1
      ;;
  esac
}

seed_database "$auth_db" "auth voice" warptalk_auth warptalk_auth_runtime
seed_database "$billing_db" "subscription" warptalk_billing warptalk_billing_runtime

run_check >/dev/null
echo "  clean cluster passes"

# 1. A sibling service granted USAGE on a schema it does not own. This is the
#    monolith-era mistake that survives the extraction, because roles do.
in_db "$auth_db" -c "GRANT USAGE ON SCHEMA auth TO warptalk_billing_runtime;" >/dev/null
expect_failure "foreign runtime role holding schema USAGE" \
  "warptalk_billing_runtime holds USAGE on auth"
in_db "$auth_db" -c "REVOKE USAGE ON SCHEMA auth FROM warptalk_billing_runtime;" >/dev/null

# 2. Table-level reach without schema USAGE. USAGE alone is not the whole story:
#    a GRANT on the table is what actually exposes rows once USAGE is restored.
in_db "$auth_db" -c "GRANT SELECT ON auth.probe TO warptalk_billing_runtime;" >/dev/null
expect_failure "foreign runtime role holding table privileges" \
  "warptalk_billing_runtime can reach auth.probe"
in_db "$auth_db" -c "REVOKE SELECT ON auth.probe FROM warptalk_billing_runtime;" >/dev/null

# 3. A foreign login able to connect. After the extraction this is the boundary:
#    if it can connect it can be granted anything later, in a database its own
#    service never looks at.
in_db "$auth_db" -c "GRANT CONNECT ON DATABASE \"$auth_db\" TO warptalk_billing;" >/dev/null
expect_failure "foreign login holding CONNECT" \
  "warptalk_billing may CONNECT"
in_db "$auth_db" -c "REVOKE CONNECT ON DATABASE \"$auth_db\" FROM warptalk_billing;" >/dev/null

# 3b. An operator login — a human's database client, not a service — is reported
#     and allowed. Production runs one of these (warptalk_tablepro_admin), and
#     failing the deploy over it would stop releases for a reason outside what
#     this contract is about.
in_db "$auth_db" -c "GRANT CONNECT ON DATABASE \"$auth_db\" TO \"$operator_role\";" >/dev/null
operator_output="$(run_check 2>&1)"
case "$operator_output" in
  *"operator login $operator_role may connect"*) echo "  reported: operator login" ;;
  *)
    echo "FAIL: an operator login was not reported." >&2
    printf '  actual:\n%s\n' "$operator_output" >&2
    exit 1
    ;;
esac
in_db "$auth_db" -c "REVOKE CONNECT ON DATABASE \"$auth_db\" FROM \"$operator_role\";" >/dev/null

# 4. PUBLIC able to connect — the default state of a freshly created database,
#    and therefore the one most likely to come back by accident.
in_db "$billing_db" -c "GRANT CONNECT ON DATABASE \"$billing_db\" TO PUBLIC;" >/dev/null
expect_failure "PUBLIC holding CONNECT" "PUBLIC may CONNECT"
in_db "$billing_db" -c "REVOKE CONNECT ON DATABASE \"$billing_db\" FROM PUBLIC;" >/dev/null

# 5. The owner losing part of its own DML. Asked for one privilege at a time on
#    purpose: has_table_privilege with a comma-separated list means "any of",
#    so the compact form would accept a role left with SELECT alone.
in_db "$billing_db" -c "REVOKE DELETE ON subscription.probe FROM warptalk_billing_runtime;" >/dev/null
expect_failure "owner missing DML on its own table" \
  "warptalk_billing_runtime is missing DML on its own table subscription.probe"
in_db "$billing_db" -c "GRANT DELETE ON subscription.probe TO warptalk_billing_runtime;" >/dev/null

# 6. A foreign key across two owned schemas inside one database. auth owning
#    both `auth` and `voice` is the reason this check still has work to do.
in_db "$auth_db" <<'SQL' >/dev/null
CREATE TABLE voice.crosses (
    id integer PRIMARY KEY,
    auth_probe_id integer NOT NULL REFERENCES auth.probe(id)
);
SQL
expect_failure "cross-schema foreign key" "cross-schema foreign keys violate"
in_db "$auth_db" -c "DROP TABLE voice.crosses;" >/dev/null

# 7. A view in one owned schema selecting from another.
in_db "$auth_db" -c "CREATE VIEW voice.crosses AS SELECT id FROM auth.probe;" >/dev/null
expect_failure "cross-schema view" "cross-schema views violate"
in_db "$auth_db" -c "DROP VIEW voice.crosses;" >/dev/null

# 8. A database with no extraction marker. Silence here would mean the check
#    quietly asserts nothing about a database nobody can describe.
in_db "$billing_db" -c "DROP TABLE public.logical_database_extract;" >/dev/null
expect_failure "database without an extraction marker" \
  "has no logical_database_extract marker"

# 9. A database that does not exist yet is skipped, not failed: the migrator
#    runs this check before extract-logical-databases.sh, so a first deploy
#    reaches it with nothing extracted.
admin -c "DROP DATABASE \"$billing_db\" WITH (FORCE);" >/dev/null
skip_output="$(run_check)"
case "$skip_output" in
  *"$billing_db: not extracted yet, skipping."*) echo "  unextracted database is skipped" ;;
  *)
    echo "FAIL: a database that does not exist was not reported as skipped." >&2
    printf '  actual:\n%s\n' "$skip_output" >&2
    exit 1
    ;;
esac

echo "database boundary isolation contract passed"
