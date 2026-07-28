#!/bin/sh
# Deploy exactly the image digests recorded in one release manifest.
set -eu

: "${RELEASE_MANIFEST:?RELEASE_MANIFEST is required}"
: "${PRODUCTION_ENV_FILE:?PRODUCTION_ENV_FILE is required}"

command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
test -r "$RELEASE_MANIFEST" || { echo "Cannot read release manifest" >&2; exit 1; }
test -r "$PRODUCTION_ENV_FILE" || { echo "Cannot read production environment" >&2; exit 1; }

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
production_dir="$script_dir/../deploy/production"
matrix_file="$production_dir/image-matrix.json"
override="$(mktemp)"
trap 'rm -f "$override"' EXIT INT TERM

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

jq '{
  services: reduce .images[] as $image ({};
    .[$image.service] = {image: ($image.ref + "@" + $image.digest)}
  )
}' "$RELEASE_MANIFEST" > "$override"

compose() {
  docker compose \
    --env-file "$PRODUCTION_ENV_FILE" \
    -f "$production_dir/app.compose.yml" \
    -f "$override" \
    "$@"
}

compose config --quiet
compose pull
compose run --rm migrator
compose up -d --remove-orphans

echo "Deployed immutable release $(jq -r '.tag' "$RELEASE_MANIFEST")"
