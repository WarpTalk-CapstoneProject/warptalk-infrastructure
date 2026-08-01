#!/bin/sh
set -eu

repo_root="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
dockerfile="$repo_root/health-inspector/Dockerfile"

grep -Fq 'apk upgrade --no-cache' "$dockerfile" || {
  echo 'health inspector image must install current Alpine security updates' >&2
  exit 1
}

grep -Fq 'pip uninstall --yes pip setuptools wheel' "$dockerfile" || {
  echo 'health inspector runtime must remove unused Python packaging tools' >&2
  exit 1
}

echo 'Health inspector image security contract: PASS'
