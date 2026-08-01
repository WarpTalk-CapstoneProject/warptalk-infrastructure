#!/bin/sh
set -eu

repo_root="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
image_dir="$repo_root/health-inspector"

fail() {
  echo "health inspector contract: FAIL - $*" >&2
  exit 1
}

grep -Fq 'docker-cli' "$image_dir/Dockerfile" ||
  fail "image must carry the Docker CLI"
grep -Fq '/var/run/docker.sock' "$repo_root/docker-compose.yml" ||
  fail "Compose service must mount the Docker socket read-only"
grep -Fq 'health-inspector:' "$repo_root/docker-compose.yml" ||
  fail "Compose must expose the on-demand health-inspector service"
grep -Fq 'profiles: ["tools"]' "$repo_root/docker-compose.yml" ||
  fail "health inspector must not start with the application stack"
grep -Fq 'EXPECTED_SERVICES' "$image_dir/inspector.py" ||
  fail "missing microservices must be detected from an explicit inventory"
grep -Fq 'warptalk-health-inspector:20260801' "$image_dir/warptalk-health-check" ||
  fail "host command must run the installed immutable inspector image"

echo "health inspector contract: PASS"
