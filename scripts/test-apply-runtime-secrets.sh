#!/bin/sh
# Contract for apply-runtime-secrets.sh.
#
# The script runs on a production host with every credential the platform has in one file, so the
# cases that matter are the destructive ones: does an unset secret blank a key, does a value
# containing sed metacharacters survive intact, does the file keep mode 0600, and does it report
# `changed` only when something actually changed — the word the release workflow uses to decide
# whether containers must be recreated.

set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
subject="$script_dir/apply-runtime-secrets.sh"

work="$(mktemp -d "${TMPDIR:-/tmp}/warptalk-runtime-secrets.XXXXXX")"
trap 'rm -rf "$work"' EXIT INT TERM

env_file="$work/.env.production"
secrets_file="$work/secrets.env"

fail() {
  echo "test-apply-runtime-secrets: $*" >&2
  exit 1
}

reset_env() {
  cat >"$env_file" <<'EOF'
IMAGE_TAG=prod-20260813-example-v1
JWT_SECRET=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
STRIPE_SECRET_KEY=sk_test_stale
STRIPE_WEBHOOK_SECRET=whsec_disabled_pending_valid_stripe_key
ALERT_EMAIL_TO=ops@example.com
EOF
  chmod 0600 "$env_file"
}

run() {
  PRODUCTION_ENV_FILE="$env_file" RUNTIME_SECRETS_FILE="$secrets_file" "$subject" 2>/dev/null
}

value_of() {
  sed -n "s/^$1=//p" "$env_file" | tail -n 1
}

# ── A new value replaces the old one, in place, and says so ──────────────────────────────────
reset_env
printf 'STRIPE_SECRET_KEY=sk_test_fresh\n' >"$secrets_file"
[ "$(run)" = "changed" ] || fail "a new value must report changed"
[ "$(value_of STRIPE_SECRET_KEY)" = "sk_test_fresh" ] || fail "the new value was not applied"
[ "$(value_of JWT_SECRET)" = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ] ||
  fail "an unrelated key was disturbed"
[ "$(grep -c '^STRIPE_SECRET_KEY=' "$env_file")" = "1" ] || fail "the key was duplicated"

# ── Re-running is a no-op, so an unchanged secret does not force a full deploy every release ──
[ "$(run)" = "unchanged" ] || fail "re-applying the same value must report unchanged"

# ── An unset GitHub secret arrives empty and MUST NOT blank the key ───────────────────────────
# This is the one that takes the platform down: a renamed or removed secret erasing JWT_SECRET.
reset_env
printf 'STRIPE_SECRET_KEY=\nJWT_SECRET=\n' >"$secrets_file"
[ "$(run)" = "unchanged" ] || fail "empty values must be ignored, not applied"
[ "$(value_of STRIPE_SECRET_KEY)" = "sk_test_stale" ] || fail "an empty value erased a key"
[ -n "$(value_of JWT_SECRET)" ] || fail "an empty value erased JWT_SECRET"

# ── A key the file does not have yet is appended ──────────────────────────────────────────────
reset_env
printf 'LIVEKIT_API_SECRET=brand-new\n' >"$secrets_file"
[ "$(run)" = "changed" ] || fail "a missing key must be added"
[ "$(value_of LIVEKIT_API_SECRET)" = "brand-new" ] || fail "the missing key was not appended"

# ── Real secrets contain the characters sed treats as syntax ──────────────────────────────────
# & is literal in a sed replacement and / is the default delimiter; base64 produces both.
reset_env
awkward='sk_test_a&b/c\d$e"f'"'"'g|h.i*j[k]'
printf 'STRIPE_SECRET_KEY=%s\n' "$awkward" >"$secrets_file"
[ "$(run)" = "changed" ] || fail "an awkward value must apply"
[ "$(value_of STRIPE_SECRET_KEY)" = "$awkward" ] || fail "the value was mangled in transit"

# ── The file keeps 0600, which validate-production-env.sh requires ─────────────────────────────
mode="$(stat -c '%a' "$env_file" 2>/dev/null || stat -f '%Lp' "$env_file")"
[ "$mode" = "600" ] || fail "the environment file lost mode 0600 (got $mode)"

# ── A value pasted from a Windows editor keeps its carriage return without it ─────────────────
reset_env
printf 'STRIPE_SECRET_KEY=sk_test_crlf\r\n' >"$secrets_file"
run >/dev/null
[ "$(value_of STRIPE_SECRET_KEY)" = "sk_test_crlf" ] || fail "a CRLF line left a carriage return in the value"

# ── A malformed key is refused rather than written as a line the parser misreads ──────────────
reset_env
printf 'not a key=whatever\n' >"$secrets_file"
if run >/dev/null 2>&1; then fail "a malformed secret name was accepted"; fi
[ "$(value_of STRIPE_SECRET_KEY)" = "sk_test_stale" ] || fail "a rejected run still modified the file"

# ── A missing environment file is an error, not a new file with one key in it ─────────────────
rm -f "$env_file"
printf 'STRIPE_SECRET_KEY=sk_test_x\n' >"$secrets_file"
if run >/dev/null 2>&1; then fail "a missing environment file was accepted"; fi

echo "test-apply-runtime-secrets: PASS"
