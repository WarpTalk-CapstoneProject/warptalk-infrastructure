#!/bin/sh
# Write GitHub-held runtime secrets into the production environment file.
#
# WHY THIS EXISTS
#   STRIPE_SECRET_KEY and STRIPE_WEBHOOK_SECRET existed only as hand-typed lines in
#   /etc/warptalk/.env.production. Nothing reviewed them, nothing versioned them, and changing one
#   meant opening an editor on a production host. That is not a hypothetical risk: the deployed
#   Stripe key differed from the real one by two characters — a capital O typed as a zero, twice —
#   and checkout returned "invalid API key" for days while the code was blameless. A value nobody
#   can diff is a value nobody can check.
#
#   validate-production-env.sh did not catch it because it only tests the PREFIX: `sk_test_`
#   followed by anything passes, and so does the placeholder `whsec_disabled_pending_valid_...`.
#   Prefix checks cannot detect a typo inside the body. Removing the typing is the fix.
#
# WHAT IT DOES
#   Reads KEY=VALUE lines from RUNTIME_SECRETS_FILE (staged over SSH at mode 0600) and applies
#   each into PRODUCTION_ENV_FILE, replacing the existing line or appending a new one. Prints
#   `changed` or `unchanged` — and NOTHING ELSE, ever: this runs with the secrets in hand, so a
#   stray echo would put them in a public Actions log.
#
#   The caller uses that word. A container only re-reads its environment when it is recreated, so
#   a selective deploy that happens not to include the billing service would leave the old value
#   running and report success. `changed` promotes the deploy to full, which is the step everyone
#   forgets when they edit the file by hand.
#
# WHAT IT DOES NOT DO
#   Delete keys, or write empty values. A secret that is not configured in GitHub arrives here as
#   an empty string, and the correct reading of that is "this deployment has nothing to say about
#   that key" — not "erase it". Blanking JWT_SECRET because a secret was renamed would take the
#   whole platform down.

set -eu

: "${PRODUCTION_ENV_FILE:?PRODUCTION_ENV_FILE is required}"
: "${RUNTIME_SECRETS_FILE:?RUNTIME_SECRETS_FILE is required}"

fail() {
  echo "apply-runtime-secrets: $*" >&2
  exit 1
}

[ -f "$PRODUCTION_ENV_FILE" ] || fail "production environment file is missing"
[ ! -L "$PRODUCTION_ENV_FILE" ] || fail "production environment must not be a symlink"
[ -r "$RUNTIME_SECRETS_FILE" ] || fail "runtime secrets file is not readable"
[ ! -L "$RUNTIME_SECRETS_FILE" ] || fail "runtime secrets file must not be a symlink"

env_dir="$(dirname "$PRODUCTION_ENV_FILE")"
changed=false
cr="$(printf '\r')"

# The last assignment wins, matching how the file is read: `. file` in deploy-release.sh and
# --env-file in compose both take the final one.
current_value() {
  sed -n "s/^$1=//p" "$PRODUCTION_ENV_FILE" | tail -n 1
}

# awk rather than sed: a secret is arbitrary text and will contain the characters sed treats as
# replacement syntax — & is literal in Stripe keys and / appears in base64. The value reaches awk
# through the environment, never through -v (which expands backslash escapes) and never through
# the program text.
apply_one() {
  key="$1"
  value="$2"
  tmp="$(mktemp "$env_dir/.env.production.XXXXXX")"

  if RUNTIME_SECRET_VALUE="$value" awk -v key="$key" '
      BEGIN { written = 0 }
      index($0, key "=") == 1 {
        if (!written) { print key "=" ENVIRON["RUNTIME_SECRET_VALUE"]; written = 1 }
        next
      }
      { print }
      END { if (!written) print key "=" ENVIRON["RUNTIME_SECRET_VALUE"] }
    ' "$PRODUCTION_ENV_FILE" >"$tmp"
  then
    # 0600 before the move, not after: between a world-readable rename and a later chmod there is
    # a window in which the file holds every credential the platform has.
    chmod 0600 "$tmp"
    mv "$tmp" "$PRODUCTION_ENV_FILE"
  else
    rm -f "$tmp"
    fail "could not rewrite the production environment file"
  fi
}

while IFS= read -r line || [ -n "$line" ]; do
  # Tolerate CRLF, which is what a value pasted through a Windows editor arrives as. An invisible
  # carriage return on the end of a secret is precisely the class of defect this script exists to
  # remove — it would be applied, pass every prefix check, and be rejected by Stripe.
  line="${line%"$cr"}"
  [ -n "$line" ] || continue

  key="${line%%=*}"
  value="${line#*=}"

  case "$key" in
    [A-Z]*) ;;
    *) fail "runtime secret name is not an environment key" ;;
  esac
  # Checked against the full name, not just the first character: a key carrying a space or a quote
  # would produce a line the env file parser reads as something else entirely.
  printf '%s' "$key" | grep -Eq '^[A-Z][A-Z0-9_]*$' || fail "runtime secret name is not an environment key"

  # An unset GitHub secret arrives empty. Leave whatever the host already has.
  [ -n "$value" ] || continue

  if [ "$(current_value "$key")" = "$value" ]; then
    echo "apply-runtime-secrets: $key is already current" >&2
    continue
  fi

  apply_one "$key" "$value"
  changed=true
  echo "apply-runtime-secrets: updated $key" >&2
done <"$RUNTIME_SECRETS_FILE"

if [ "$changed" = "true" ]; then
  echo changed
else
  echo unchanged
fi
