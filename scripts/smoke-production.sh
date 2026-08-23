#!/bin/sh
# Post-deploy smoke checks, run ON the app host against the PUBLIC URLs.
#
# WHY THIS IS MORE THAN A CURL
#
# On 23 Aug 2026 release v168 finished deploying — every container healthy, the release
# directory switched — and this script then failed with:
#
#     curl: (28) Resolving timed out after 5001 milliseconds
#
# The domain's authoritative nameservers had stopped answering on port 53. Nothing was wrong
# with the images, the deploy or the app: with DNS bypassed, both endpoints answered 200 with a
# valid certificate. But the workflow reported `production: failure`, which reads as a broken
# release and invites a rollback — and a rollback cannot restore DNS. It would only take working
# code off production.
#
# So this script now answers two questions instead of one:
#
#   1. Is production serving?  — retried, because a single blip is not an answer.
#   2. If it is NOT reachable by name, is that the APP or the NAME? — proven, not guessed,
#      by re-running the same request against the loopback with the real hostname and SNI.
#
# It still FAILS when the site is unreachable: users cannot reach it either, and a release that
# ends with the product dark must not report success. What changes is that the log says which
# thing broke, so the next person does not spend half an hour rediscovering it.

set -eu

: "${APP_BASE_URL:?APP_BASE_URL is required}"
: "${API_BASE_URL:?API_BASE_URL is required}"

# Four tries over ~14s. Enough to ride out a resolver blip or a container finishing its first
# request, short enough that a genuinely dark site is reported promptly.
attempts="${SMOKE_ATTEMPTS:-4}"
retry_delay="${SMOKE_RETRY_DELAY:-3}"

fail() {
  echo "smoke-production: $*" >&2
  exit 1
}

host_of() {
  # scheme://host[:port]/path -> host
  printf '%s' "$1" | sed -e 's,^[a-zA-Z][a-zA-Z0-9+.-]*://,,' -e 's,[/?#].*$,,' -e 's,:.*$,,'
}

#: Set by `probe` so a caller can tell WHY the last attempt failed.
probe_exit=0
probe_status=000
probe_namelookup=0

probe() {
  url="$1"
  out="$2"
  probe_exit=0
  # -w writes the diagnosis; the body goes to $out for the callers that inspect it.
  meta="$(
    curl --silent --show-error --output "$out" \
      --write-out '%{http_code} %{time_namelookup}' \
      --connect-timeout 5 --max-time 20 \
      "$url" 2>/dev/null
  )" || probe_exit=$?
  probe_status="$(printf '%s' "$meta" | cut -d' ' -f1)"
  probe_namelookup="$(printf '%s' "$meta" | cut -d' ' -f2)"
  [ -n "$probe_status" ] || probe_status=000
  [ -n "$probe_namelookup" ] || probe_namelookup=0
  return 0
}

# Whether the last probe failed because the NAME could not be resolved.
#
# curl 6 is "couldn't resolve host". curl 28 is a timeout, which is ambiguous on its own — it is
# also what a hung server produces — so it only counts as DNS when name lookup never completed,
# which is exactly the v168 signature.
probe_was_dns() {
  case "$probe_exit" in
    6) return 0 ;;
    28)
      case "$probe_namelookup" in
        0|0.000000|0.000) return 0 ;;
      esac
      ;;
  esac
  return 1
}

# The same request, with the name pinned to this host. Proves the stack is serving even when the
# public name does not resolve — same hostname, so the same virtual host and the same certificate.
serves_on_loopback() {
  url="$1"
  host="$(host_of "$url")"
  curl --silent --output /dev/null --fail \
    --connect-timeout 5 --max-time 20 \
    --resolve "$host:443:127.0.0.1" \
    "$url" 2>/dev/null
}

# Runs one check until it passes, or reports what stopped it.
#
# `verify` is given the response body path and returns non-zero if the body is wrong; that
# distinction matters, because a wrong body is the app being broken and never worth retrying
# many times, whereas an unreachable name may simply be a blip.
check() {
  label="$1"
  url="$2"
  expect="$3"
  verify="${4:-}"

  body="$(mktemp "${TMPDIR:-/tmp}/warptalk-smoke.XXXXXX")"
  attempt=1
  while :; do
    probe "$url" "$body"
    if [ "$probe_exit" -eq 0 ] && [ "$probe_status" = "$expect" ]; then
      if [ -z "$verify" ] || "$verify" "$body"; then
        rm -f "$body"
        return 0
      fi
      rm -f "$body"
      fail "$label answered $expect with an unexpected body — the service is up and wrong."
    fi

    if [ "$attempt" -ge "$attempts" ]; then
      break
    fi
    echo "smoke-production: $label not ready (curl=$probe_exit http=$probe_status), retrying..." >&2
    attempt=$((attempt + 1))
    sleep "$retry_delay"
  done
  rm -f "$body"

  if probe_was_dns; then
    echo "smoke-production: $url did not RESOLVE (curl=$probe_exit, name lookup never completed)." >&2
    if serves_on_loopback "$url"; then
      cat >&2 <<EOF
smoke-production:
smoke-production:   THE DEPLOY IS FINE. THE DOMAIN IS NOT RESOLVING.
smoke-production:
smoke-production:   The same request served 200 over HTTPS on this host with the real
smoke-production:   hostname and certificate, reached via --resolve. So the release that
smoke-production:   just completed is running and correct; what is broken is DNS for
smoke-production:   $(host_of "$url").
smoke-production:
smoke-production:   Do NOT roll back — a rollback cannot restore DNS, and would take
smoke-production:   working code off production. Check the zone's nameservers:
smoke-production:     dig NS $(host_of "$url")
smoke-production:     dig @<each nameserver> SOA $(host_of "$url")
smoke-production:
EOF
    else
      echo "smoke-production: and it does not serve on loopback either — this is the app, not DNS." >&2
    fi
    exit 1
  fi

  fail "$label failed after $attempts attempts (curl=$probe_exit http=$probe_status)."
}

body_is_healthy() {
  grep -q '^Healthy$' "$1"
}

check "the web app" "$APP_BASE_URL/" 200
check "the API liveness probe" "$API_BASE_URL/health/live" 200 body_is_healthy
check "the API readiness probe" "$API_BASE_URL/health/ready" 200 body_is_healthy

# The protected route must reach the Gateway and reject an anonymous request, not return a proxy
# 404/502. Through `check` like the rest: it used to be a bare curl, which meant the one probe
# whose whole point is "the Gateway is really behind Caddy" was also the one that could not tell a
# DNS blip from a broken route.
check "the protected route" "$API_BASE_URL/api/v1/workspaces" 401

echo "Production smoke checks passed."
