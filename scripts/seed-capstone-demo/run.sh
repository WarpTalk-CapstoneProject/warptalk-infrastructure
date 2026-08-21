#!/usr/bin/env bash
#
# WarpTalk capstone demo seed — runner
#
# Applies all five parts, each against its own logical database. Production
# completed the per-service database cutover, so auth.* and workspace.* cannot
# be written in one transaction and there is no single database to target.
#
#   ./run.sh --dry-run     rewrite COMMIT to ROLLBACK; exercises every
#                          statement against the real schema and writes nothing
#   ./run.sh --apply       for real
#
# Postgres lives on the Data host in warptalk-postgres-1, reachable through the
# App jump host; ~/.ssh/config already has the warptalk-data alias.
#
# PGCLIENTENCODING=UTF8 matters — the seed carries Vietnamese and Japanese text.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_HOST="${WARPTALK_DATA_HOST:-warptalk-data}"
CONTAINER="${WARPTALK_PG_CONTAINER:-warptalk-postgres-1}"

MODE=""
case "${1:-}" in
    --dry-run) MODE="dry-run" ;;
    --apply)   MODE="apply" ;;
    *)
        echo "usage: $0 --dry-run | --apply" >&2
        exit 2
        ;;
esac

# part file -> target database
PARTS=(
    "01-auth.sql:warptalk_auth"
    "02-workspace.sql:warptalk_workspace"
    "03-billing.sql:warptalk_billing"
    "04-transcript.sql:warptalk_transcript"
    "05-translation-room.sql:warptalk_translation_room"
)

echo "=== WarpTalk capstone demo seed — ${MODE} ==="
echo "host=${SSH_HOST} container=${CONTAINER}"
echo

# A release deploy recreates warptalk-postgres-1. Seeding into a container that
# is being torn down half-applies the seed across five databases with no
# transaction spanning them, so refuse to start while one is in flight.
#
# The bracket in '[d]eploy' keeps the pattern from matching the ssh command
# line that carries it — without it this check reports a deploy every time.
if ssh "${SSH_HOST}" 'pgrep -f "[d]eploy-release\.sh" >/dev/null 2>&1'; then
    echo "REFUSING: a release deploy is running on ${SSH_HOST}. Wait for it to finish." >&2
    exit 1
fi

# $POSTGRES_USER must be expanded by the shell INSIDE the container, not by
# this shell and not by the remote one — hence `sh -c` with the dollar escaped
# all the way through. Expanding it any earlier yields an empty user and psql
# falls back to the login name ("role \"root\" does not exist").
if ! ssh "${SSH_HOST}" \
     "docker exec ${CONTAINER} sh -c 'pg_isready -U \"\$POSTGRES_USER\"'" >/dev/null 2>&1; then
    echo "REFUSING: ${CONTAINER} is not accepting connections." >&2
    exit 1
fi

for entry in "${PARTS[@]}"; do
    file="${entry%%:*}"
    db="${entry##*:}"
    echo "--- ${file}  ->  ${db}"

    if [[ "${MODE}" == "dry-run" ]]; then
        # Rewriting the commit exercises the whole script against the real
        # schema without leaving anything behind.
        sed 's/^COMMIT;$/ROLLBACK;/' "${SCRIPT_DIR}/${file}"
    else
        cat "${SCRIPT_DIR}/${file}"
    fi | ssh "${SSH_HOST}" \
        "docker exec -i -e PGCLIENTENCODING=UTF8 ${CONTAINER} \
         psql -U \"\${POSTGRES_USER}\" -d ${db} -v ON_ERROR_STOP=1"

    echo
done

echo "=== ${MODE} finished ==="
if [[ "${MODE}" == "apply" ]]; then
    echo
    echo "NOT DONE YET — the entitlement snapshot is still missing."
    echo "Run step 6 in README.md (save Workspace Settings through the API) so"
    echo "billing publishes billing.entitlements_changed. Until then the"
    echo "workspace has no snapshot at all."
fi
