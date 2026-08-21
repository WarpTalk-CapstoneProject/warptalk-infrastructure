#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
LOCAL_COMPOSE="$ROOT_DIR/docker-compose.yml"
LOCAL_ENV_FILE="$ROOT_DIR/.env.example"
DEPLOY_DIR="$ROOT_DIR/deploy/production"
ENV_FILE="$DEPLOY_DIR/.env.example"
DATA_COMPOSE="$DEPLOY_DIR/data.compose.yml"
INFRA_COMPOSE="$DEPLOY_DIR/infra.compose.yml"
APP_COMPOSE="$DEPLOY_DIR/app.compose.yml"
SINGLE_HOST_COMPOSE="$DEPLOY_DIR/single-host.compose.yml"
SINGLE_HOST_INVENTORY="$DEPLOY_DIR/inventory/single-host.env.example"
SPLIT_HOST_INVENTORY="$DEPLOY_DIR/inventory/split-host.env.example"
HOST_BOOTSTRAP="$ROOT_DIR/scripts/bootstrap-production-host.sh"
MIGRATION_RUNNER="$ROOT_DIR/scripts/run-migrations.sh"
IMAGE_MATRIX="$DEPLOY_DIR/image-matrix.json"
BACKEND_DIR="$ROOT_DIR/../warptalk-backend"
OUTBOX_MIGRATION="$ROOT_DIR/scripts/migrations/029-27-07-2026-add-billing-outbox-inbox.sql"
NOTIFICATION_MESSAGES_MIGRATION="$ROOT_DIR/scripts/migrations/004-01-05-2026-add-notification-message-table.sql"
ADMIN_NOTIFICATIONS_MIGRATION="$ROOT_DIR/scripts/migrations/005-09-05-2026-add-admin-notifications-table.sql"
TRANSLATION_AUDIO_RENAME_MIGRATION="$ROOT_DIR/scripts/migrations/006-15-05-2026-rename-participant-is-translation-audio-enabled.sql"
ACTIVE_SUBSCRIPTION_MIGRATION="$ROOT_DIR/scripts/migrations/016-03-07-2026-enforce-single-active-subscription.sql"
DEAD_LETTER_MIGRATION="$ROOT_DIR/scripts/migrations/030-27-07-2026-add-billing-outbox-dead-letter.sql"
NOTIFICATION_INBOX_MIGRATION="$ROOT_DIR/scripts/migrations/031-27-07-2026-add-notification-inbox.sql"
BILLING_RUNTIME_ROLE_MIGRATION="$ROOT_DIR/scripts/migrations/032-27-07-2026-add-billing-runtime-role.sql"
WORKSPACE_RUNTIME_ROLE_MIGRATION="$ROOT_DIR/scripts/migrations/033-27-07-2026-add-workspace-runtime-role.sql"
NOTIFICATION_RUNTIME_ROLE_MIGRATION="$ROOT_DIR/scripts/migrations/034-27-07-2026-add-notification-runtime-role.sql"
AUTH_RUNTIME_ROLE_MIGRATION="$ROOT_DIR/scripts/migrations/035-27-07-2026-add-auth-runtime-role.sql"
TRANSLATION_REFERENCE_MIGRATION="$ROOT_DIR/scripts/migrations/036-27-07-2026-localize-translation-room-reference-data.sql"
TRANSLATION_RUNTIME_ROLE_MIGRATION="$ROOT_DIR/scripts/migrations/037-27-07-2026-add-translation-room-runtime-role.sql"
TRANSCRIPT_RUNTIME_ROLE_MIGRATION="$ROOT_DIR/scripts/migrations/038-27-07-2026-add-transcript-runtime-role.sql"
MEETING_RUNTIME_ROLE_MIGRATION="$ROOT_DIR/scripts/migrations/039-27-07-2026-add-meeting-runtime-role.sql"
ASSISTANT_RUNTIME_ROLE_MIGRATION="$ROOT_DIR/scripts/migrations/040-27-07-2026-add-assistant-runtime-role.sql"
WORKSPACE_OUTBOX_MIGRATION="$ROOT_DIR/scripts/migrations/042-28-07-2026-add-workspace-outbox.sql"
CROSS_SERVICE_FK_MIGRATION="$ROOT_DIR/scripts/migrations/043-30-07-2026-drop-cross-service-workspace-foreign-keys.sql"
WORKSPACE_SERVICE_OUTBOX_MIGRATION="$ROOT_DIR/../warptalk-backend/workspace/database/migrations/20260728142000_add_workspace_outbox.sql"
SERVICE_DB_USER_PROVISIONER="$ROOT_DIR/scripts/provision-service-db-users.sh"
DATABASE_BOUNDARY_CHECK="$ROOT_DIR/scripts/check-database-boundaries.sh"
LOGICAL_DATABASE_EXTRACTOR="$ROOT_DIR/scripts/extract-logical-databases.sh"
LOGICAL_DATABASE_CHECK="$ROOT_DIR/scripts/check-logical-databases.sh"
LOGICAL_DATABASE_BACKUP="$ROOT_DIR/scripts/backup-logical-databases.sh"
SOURCE_READONLY_WINDOW="$ROOT_DIR/scripts/enter-source-readonly-window.sh"
LOGICAL_MIGRATION_RUNNER="$ROOT_DIR/scripts/run-logical-database-migrations.sh"
COST_RENDERER="$ROOT_DIR/scripts/render-cost-observability.sh"
BILLING_COST_TEMPLATE="$ROOT_DIR/observability/billing-cost-queries.yml.example"
LIVEKIT_COST_TEMPLATE="$ROOT_DIR/observability/livekit-cost-queries.yml.example"
WORKSPACE_STORAGE_TEMPLATE="$ROOT_DIR/observability/workspace-storage-queries.yml.example"
COST_RULES_TEMPLATE="$ROOT_DIR/observability/alerts/warptalk.cost.rules.yml.example"
COST_GOVERNANCE="$ROOT_DIR/observability/COST-GOVERNANCE.md"
LOCAL_PROMETHEUS_CONFIG="$ROOT_DIR/observability/prometheus.yml"
LOCAL_ALERT_RULES="$ROOT_DIR/observability/alerts/warptalk.rules.yml"
LOCAL_ALERTMANAGER_CONFIG="$ROOT_DIR/observability/alertmanager.local.yml"
LOCAL_GRAFANA_PROVISIONING="$ROOT_DIR/observability/grafana/provisioning"
LOCAL_GRAFANA_DASHBOARDS="$ROOT_DIR/observability/grafana/dashboards"
LEGACY_PRODUCTION_COMPOSE="$ROOT_DIR/docker-compose.prod.yml"
LOCAL_STARTER="$ROOT_DIR/scripts/start-all.sh"
DEPENDENCY_READINESS_DRILL="$ROOT_DIR/scripts/drill-dependency-readiness.sh"

fail() {
  echo "production deployment contract: $*" >&2
  exit 1
}

# Reads C# on stdin and writes it back with comments removed.
#
# Source-text contracts below must judge code, not prose. A plain grep also
# matches inside doc comments, so a comment that merely explains the arrangement
# the contract permits reddens CI: that is exactly what happened to
# LanguageRepository.cs, whose comment named the platform-owned table while
# describing the local view over it, and the backend ended up rewording prose
# (891bfc8) to get past the grep instead of changing any behaviour.
#
# Deliberately fail-closed. String literals are preserved byte for byte -- plain
# "...", interpolated $"...", verbatim @"..." with its "" escape, and char
# literals -- so SQL carried in a string is still scanned, and a "//" appearing
# inside a string never starts a comment. Only /* */ and // are removed.
# Block-comment and verbatim-string state carry across lines; awk is invoked
# once per file, so the state cannot leak between files.
strip_cs_comments() {
  awk '
    BEGIN { apostrophe = sprintf("%c", 39) }
    {
      line = $0
      out = ""
      i = 1
      n = length(line)
      while (i <= n) {
        c = substr(line, i, 1)
        c2 = substr(line, i, 2)
        if (in_block) {
          if (c2 == "*/") { in_block = 0; i += 2 } else { i += 1 }
          continue
        }
        if (in_string == 1) {
          if (c == "\\") { out = out c substr(line, i + 1, 1); i += 2; continue }
          if (c == "\"") { in_string = 0 }
          out = out c; i += 1; continue
        }
        if (in_string == 2) {
          if (c2 == "\"\"") { out = out c2; i += 2; continue }
          if (c == "\"") { in_string = 0 }
          out = out c; i += 1; continue
        }
        if (in_string == 3) {
          if (c == "\\") { out = out c substr(line, i + 1, 1); i += 2; continue }
          if (c == apostrophe) { in_string = 0 }
          out = out c; i += 1; continue
        }
        if (c2 == "//") { break }
        if (c2 == "/*") { in_block = 1; i += 2; continue }
        if (c2 == "@\"") { in_string = 2; out = out c2; i += 2; continue }
        if (c == "\"") { in_string = 1; out = out c; i += 1; continue }
        if (c == apostrophe) { in_string = 3; out = out c; i += 1; continue }
        out = out c; i += 1
      }
      # Only a verbatim string may legally continue onto the next line.
      if (in_string != 2) { in_string = 0 }
      print out
    }
  '
}

# scan_cs_source <directory> <grep arguments...>
# Prints "file:line:code" for every match found in comment-stripped source.
# Blank lines replace stripped comments, so the reported line numbers are the
# real ones.
scan_cs_source() {
  scan_dir="$1"
  shift
  find "$scan_dir" -name '*.cs' -type f -print |
    while IFS= read -r cs_file; do
      strip_cs_comments <"$cs_file" |
        grep -n "$@" |
        sed "s#^#$cs_file:#"
    done
}

for dependency in docker jq; do
  command -v "$dependency" >/dev/null 2>&1 || fail "missing dependency: $dependency"
done

for required_file in "$LOCAL_COMPOSE" "$LOCAL_ENV_FILE" "$ENV_FILE" "$DATA_COMPOSE" "$INFRA_COMPOSE" "$APP_COMPOSE" "$SINGLE_HOST_COMPOSE" "$SINGLE_HOST_INVENTORY" "$SPLIT_HOST_INVENTORY" "$HOST_BOOTSTRAP" "$IMAGE_MATRIX" "$NOTIFICATION_MESSAGES_MIGRATION" "$ADMIN_NOTIFICATIONS_MIGRATION" "$TRANSLATION_AUDIO_RENAME_MIGRATION" "$ACTIVE_SUBSCRIPTION_MIGRATION" "$OUTBOX_MIGRATION" "$DEAD_LETTER_MIGRATION" "$NOTIFICATION_INBOX_MIGRATION" "$BILLING_RUNTIME_ROLE_MIGRATION" "$WORKSPACE_RUNTIME_ROLE_MIGRATION" "$NOTIFICATION_RUNTIME_ROLE_MIGRATION" "$AUTH_RUNTIME_ROLE_MIGRATION" "$TRANSLATION_REFERENCE_MIGRATION" "$TRANSLATION_RUNTIME_ROLE_MIGRATION" "$TRANSCRIPT_RUNTIME_ROLE_MIGRATION" "$MEETING_RUNTIME_ROLE_MIGRATION" "$ASSISTANT_RUNTIME_ROLE_MIGRATION" "$WORKSPACE_OUTBOX_MIGRATION" "$CROSS_SERVICE_FK_MIGRATION" "$SERVICE_DB_USER_PROVISIONER" "$DATABASE_BOUNDARY_CHECK" "$LOGICAL_DATABASE_EXTRACTOR" "$LOGICAL_DATABASE_CHECK" "$LOGICAL_DATABASE_BACKUP" "$SOURCE_READONLY_WINDOW" "$LOGICAL_MIGRATION_RUNNER" "$COST_RENDERER" "$BILLING_COST_TEMPLATE" "$LIVEKIT_COST_TEMPLATE" "$WORKSPACE_STORAGE_TEMPLATE" "$COST_RULES_TEMPLATE" "$COST_GOVERNANCE" "$LOCAL_PROMETHEUS_CONFIG" "$LOCAL_ALERT_RULES" "$LOCAL_ALERTMANAGER_CONFIG" "$DEPENDENCY_READINESS_DRILL"; do
  [ -f "$required_file" ] || fail "missing file: $required_file"
done
for required_directory in "$LOCAL_GRAFANA_PROVISIONING" "$LOCAL_GRAFANA_DASHBOARDS"; do
  [ -d "$required_directory" ] || fail "missing directory: $required_directory"
done

[ ! -e "$LEGACY_PRODUCTION_COMPOSE" ] ||
  fail "legacy docker-compose.prod.yml must not coexist with canonical production manifests"
grep -q 'exec "$INFRA_DIR/scripts/deploy-release.sh"' "$LOCAL_STARTER" ||
  fail "start-all --prod must delegate to the immutable release deployer"
grep -q 'Stripe__SecretKey: ${STRIPE_SECRET_KEY:-}' "$ROOT_DIR/docker-compose.yml" ||
  fail "local Billing Compose must accept Stripe Sandbox configuration"
if grep -E '^[[:space:]]+image:' "$LOCAL_COMPOSE" |
  grep -Ev '@sha256:[0-9a-f]{64}([[:space:]#]|$)'; then
  fail "every third-party local runtime image must be pinned by digest"
fi
grep -q 'CONFIRM_DEPENDENCY_DRILL' "$DEPENDENCY_READINESS_DRILL" ||
  fail "dependency readiness drill must require an explicit destructive-test confirmation"
grep -q 'trap restore_dependency EXIT INT TERM' "$DEPENDENCY_READINESS_DRILL" ||
  fail "dependency readiness drill must restore the stopped dependency on exit"

jq -e '
  .schemaVersion == 1
  and .platform == "linux/amd64"
  and ([.images[].name] | length == 22)
  and ([.images[].name] | unique | length == 22)
  and (all(.images[]; (.context | length) > 0 and (.dockerfile | length) > 0))
' "$IMAGE_MATRIX" >/dev/null || fail "image matrix must define 22 unique linux/amd64 release images"

MATRIX_NAMES="$(jq -r '.images[] | select(.compose != false) | .name' "$IMAGE_MATRIX" | sort)"
IMAGE_REGISTRY_VALUE="$(
  sed -n 's/^IMAGE_REGISTRY=//p' "$ENV_FILE" |
    tail -n 1
)"
[ -n "$IMAGE_REGISTRY_VALUE" ] ||
  fail "IMAGE_REGISTRY is missing from the production environment file"
compose_images_file="$(mktemp)"
{
  docker compose --env-file "$ENV_FILE" -f "$APP_COMPOSE" config --images
  docker compose --env-file "$ENV_FILE" -f "$DATA_COMPOSE" config --images
  docker compose --env-file "$ENV_FILE" -f "$INFRA_COMPOSE" config --images
} |
  while IFS= read -r image_ref; do
    # Every internal Warptalk image in Compose must be represented in the
    # release matrix; third-party platform images are pinned separately.
    case "$image_ref" in
      "$IMAGE_REGISTRY_VALUE"/*)
        image_name="${image_ref#"$IMAGE_REGISTRY_VALUE"/}"
        image_name="${image_name%%:*}"
        image_name="${image_name%%@*}"
        printf '%s\n' "$image_name"
        ;;
    esac
  done >"$compose_images_file"
COMPOSE_IMAGE_NAMES="$(sort -u "$compose_images_file")"
rm -f "$compose_images_file"
[ "$MATRIX_NAMES" = "$COMPOSE_IMAGE_NAMES" ] ||
  fail "production Compose image references must exactly match image-matrix.json"

# EVERY SERVICE, not just every image NAME.
#
# The comparison above deduplicates: two services running one image satisfy it with a single
# matrix entry, and the second service is then never pinned. release-override.jq rewrites images
# per SERVICE, so an unpinned one falls through to ${IMAGE_REGISTRY}/${IMAGE_TAG} — a pair no
# release rewrites, still holding July's values on production. It pulls a tag that no longer
# exists, 403s, and takes the whole deploy down with it after every other image is already
# fetched.
#
# That is v144: translation-backfill-worker was added to the Compose file and not to the matrix,
# and the check above passed because the image it runs was already listed for another service.
matrix_services_file="$(mktemp)"
jq -r '.images[] | select(.compose != false) | ([.service] + (.alsoServices // []))[]' \
  "$IMAGE_MATRIX" | sort -u >"$matrix_services_file"

compose_services_file="$(mktemp)"
{
  docker compose --env-file "$ENV_FILE" -f "$APP_COMPOSE" config --format json
  docker compose --env-file "$ENV_FILE" -f "$DATA_COMPOSE" config --format json
  docker compose --env-file "$ENV_FILE" -f "$INFRA_COMPOSE" config --format json
} |
  jq -r --arg registry "$IMAGE_REGISTRY_VALUE" '
    .services | to_entries[]
    | select((.value.image // "") | startswith($registry + "/"))
    | .key
  ' | sort -u >"$compose_services_file"

unpinned="$(comm -13 "$matrix_services_file" "$compose_services_file")"
rm -f "$matrix_services_file" "$compose_services_file"
[ -z "$unpinned" ] ||
  fail "these Compose services run a WarpTalk image and are absent from image-matrix.json, so no release would pin them: $(printf '%s' "$unpinned" | tr '\n' ' ')"

grep -q 'ON_ERROR_STOP' "$MIGRATION_RUNNER" ||
  fail "migration runner must stop on the first SQL error"
grep -q 'pg_advisory_lock' "$MIGRATION_RUNNER" ||
  fail "migration runner must serialize concurrent deploys with an advisory lock"
grep -q 'subscription.outbox_messages' "$OUTBOX_MIGRATION" ||
  fail "Billing outbox migration is missing"
if grep -q 'GRANT.*TO notif_svc' "$NOTIFICATION_MESSAGES_MIGRATION"; then
  grep -q "WHERE rolname = 'notif_svc'" "$NOTIFICATION_MESSAGES_MIGRATION" ||
    fail "historical Notification migration must guard its notif_svc grant with a role-existence check"
fi
grep -Eq 'CREATE EXTENSION IF NOT EXISTS pg_trgm' "$ADMIN_NOTIFICATIONS_MIGRATION" ||
  fail "Admin Notification migration must provision pg_trgm before gin_trgm_ops"
grep -Eq 'CREATE TABLE IF NOT EXISTS notification\.admin_notifications' "$ADMIN_NOTIFICATIONS_MIGRATION" ||
  fail "Admin Notification migration must recover safely after a partial run"
if grep -E '^CREATE INDEX ' "$ADMIN_NOTIFICATIONS_MIGRATION" |
  grep -Ev '^CREATE INDEX IF NOT EXISTS '; then
  fail "Admin Notification indexes must be idempotent after a partial run"
fi
grep -q 'information_schema.columns' "$TRANSLATION_AUDIO_RENAME_MIGRATION" ||
  fail "Translation audio rename must inspect the live column state"
grep -q "column_name = 'is_muted'" "$TRANSLATION_AUDIO_RENAME_MIGRATION" ||
  fail "Translation audio rename must only invert data when the legacy column exists"
grep -q 'ON subscription.subscriptions (workspace_id)' "$ACTIVE_SUBSCRIPTION_MIGRATION" ||
  fail "active subscription uniqueness must target the canonical subscription schema"
grep -q 'WHERE is_active = true AND workspace_id IS NOT NULL' "$ACTIVE_SUBSCRIPTION_MIGRATION" ||
  fail "active subscription uniqueness must use the live is_active model"
grep -q 'workspace.outbox_messages' "$WORKSPACE_OUTBOX_MIGRATION" ||
  fail "Workspace outbox migration is missing"
for legacy_constraint in \
  workspace_invitations_invited_by_fkey \
  workspace_invitations_role_id_fkey \
  workspace_members_removed_by_fkey \
  workspace_members_role_id_fkey \
  workspace_members_user_id_fkey \
  workspace_verified_domains_created_by_fkey \
  workspace_verified_domains_updated_by_fkey \
  workspace_verified_domains_verified_by_fkey \
  workspaces_created_by_fkey \
  workspaces_deleted_by_fkey \
  workspaces_owner_id_fkey \
  workspaces_updated_by_fkey; do
  grep -q "DROP CONSTRAINT IF EXISTS $legacy_constraint" "$CROSS_SERVICE_FK_MIGRATION" ||
    fail "cross-service FK migration is missing $legacy_constraint"
done
grep -q 'workspace.outbox_messages' "$WORKSPACE_SERVICE_OUTBOX_MIGRATION" ||
  fail "Workspace logical-database outbox migration is missing"
grep -q 'FOR UPDATE SKIP LOCKED' \
  "$ROOT_DIR/../warptalk-backend/workspace/src/WarpTalk.WorkspaceService.Infrastructure/Outbox/WorkspaceOutboxDispatcher.cs" ||
  fail "Workspace outbox must claim messages safely"
grep -q 'subscription.inbox_messages' "$OUTBOX_MIGRATION" ||
  fail "Billing inbox migration is missing"
grep -q 'dead_lettered_at' "$DEAD_LETTER_MIGRATION" ||
  fail "Billing outbox dead-letter migration is missing"
grep -q 'notification.inbox_messages' "$NOTIFICATION_INBOX_MIGRATION" ||
  fail "Notification inbox migration is missing"
grep -q 'warptalk_billing_runtime' "$BILLING_RUNTIME_ROLE_MIGRATION" ||
  fail "Billing runtime database role migration is missing"
grep -q 'warptalk_workspace_runtime' "$WORKSPACE_RUNTIME_ROLE_MIGRATION" ||
  fail "Workspace runtime database role migration is missing"
grep -q 'warptalk_notification_runtime' "$NOTIFICATION_RUNTIME_ROLE_MIGRATION" ||
  fail "Notification runtime database role migration is missing"
grep -q 'warptalk_auth_runtime' "$AUTH_RUNTIME_ROLE_MIGRATION" ||
  fail "Auth runtime database role migration is missing"
grep -q 'DROP VIEW IF EXISTS translation_room.user_settings' "$TRANSLATION_REFERENCE_MIGRATION" ||
  fail "Translation Room cross-schema user settings view removal is missing"
grep -q 'warptalk_translation_room_runtime' "$TRANSLATION_RUNTIME_ROLE_MIGRATION" ||
  fail "Translation Room runtime database role migration is missing"
grep -q 'warptalk_transcript_runtime' "$TRANSCRIPT_RUNTIME_ROLE_MIGRATION" ||
  fail "Transcript runtime database role migration is missing"
grep -q 'warptalk_meeting_runtime' "$MEETING_RUNTIME_ROLE_MIGRATION" ||
  fail "Meeting runtime database role migration is missing"
grep -q 'warptalk_assistant_runtime' "$ASSISTANT_RUNTIME_ROLE_MIGRATION" ||
  fail "Assistant runtime database role migration is missing"
grep -q 'SUBSCRIPTION_DB_PASSWORD' "$SERVICE_DB_USER_PROVISIONER" ||
  fail "service database user provisioner must consume Billing credentials from the environment"
grep -q 'WORKSPACE_DB_PASSWORD' "$SERVICE_DB_USER_PROVISIONER" ||
  fail "service database user provisioner must consume Workspace credentials from the environment"
grep -q 'NOTIFICATION_DB_PASSWORD' "$SERVICE_DB_USER_PROVISIONER" ||
  fail "service database user provisioner must consume Notification credentials from the environment"
grep -q 'AUTH_DB_PASSWORD' "$SERVICE_DB_USER_PROVISIONER" ||
  fail "service database user provisioner must consume Auth credentials from the environment"
for credential in TRANSLATION_ROOM_DB_PASSWORD TRANSCRIPT_DB_PASSWORD MEETING_DB_PASSWORD ASSISTANT_DB_PASSWORD; do
  grep -q "$credential" "$SERVICE_DB_USER_PROVISIONER" ||
    fail "service database user provisioner is missing $credential"
done
grep -q 'provision-service-db-users.sh' "$APP_COMPOSE" ||
  fail "production migrator must provision service database logins after migrations"
grep -q 'extract-logical-databases.sh' "$APP_COMPOSE" ||
  fail "production migrator must create or verify logical databases"
grep -q 'run-logical-database-migrations.sh' "$APP_COMPOSE" ||
  fail "production migrator must run service-owned logical database migrations"
grep -q 'check-database-boundaries.sh' "$APP_COMPOSE" ||
  fail "production migrator must verify service boundaries before extraction"
grep -q 'FROM pg_extension' "$LOGICAL_DATABASE_EXTRACTOR" ||
  fail "logical database extraction must discover required source extensions"
grep -q 'CREATE EXTENSION IF NOT EXISTS' "$LOGICAL_DATABASE_EXTRACTOR" ||
  fail "logical database extraction must install extensions before schema restore"
if grep -R -n --include='*.cs' --exclude-dir=Migrations \
  'workspace\.workspaces' "$BACKEND_DIR/billing/src" >/dev/null; then
  fail "billing-service source must not query workspace.workspaces directly"
fi

# Billing owns the money path, so its data access must go through EF Core
# repositories rather than hand-written SQL. Exactly two operations cannot be
# expressed in LINQ and are approved primitives:
#
#   UsageSettlementRepository - invokes subscription.settle_usage_charge, which
#     keeps the debit, usage record, credit transaction, idempotency check and
#     overage re-evaluation atomic inside the database.
#   OutboxClaimStore - needs FOR UPDATE SKIP LOCKED so concurrent dispatchers
#     claim disjoint batches instead of blocking or double-publishing.
#
# Any other file reaching for a raw command, a raw connection, or FromSql fails
# this gate. Adding a third primitive is a deliberate decision that must be made
# here, not silently in the service.
BILLING_RAW_SQL_PRIMITIVES="UsageSettlementRepository.cs OutboxClaimStore.cs"
for primitive in $BILLING_RAW_SQL_PRIMITIVES; do
  # A stale allowlist entry is itself a defect: it would silently widen the gate
  # if the file were renamed or deleted.
  [ -f "$BACKEND_DIR/billing/src/WarpTalk.BillingService.Infrastructure/Repositories/$primitive" ] ||
    fail "approved billing raw-SQL primitive $primitive is missing; update the allowlist in this script"
done
# The trailing `|| true` matters: grep exits 1 when it finds nothing, which is
# the passing case here, and `set -e` would abort the script on it.
BILLING_RAW_SQL_OFFENDERS="$(
  grep -R -n --include='*.cs' --exclude-dir=Migrations \
    --exclude='UsageSettlementRepository.cs' \
    --exclude='OutboxClaimStore.cs' \
    -e 'GetDbConnection' \
    -e 'NpgsqlCommand' \
    -e 'CreateCommand' \
    -e 'FromSqlRaw' \
    -e 'FromSqlInterpolated' \
    -e 'ExecuteSqlRaw' \
    -e 'ExecuteSqlInterpolated' \
    "$BACKEND_DIR/billing/src" || true
)"
if [ -n "$BILLING_RAW_SQL_OFFENDERS" ]; then
  printf 'unapproved raw SQL in billing-service source:\n%s\n' "$BILLING_RAW_SQL_OFFENDERS" >&2
  fail "billing-service source must use EF Core repositories outside the approved raw-SQL primitives"
fi
# translation-room must read language data from its own
# translation_room.supported_languages view rather than the platform-owned table,
# and must obtain user settings over Auth gRPC rather than binding Auth's
# UserSettingsRepository. The scan runs over comment-stripped source so that
# documenting either arrangement is not a violation of it. An absent source tree
# would make the scan vacuously pass, so require it explicitly.
test -d "$BACKEND_DIR/translation-room/src" ||
  fail "translation-room source tree is missing; the language data contract cannot be verified"
TRANSLATION_ROOM_OFFENDERS="$(
  scan_cs_source "$BACKEND_DIR/translation-room/src" \
    -e 'platform\.supported_languages' \
    -e 'UserSettingsRepository'
)"
if [ -n "$TRANSLATION_ROOM_OFFENDERS" ]; then
  printf 'cross-schema language reads or Auth settings repository use:\n%s\n' \
    "$TRANSLATION_ROOM_OFFENDERS" >&2
  fail "translation-room source must use local language data and Auth gRPC settings"
fi

render_compose() {
  docker compose \
    --env-file "$ENV_FILE" \
    -f "$1" \
    config \
    --format json
}

DATA_JSON="$(render_compose "$DATA_COMPOSE")"
INFRA_JSON="$(render_compose "$INFRA_COMPOSE")"
APP_JSON="$(render_compose "$APP_COMPOSE")"
LOCAL_JSON="$(
  docker compose \
    --env-file "$LOCAL_ENV_FILE" \
    -f "$LOCAL_COMPOSE" \
    config \
    --format json
)"

echo "$DATA_JSON" | jq -e '
  [.services | to_entries[]]
  | all(.[]; .value.image | test("@sha256:[0-9a-f]{64}$"))
' >/dev/null || fail "every third-party Data image must be pinned by digest"

echo "$INFRA_JSON" | jq -e '
  [.services | to_entries[] | select(.key != "metrics-exporter")]
  | all(.[]; .value.image | test("@sha256:[0-9a-f]{64}$"))
' >/dev/null || fail "every third-party Infra image must be pinned by digest"

echo "$APP_JSON" | jq -e '
  [.services.migrator.image, .services.caddy.image]
  | all(test("@sha256:[0-9a-f]{64}$"))
' >/dev/null || fail "App-side third-party images must be pinned by digest"

SINGLE_HOST_JSON="$(
  docker compose \
    --env-file "$ENV_FILE" \
    -f "$DATA_COMPOSE" \
    -f "$INFRA_COMPOSE" \
    -f "$APP_COMPOSE" \
    -f "$SINGLE_HOST_COMPOSE" \
    config \
    --format json
)"

assert_services() {
  json="$1"
  shift
  for service in "$@"; do
    printf '%s\n' "$json" | jq -e --arg service "$service" \
      '.services | has($service)' >/dev/null ||
      fail "missing required service: $service"
  done
}

assert_services "$DATA_JSON" \
  postgres pgbouncer minio minio-init qdrant

assert_services "$INFRA_JSON" \
  redis rabbitmq alertmanager prometheus grafana seq otel-collector \
  postgres-exporter billing-cost-exporter livekit-cost-exporter \
  workspace-storage-exporter redis-exporter metrics-exporter

assert_services "$APP_JSON" \
  migrator auth-service workspace-service translation-room-service \
  transcript-service notification-service meeting-service assistant-service \
  billing-service gateway frontend stt-worker translation-worker translation-backfill-worker tts-worker \
  assistant-worker suggestion-worker embedding-worker billing-worker livekit-ingress-worker \
  security-worker caddy

assert_services "$SINGLE_HOST_JSON" \
  postgres redis rabbitmq qdrant auth-service workspace-service gateway frontend caddy

assert_services "$LOCAL_JSON" \
  prometheus grafana seq otel-collector alertmanager postgres-exporter \
  redis-exporter metrics-exporter billing-cost-exporter livekit-cost-exporter \
  workspace-storage-exporter

printf '%s\n' "$LOCAL_JSON" | jq -e '
  (.services.prometheus.volumes | any(.target == "/etc/prometheus/rules" and .read_only == true))
  and (.services.grafana.volumes | any(.target == "/etc/grafana/provisioning" and .read_only == true))
  and (.services.grafana.volumes | any(.target == "/var/lib/grafana/dashboards" and .read_only == true))
  and (.services.grafana.environment.GF_ANALYTICS_CHECK_FOR_UPDATES == "false")
  and (.services.grafana.environment.GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES == "false")
  and (.services.grafana.environment.GF_PLUGINS_PREINSTALL_DISABLED == "true")
  and (.services.grafana.environment.GF_PLUGINS_PLUGIN_ADMIN_ENABLED == "false")
' >/dev/null || fail "local observability must provision rules, dashboards, and deterministic Grafana startup"

echo "$APP_JSON" | jq -e '
  [
    .services
    | to_entries[]
    | select(.key != "caddy")
    | (.value.ports // [])[]
  ]
  | length == 0
' >/dev/null || fail "only caddy may publish ports on the App VM"

echo "$APP_JSON" | jq -e '
  (.services.caddy.ports // [])
  | map(.published)
  | sort
  == ["443", "443", "80"]
' >/dev/null || fail "caddy must publish TCP 80/443 and UDP 443"

data_private_ip="$(sed -n 's/^DATA_PRIVATE_IP=//p' "$ENV_FILE" | tail -n 1)"
[ -n "$data_private_ip" ] || fail "DATA_PRIVATE_IP is missing from production env example"
echo "$DATA_JSON" | jq -e --arg private_ip "$data_private_ip" '
  [
    .services
    | to_entries[]
    | (.value.ports // [])[]
    | select(.host_ip != $private_ip)
  ]
  | length == 0
' >/dev/null || fail "Data VM ports must bind only to DATA_PRIVATE_IP"

infra_private_ip="$(sed -n 's/^INFRA_PRIVATE_IP=//p' "$ENV_FILE" | tail -n 1)"
[ -n "$infra_private_ip" ] || fail "INFRA_PRIVATE_IP is missing from production env example"
echo "$INFRA_JSON" | jq -e --arg private_ip "$infra_private_ip" '
  [
    .services
    | to_entries[]
    | (.value.ports // [])[]
    | select(.host_ip != $private_ip)
  ]
  | length == 0
' >/dev/null || fail "Infra VM ports must bind only to INFRA_PRIVATE_IP"

echo "$DATA_JSON" | jq -e '
  [
    .services
    | to_entries[]
    | select(.key != "minio-init")
    | select((.value.restart // "") != "unless-stopped")
  ]
  | length == 0
' >/dev/null || fail "all persistent Data VM services must use restart: unless-stopped"

echo "$INFRA_JSON" | jq -e '
  [
    .services
    | to_entries[]
    | select((.value.restart // "") != "unless-stopped")
  ]
  | length == 0
' >/dev/null || fail "all persistent Infra VM services must use restart: unless-stopped"

echo "$DATA_JSON" | jq -e '
  [
    .services
    | to_entries[]
    | select(.key != "minio-init")
    | select(
        .value.init != true
        or (.value.security_opt // [] | index("no-new-privileges:true") | not)
        or .value.logging.driver != "json-file"
        or .value.logging.options["max-size"] == null
        or .value.logging.options["max-file"] == null
        or .value.ulimits.nofile.soft == null
      )
  ]
  | length == 0
' >/dev/null || fail "Data VM services must use init, no-new-privileges, bounded logs, and nofile limits"

echo "$INFRA_JSON" | jq -e '
  [
    .services
    | to_entries[]
    | select(
        .value.init != true
        or (.value.security_opt // [] | index("no-new-privileges:true") | not)
        or .value.logging.driver != "json-file"
        or .value.logging.options["max-size"] == null
        or .value.logging.options["max-file"] == null
        or .value.ulimits.nofile.soft == null
      )
  ]
  | length == 0
' >/dev/null || fail "Infra VM services must use init, no-new-privileges, bounded logs, and nofile limits"

echo "$DATA_JSON" | jq -e '
  [
    .services.postgres,
    .services.minio
  ]
  | all(.healthcheck.start_period != null)
' >/dev/null || fail "Data dependency health checks must define startup grace periods"

echo "$INFRA_JSON" | jq -e '
  [.services.redis, .services.rabbitmq]
  | all(.healthcheck.start_period != null)
' >/dev/null || fail "Infra dependency health checks must define startup grace periods"

grep -q 'ADMIN_CIDR must not allow the entire Internet' "$HOST_BOOTSTRAP" ||
  fail "host bootstrap must reject world-open SSH"
grep -q 'ufw default deny incoming' "$HOST_BOOTSTRAP" ||
  fail "host bootstrap must default-deny inbound traffic"
grep -q 'ufw allow in on tailscale0' "$HOST_BOOTSTRAP" ||
  fail "host bootstrap must rebuild tailnet SSH or a re-run cuts off the release workflow"
grep -q 'download.docker.com/linux/ubuntu' "$HOST_BOOTSTRAP" ||
  fail "host bootstrap must install Docker from the signed apt repository"
grep -q 'APP_PRIVATE_IP=10.20.0.10' "$SINGLE_HOST_INVENTORY" &&
  grep -q 'DATA_PRIVATE_IP=10.20.0.10' "$SINGLE_HOST_INVENTORY" ||
  fail "single-host inventory must route both roles through one private interface"

echo "$INFRA_JSON" | jq -e '
  .services["metrics-exporter"]
  | (.image | contains("/ai-metrics:"))
    and (.environment.REDIS_URL == "redis://redis:6379")
    and (.environment.METRICS_PORT == "9108")
    and (.healthcheck.test | join(" ") | contains("/health/ready"))
' >/dev/null || fail "WarpTalk metrics exporter must expose Redis worker and stream health"
grep -q "metrics-exporter:9108" "$ROOT_DIR/observability/prometheus.yml" ||
  fail "Prometheus must scrape the WarpTalk metrics exporter"

echo "$INFRA_JSON" | jq -e '
  .services["postgres-exporter"].environment.DATA_SOURCE_NAME
  | contains("warptalk_monitor")
    and (contains("postgres:${POSTGRES_PASSWORD}") | not)
' >/dev/null || fail "PostgreSQL exporter must use the least-privilege monitor role"

echo "$INFRA_JSON" | jq -e '
  [
    .services["billing-cost-exporter"],
    .services["livekit-cost-exporter"],
    .services["workspace-storage-exporter"]
  ]
  | all(
      (.image | startswith("burningalchemist/sql_exporter:0.24.3@sha256:"))
      and (.environment.SQLEXPORTER_TARGET_DSN | contains("warptalk_monitor"))
      and ((.deploy.resources.limits.memory | tonumber) >= 50331648)
      and ((.deploy.resources.limits.memory | tonumber) <= 67108864)
    )
' >/dev/null || fail "cost exporters must use pinned SQL Exporter and the monitor role"

echo "$DATA_JSON" | jq -e '
  .services.minio.environment.MINIO_PROMETHEUS_AUTH_TYPE == "public"
' >/dev/null || fail "MinIO bucket metrics must be enabled on the private data network"

grep -q 'alertmanager:9093' "$ROOT_DIR/observability/prometheus.yml" ||
  fail "Prometheus must forward alerts to Alertmanager"
for target in billing-cost-exporter:9188 livekit-cost-exporter:9189 workspace-storage-exporter:9190 data-host:9000 data-host:6333; do
  grep -q "$target" "$ROOT_DIR/observability/prometheus.yml" ||
    fail "Prometheus is missing scrape target $target"
done
grep -q 'WarpTalkAiWorkerMissing' "$ROOT_DIR/observability/alerts/warptalk.rules.yml" ||
  fail "AI worker heartbeat alert is missing"
grep -q 'WarpTalkDeadLetterPresent' "$ROOT_DIR/observability/alerts/warptalk.rules.yml" ||
  fail "dead-letter alert is missing"

echo "$APP_JSON" | jq -e '
  [
    .services["auth-service"].environment.Redis__ConnectionString,
    .services["workspace-service"].environment.RabbitMQ__Host,
    .services["auth-service"].environment.OTEL_EXPORTER_OTLP_ENDPOINT
  ]
  | all(contains("10.20.0.30"))
' >/dev/null || fail "App services must route Redis, RabbitMQ, and OTLP through the Infra VM"

echo "$APP_JSON" | jq -e '
  [
    .services
    | to_entries[]
    | select(.key != "migrator")
    | select((.value.restart // "") != "unless-stopped")
  ]
  | length == 0
' >/dev/null || fail "all long-running App VM services must use restart: unless-stopped"

echo "$APP_JSON" | jq -e '
  .services["translation-room-service"].environment
  | (.["ConnectionStrings__TranslationRoomDb"] | contains("Database=warptalk_translation_room"))
    and (.["ConnectionStrings__TranslationRoomDb"] | contains("Username=warptalk_translation_room"))
    and (.["ConnectionStrings__TranslationRoomDb"] | contains("Username=postgres") | not)
' >/dev/null || fail "translation-room-service must use its least-privilege database login"

echo "$APP_JSON" | jq -e '
  .services["transcript-service"].environment
  | (.["ConnectionStrings__TranscriptDb"] | contains("Database=warptalk_transcript"))
    and (.["ConnectionStrings__TranscriptDb"] | contains("Username=warptalk_transcript"))
    and (.["ConnectionStrings__TranscriptDb"] | contains("Username=postgres") | not)
' >/dev/null || fail "transcript-service must use its least-privilege database login"

echo "$APP_JSON" | jq -e '
  .services["meeting-service"].environment
  | (.["ConnectionStrings__DefaultConnection"] | contains("Database=warptalk_meeting"))
    and (.["ConnectionStrings__DefaultConnection"] | contains("Username=warptalk_meeting"))
    and (.["ConnectionStrings__DefaultConnection"] | contains("Username=postgres") | not)
' >/dev/null || fail "meeting-service must use its least-privilege database login"

echo "$APP_JSON" | jq -e '
  .services["assistant-service"].environment
  | (.["ConnectionStrings__AssistantDb"] | contains("Database=warptalk_assistant"))
    and (.["ConnectionStrings__AssistantDb"] | contains("Username=warptalk_assistant"))
    and (.["ConnectionStrings__AssistantDb"] | contains("Username=postgres") | not)
' >/dev/null || fail "assistant-service must use its least-privilege database login"

echo "$APP_JSON" | jq -e '
  .services["auth-service"].environment
  | (.["ConnectionStrings__AuthDb"] | contains("Database=warptalk_auth"))
    and (.["ConnectionStrings__AuthDb"] | contains("Username=warptalk_auth"))
    and (.["ConnectionStrings__AuthDb"] | contains("Username=postgres") | not)
' >/dev/null || fail "auth-service must use its least-privilege database login"

echo "$APP_JSON" | jq -e '
  .services["auth-service"].environment
  | has("Authentication__Google__ClientId")
    and (.["Authentication__Google__ClientId"] | length > 0)
' >/dev/null || fail "auth-service must receive the Google OAuth client ID"

echo "$APP_JSON" | jq -e '
  .services["workspace-service"].environment
  | (.["ConnectionStrings__WorkspaceDb"] | contains("Database=warptalk_workspace"))
    and (.["ConnectionStrings__WorkspaceDb"] | contains("Search Path=workspace,public"))
    and (.["ConnectionStrings__WorkspaceDb"] | contains("Username=warptalk_workspace"))
    and (.["ConnectionStrings__WorkspaceDb"] | contains("Username=postgres") | not)
' >/dev/null || fail "workspace-service must use its least-privilege database login"

echo "$APP_JSON" | jq -e '
  .services["billing-service"].environment
  | has("Stripe__SecretKey")
    and has("Stripe__WebhookSecret")
    and has("Stripe__SuccessUrl")
    and has("Stripe__CancelUrl")
' >/dev/null || fail "billing-service must receive Stripe checkout and webhook configuration"

echo "$APP_JSON" | jq -e '
  .services["billing-service"].environment
  | has("RabbitMQ__Host")
    and has("RabbitMQ__Username")
    and has("RabbitMQ__Password")
' >/dev/null || fail "billing-service must receive RabbitMQ outbox transport configuration"

echo "$APP_JSON" | jq -e '
  .services["billing-service"].environment
  | .["GrpcUrls__WorkspaceServiceUrl"] == "http://workspace-service:50056"
    and (.["ConnectionStrings__BillingDb"] | contains("Database=warptalk_billing"))
    and (.["ConnectionStrings__BillingDb"] | contains("Search Path=subscription,public"))
    and (.["ConnectionStrings__BillingDb"] | contains("Username=warptalk_billing"))
    and (.["ConnectionStrings__BillingDb"] | contains("workspace") | not)
    and (.["ConnectionStrings__BillingDb"] | contains("Username=postgres") | not)
' >/dev/null || fail "billing-service must use Workspace gRPC without workspace schema access"

echo "$APP_JSON" | jq -e '
  .services["notification-service"].environment
  | has("RabbitMQ__Host")
    and has("RabbitMQ__Username")
    and has("RabbitMQ__Password")
    and has("RESEND_API_KEY")
    and has("Resend__FromEmail")
    and has("Resend__FromName")
    and (.["Resend__FromEmail"] | length > 0)
    and (.["Resend__FromName"] | length > 0)
    and has("Grpc__InternalSecret")
    and (.["ConnectionStrings__DefaultConnection"] | contains("Database=warptalk_notification"))
    and (.["ConnectionStrings__DefaultConnection"] | contains("Username=warptalk_notification"))
    and (.["ConnectionStrings__DefaultConnection"] | contains("Username=postgres") | not)
' >/dev/null || fail "notification-service must receive RabbitMQ consumer configuration"

echo "$APP_JSON" | jq -e '
  [
    .services
    | to_entries[]
    | select(.key | endswith("-service") or . == "gateway")
    | select(.value.environment["Grpc__InternalSecret"] == null)
  ]
  | length == 0
' >/dev/null || fail "all .NET services and gateway must receive the internal gRPC secret"

echo "$APP_JSON" | jq -e '
  .services.gateway.environment[
    "ReverseProxy__Clusters__billing-cluster__Destinations__billing-service__Address"
  ] == "http://billing-service:5107"
' >/dev/null || fail "gateway must route billing endpoints to billing-service"

echo "production deployment contract: PASS"
