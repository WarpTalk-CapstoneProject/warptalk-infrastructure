#!/bin/sh
set -eu

root_dir="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
caddy="$root_dir/deploy/production/Caddyfile"
traefik="$root_dir/deploy/k3s/chart/templates/security-headers.yaml"
k3s_check="$root_dir/scripts/check-k3s-deployment.sh"
smoke="$root_dir/scripts/security-smoke.sh"

grep -Fq 'X-Frame-Options "DENY"' "$caddy"
grep -Fq "customFrameOptionsValue: DENY" "$traefik"
grep -Fq "customFrameOptionsValue: DENY" "$k3s_check"
grep -Fq "Content-Security-Policy" "$caddy"
grep -Fq "contentSecurityPolicy:" "$traefik"
grep -Fq "frame-ancestors 'none'" "$caddy"
grep -Fq "frame-ancestors 'none'" "$traefik"
grep -Fq "content-security-policy:" "$smoke"

echo "security header contract passed"
