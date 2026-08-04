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
grep -Fq 'warptalk-health-inspector:20260801-v3' "$image_dir/warptalk-health-check" ||
  fail "host command must run the installed immutable inspector image"
grep -Fq -- '--until' "$image_dir/inspector.py" ||
  fail "inspector must support bounded historical log windows"
grep -Fq 'group_log_findings' "$image_dir/inspector.py" ||
  fail "inspector must deduplicate repeated log evidence"
grep -Fq '/state/checkpoint.json' "$image_dir/warptalk-health-check" ||
  fail "host command must persist restart checkpoints"
grep -Fq 'docker volume create' "$image_dir/warptalk-health-check" ||
  fail "host command must provision a dedicated persistent state volume"
grep -Fq 'warptalk-health-inspector-state:/state' "$image_dir/warptalk-health-check" ||
  fail "checkpoint state must use the dedicated Docker volume"
grep -Fq 'kiểm tra log lỗi của prod' "$image_dir/AGENT-RUNBOOK.md" ||
  fail "agent runbook must define the production log trigger phrase"
grep -Fq 'warptalk-health-check --since 30m --json' "$image_dir/AGENT-RUNBOOK.md" ||
  fail "agent runbook must define the default production scan"
grep -Fq 'App, Data, and Infra' "$repo_root/AGENTS.md" ||
  fail "Codex instructions must require all production roles"
grep -Fq 'App, Data, and Infra' "$repo_root/CLAUDE.md" ||
  fail "Claude instructions must require all production roles"

echo "health inspector contract: PASS"
