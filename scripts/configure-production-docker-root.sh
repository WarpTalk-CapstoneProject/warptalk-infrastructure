#!/bin/sh
set -eu

ROLE="${ROLE:-}"
durable_mount=/srv/warptalk
docker_root="$durable_mount/docker"
daemon_config=/etc/docker/daemon.json

fail() {
  echo "configure-production-docker-root: $*" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || fail "run as root"
[ "$ROLE" = "data" ] || [ "$ROLE" = "infra" ] ||
  fail "ROLE must be data or infra"
findmnt --mountpoint /srv/warptalk >/dev/null 2>&1 ||
  fail "/srv/warptalk is not a mounted durable volume"
command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v docker >/dev/null 2>&1 || fail "Docker is required"

current_root="$(docker info --format '{{.DockerRootDir}}')"
if [ "$current_root" = "$docker_root" ]; then
  echo "configure-production-docker-root: PASS role=$ROLE root=$docker_root"
  exit 0
fi

[ -z "$(docker ps -aq)" ] ||
  fail "existing containers require an explicit migration"
[ -z "$(docker images -aq)" ] ||
  fail "existing images require an explicit migration"

install -d -m 0710 -o root -g docker "$docker_root"
temporary_config="$(mktemp)"
trap 'rm -f "$temporary_config"' EXIT INT TERM

if [ -f "$daemon_config" ]; then
  jq --arg root "$docker_root" '. + {"data-root": $root}' \
    "$daemon_config" >"$temporary_config"
else
  jq -n --arg root "$docker_root" '{"data-root": $root}' >"$temporary_config"
fi
jq -e --arg root "$docker_root" '.["data-root"] == $root' \
  "$temporary_config" >/dev/null ||
  fail "generated Docker configuration is invalid"

systemctl stop docker.service docker.socket
install -m 0644 "$temporary_config" "$daemon_config"
systemctl restart docker

configured_root="$(docker info --format '{{.DockerRootDir}}')"
[ "$configured_root" = "$docker_root" ] ||
  fail "DockerRootDir verification failed"

echo "configure-production-docker-root: PASS role=$ROLE root=$docker_root"
