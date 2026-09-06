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
grep -Fq "script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' blob: https://accounts.google.com/gsi/client" "$caddy"
grep -Fq "style-src 'self' 'unsafe-inline' https://accounts.google.com/gsi/style https://fonts.googleapis.com" "$caddy"
# WT-600: `blob:` is what lets the in-browser PDF preview render at all — an iframe over an
# object URL is governed by frame-src, and without it Chrome shows a broken-file icon in
# production only. Pinned as a whole directive so removing the token fails here rather than in a
# bug report about uploaded documents.
grep -Fq "frame-src 'self' blob: https://accounts.google.com/gsi/" "$caddy"
grep -Fq "connect-src 'self' https: wss: https://accounts.google.com/gsi/" "$caddy"
grep -Fq "script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' blob: https://accounts.google.com/gsi/client" "$traefik"
grep -Fq "style-src 'self' 'unsafe-inline' https://accounts.google.com/gsi/style https://fonts.googleapis.com" "$traefik"
grep -Fq "frame-src 'self' blob: https://accounts.google.com/gsi/" "$traefik"
grep -Fq "connect-src 'self' https: wss: https://accounts.google.com/gsi/" "$traefik"
grep -Fq "content-security-policy:" "$smoke"

echo "security header contract passed"
