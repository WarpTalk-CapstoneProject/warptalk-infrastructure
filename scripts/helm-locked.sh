#!/bin/sh
# Run Helm at the version locked in deploy/k3s/addons.lock.env (HELM_IMAGE), never whatever `helm`
# happens to be on the PATH. A laptop with Helm 4 and a runner with Helm 3.x render and upgrade
# differently; every K3s script goes through this wrapper so a release is planned and applied by
# the same binary the contracts were checked with.
#
# Usage: helm-locked.sh <helm arguments...>
#
# Paths: every absolute path argument that exists (a chart, a -f values file, a post-renderer)
# is bind-mounted at the SAME path inside the container, so callers pass ordinary host paths.
# KUBECONFIG, when set, is mounted read-only at its own path too. Repository state (helm repo add)
# persists in WARPTALK_HELM_HOME between calls.
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
lock_file="$script_dir/../deploy/k3s/addons.lock.env"

fail() {
  echo "helm-locked: $*" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || fail "missing dependency: docker"
test -r "$lock_file" || fail "cannot read add-on lock"
helm_image="$(sed -n 's/^HELM_IMAGE=//p' "$lock_file")"
[ -n "$helm_image" ] || fail "HELM_IMAGE is not locked"

helm_home="${WARPTALK_HELM_HOME:-${TMPDIR:-/tmp}/warptalk-helm-home}"
mkdir -p "$helm_home"

# Mount list, built as positional arguments so paths with spaces survive.
mounts_file="$(mktemp "${TMPDIR:-/tmp}/warptalk-helm-mounts.XXXXXX")"
trap 'rm -f "$mounts_file"' EXIT INT TERM
add_mount() {
  # $1 path, $2 mode (ro|rw)
  printf '%s\n%s\n' "-v" "$1:$1:$2" >>"$mounts_file"
}

add_mount "$helm_home" rw
if [ -n "${KUBECONFIG:-}" ]; then
  case "$KUBECONFIG" in
    /*) ;;
    *) fail "KUBECONFIG must be an absolute path" ;;
  esac
  test -r "$KUBECONFIG" || fail "cannot read KUBECONFIG"
  add_mount "$KUBECONFIG" ro
fi
for argument in "$@"; do
  case "$argument" in
    /*)
      if [ -e "$argument" ]; then
        add_mount "$argument" ro
      fi
      ;;
  esac
done

docker_arguments_file="$(mktemp "${TMPDIR:-/tmp}/warptalk-helm-args.XXXXXX")"
trap 'rm -f "$mounts_file" "$docker_arguments_file"' EXIT INT TERM
{
  printf '%s\n' run --rm -i --network host
  printf '%s\n' --user "$(id -u):$(id -g)"
  printf '%s\n' -e "HOME=$helm_home"
  printf '%s\n' -e "HELM_CACHE_HOME=$helm_home/cache"
  printf '%s\n' -e "HELM_CONFIG_HOME=$helm_home/config"
  printf '%s\n' -e "HELM_DATA_HOME=$helm_home/data"
  if [ -n "${KUBECONFIG:-}" ]; then
    printf '%s\n' -e "KUBECONFIG=$KUBECONFIG"
  fi
  # Post-renderers read their pins from the lock (pin-qdrant-images.sh needs QDRANT_IMAGE_DIGEST).
  printf '%s\n' --env-file "$lock_file"
  cat "$mounts_file"
  printf '%s\n' "$helm_image"
} >"$docker_arguments_file"

# Rebuild argv as: docker <docker args...> <helm args...>. Arguments are read back one per line;
# none of the docker arguments above can contain a newline.
helm_argument_count="$#"
while IFS= read -r line; do
  set -- "$@" "$line"
done <"$docker_arguments_file"
# Rotate the helm arguments (the first $helm_argument_count) to the end.
index=0
while [ "$index" -lt "$helm_argument_count" ]; do
  first="$1"
  shift
  set -- "$@" "$first"
  index=$((index + 1))
done

# Not exec: the traps above must still remove the temporary argument files.
status=0
docker "$@" || status=$?
exit "$status"
