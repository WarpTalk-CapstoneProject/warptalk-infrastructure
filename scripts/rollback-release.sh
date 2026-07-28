#!/bin/sh
# Rollback is an immutable deployment of a previously verified manifest.
set -eu

: "${PREVIOUS_RELEASE_MANIFEST:?PREVIOUS_RELEASE_MANIFEST is required}"
: "${PRODUCTION_ENV_FILE:?PRODUCTION_ENV_FILE is required}"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
RELEASE_MANIFEST="$PREVIOUS_RELEASE_MANIFEST" \
PRODUCTION_ENV_FILE="$PRODUCTION_ENV_FILE" \
  "$script_dir/deploy-release.sh"
