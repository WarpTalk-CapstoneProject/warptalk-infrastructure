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

echo "Deployed immutable release $(jq -r '.tag' "$RELEASE_MANIFEST") to $DEPLOY_ROLE ($DEPLOY_MODE)"
