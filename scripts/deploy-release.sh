#!/bin/sh
# Deploy one immutable WarpTalk release to exactly one production host role.
set -eu

: "${DEPLOY_ROLE:?DEPLOY_ROLE is required: app, data, or infra}"
: "${RELEASE_MANIFEST:?RELEASE_MANIFEST is required}"
: "${PRODUCTION_ENV_FILE:?PRODUCTION_ENV_FILE is required}"

SKIP_IMAGE_PULL="${SKIP_IMAGE_PULL:-false}"
DEPLOY_MODE="${DEPLOY_MODE:-full}"
DEPLOY_SERVICES="${DEPLOY_SERVICES:-}"
RUN_MIGRATIONS="${RUN_MIGRATIONS:-true}"
case "$SKIP_IMAGE_PULL" in
  true|false) ;;
  *)
    echo "SKIP_IMAGE_PULL must be true or false" >&2
    exit 1
    ;;
esac
case "$DEPLOY_MODE" in
  full|selective) ;;
  *) echo "DEPLOY_MODE must be full or selective" >&2; exit 1 ;;
esac
case "$RUN_MIGRATIONS" in
  true|false) ;;
  *) echo "RUN_MIGRATIONS must be true or false" >&2; exit 1 ;;
esac
if [ "$DEPLOY_MODE" = "selective" ] && [ -z "$DEPLOY_SERVICES" ]; then
  echo "DEPLOY_SERVICES is required for a selective deployment" >&2
  exit 1
fi

command -v docker >/dev/null 2>&1 || {
  echo "docker is required" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "jq is required" >&2
  exit 1
}
test -r "$RELEASE_MANIFEST" || {
  echo "Cannot read release manifest" >&2
  exit 1
}
test -r "$PRODUCTION_ENV_FILE" || {
  echo "Cannot read production environment" >&2
  exit 1
}

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
production_dir="$script_dir/../deploy/production"
matrix_file="$production_dir/image-matrix.json"
override_filter="$production_dir/release-override.jq"

PRODUCTION_ENV_FILE="$PRODUCTION_ENV_FILE" \
  "$script_dir/validate-production-env.sh"

case "$DEPLOY_ROLE" in
  app) compose_file="$production_dir/app.compose.yml" ;;
  data) compose_file="$production_dir/data.compose.yml" ;;
  infra) compose_file="$production_dir/infra.compose.yml" ;;
  *)
    echo "DEPLOY_ROLE must be app, data, or infra" >&2
    exit 1
    ;;
esac

for required_file in "$matrix_file" "$override_filter" "$compose_file"; do
  test -r "$required_file" || {
    echo "Cannot read deployment artifact: $required_file" >&2
    exit 1
  }
done

# The Infra role's Alertmanager config and the three sql_exporter query files are
# rendered from templates, never committed (they carry the Resend SMTP key and are
# gitignored). Until this ran here, rendering was a manual README step: every
# release unpacked a fresh releases/<tag>/ tree without the rendered query files,
# Docker created empty DIRECTORIES at those bind-mount paths, and all three
# sql_exporters crash-looped on "sql_exporter.yml: is a directory" — taking the
# billing-cost, livekit-cost and workspace-storage metrics down with them.
# Rendering in a subshell keeps the production secrets out of the deploy shell.
if [ "$DEPLOY_ROLE" = "infra" ]; then
  (
    set -a
    # The env file is a runtime host path (/etc/warptalk/.env.production), so
    # there is nothing for shellcheck to follow at lint time.
    # shellcheck source=/dev/null
    . "$PRODUCTION_ENV_FILE"
    set +a

    ALERTMANAGER_CONFIG_PATH="$ALERTMANAGER_CONFIG_PATH" \
      "$script_dir/render-alertmanager-config.sh"
    "$script_dir/render-cost-observability.sh"
  )
fi

jq -e --slurpfile matrix "$matrix_file" '
  .schemaVersion == 1 and
  ([.images[].service] | sort) == ([$matrix[0].images[].service] | sort) and
  (.images | length) == ([.images[].service] | unique | length) and
  all(.images[];
    (.service | test("^[a-z0-9][a-z0-9-]*$")) and
    (.ref | length > 0) and
    (.digest | test("^sha256:[a-f0-9]{64}$"))
  )
' "$RELEASE_MANIFEST" >/dev/null

base_config="$(mktemp)"
override="$(mktemp)"
trap 'rm -f "$base_config" "$override"' EXIT INT TERM

docker compose \
  --env-file "$PRODUCTION_ENV_FILE" \
  -f "$compose_file" \
  config \
  --format json >"$base_config"

jq --slurpfile base "$base_config" \
  -f "$override_filter" \
  "$RELEASE_MANIFEST" >"$override"

compose() {
  docker compose \
    --env-file "$PRODUCTION_ENV_FILE" \
    -f "$compose_file" \
    -f "$override" \
    "$@"
}

compose config --quiet

# Rendering the Alertmanager config is not the same as loading it. Nothing about
# the alertmanager service's spec or image digest changes when only the bytes on
# disk change, so `compose up -d` correctly concludes there is nothing to
# recreate and the running process keeps serving whatever it parsed at startup.
#
# That is how production served a stale Alertmanager configuration for six days
# while the correct one sat on disk, and dropped two genuinely firing alerts
# (WarpTalkObjectStorageBudgetNearLimit and WarpTalkObjectStorageBudgetExceeded).
# The container reported `Up 6 days` while the cost exporters that feed those
# alerts reported `Up 4 hours`.
#
# The renderer truncates and rewrites the same inode, so the read-only bind mount
# inside the container already sees the new bytes; only the reload was missing,
# and Alertmanager performs one on SIGHUP.
#
# Signal only a container that was already running before this deploy and was not
# replaced by it. A container that `compose up` created or recreated has just
# parsed the rendered file itself, and signalling a process that started
# milliseconds ago risks arriving before it installs its SIGHUP handler, whose
# default disposition is to terminate.
running_alertmanager() {
  alertmanager_container="$(compose ps -q alertmanager 2>/dev/null || true)"
  [ -n "$alertmanager_container" ] || return 0
  alertmanager_state="$(
    docker inspect -f '{{.State.Running}}' "$alertmanager_container" 2>/dev/null || echo false
  )"
  [ "$alertmanager_state" = "true" ] || return 0
  printf '%s\n' "$alertmanager_container"
}

alertmanager_before=''
if [ "$DEPLOY_ROLE" = "infra" ]; then
  alertmanager_before="$(running_alertmanager)"
fi

if [ "$DEPLOY_MODE" = "selective" ]; then
  # The planner emits service names from the trusted image matrix. Validate
  # again at the host boundary before allowing them to become CLI arguments.
  set -- $DEPLOY_SERVICES
  for service in "$@"; do
    echo "$service" | grep -Eq '^[a-z0-9][a-z0-9-]*$' || {
      echo "Invalid selective deployment service: $service" >&2
      exit 1
    }
    jq -e --arg service "$service" '.services | has($service)' "$override" >/dev/null || {
      echo "Service is not an immutable image on this role: $service" >&2
      exit 1
    }
  done
  if [ "$SKIP_IMAGE_PULL" != "true" ]; then
    compose pull "$@"
  fi
else
  if [ "$SKIP_IMAGE_PULL" != "true" ]; then
    compose pull
  fi
fi

if [ "$DEPLOY_ROLE" = "app" ] && [ "$RUN_MIGRATIONS" = "true" ]; then
  compose run --rm migrator
fi

if [ "$DEPLOY_MODE" = "selective" ]; then
  compose up -d --no-deps "$@"
else
  compose up -d --remove-orphans
fi

if [ "$DEPLOY_ROLE" = "infra" ]; then
  # Idempotent: a reload re-reads the file and is a no-op when the content is
  # unchanged, and silences and notification state live in the alertmanager-data
  # volume rather than in process memory. Nothing here may fail the release --
  # on a first deploy there is no container to signal, and a signal that cannot
  # be delivered is reported rather than fatal.
  alertmanager_after="$(running_alertmanager)"
  if [ -z "$alertmanager_before" ]; then
    echo "Alertmanager was not running before this deploy; it reads the rendered configuration at startup."
  elif [ "$alertmanager_after" != "$alertmanager_before" ]; then
    echo "Alertmanager was recreated by this deploy; it read the rendered configuration at startup."
  elif docker kill -s HUP "$alertmanager_before" >/dev/null 2>&1; then
    echo "Reloaded the rendered Alertmanager configuration (SIGHUP to $alertmanager_before)."
  else
    echo "warning: could not signal Alertmanager ($alertmanager_before); it may still be serving the previous configuration" >&2
  fi
fi

echo "Deployed immutable release $(jq -r '.tag' "$RELEASE_MANIFEST") to $DEPLOY_ROLE ($DEPLOY_MODE)"
