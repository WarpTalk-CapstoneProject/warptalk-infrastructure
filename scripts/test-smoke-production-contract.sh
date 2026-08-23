#!/bin/sh
# Contract for smoke-production.sh.
#
# This script is the last word on whether a release worked, so the cases that matter are the ones
# where it is WRONG about that: a transient blip reported as a dead release, a DNS outage reported
# as a broken deploy, and — the opposite mistake, which is worse — a genuinely broken app reported
# as merely a name problem.
#
# Driven by a fake `curl` on PATH, so every failure mode is reproducible without a network.

set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
subject="$script_dir/smoke-production.sh"

work="$(mktemp -d "${TMPDIR:-/tmp}/warptalk-smoke-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT INT TERM

fail() {
  echo "test-smoke-production: $*" >&2
  exit 1
}

# The fake curl reads its behaviour from $work/mode and counts calls in $work/calls.
cat >"$work/curl" <<'FAKE'
#!/bin/sh
mode="$(cat "$FAKE_DIR/mode")"
echo x >>"$FAKE_DIR/calls"

# Which URL, and where the body goes.
out=/dev/null
url=""
resolving=false
prev=""
for arg in "$@"; do
  case "$prev" in
    --output) out="$arg" ;;
    --resolve) resolving=true ;;
  esac
  case "$arg" in
    http*) url="$arg" ;;
  esac
  prev="$arg"
done

emit_ok() {
  case "$url" in
    *health/live|*health/ready) printf 'Healthy\n' >"$out"; printf '200 0.004' ;;
    # The protected route is expected to REFUSE an anonymous caller — that is the pass.
    */api/v1/workspaces) : >"$out"; printf '401 0.004' ;;
    *) printf 'ok\n' >"$out"; printf '200 0.004' ;;
  esac
  exit 0
}

case "$mode" in
  ok) emit_ok ;;
  dns_but_serving)
    # Public name dead; the loopback probe (--resolve) succeeds.
    if [ "$resolving" = true ]; then exit 0; fi
    printf '000 0.000000'
    exit 28
    ;;
  dns_and_dead)
    if [ "$resolving" = true ]; then exit 7; fi
    printf '000 0.000000'
    exit 6
    ;;
  hung_server)
    # Resolves fine, then the server never answers: curl 28, but name lookup DID complete.
    # This is the other half of what exit 28 can mean, and it is not a DNS story.
    if [ "$resolving" = true ]; then exit 28; fi
    printf '000 0.021'
    exit 28
    ;;
  app_down)
    # Resolves fine, server refuses the connection. NOT a DNS story.
    printf '000 0.031'
    exit 7
    ;;
  flaky_then_ok)
    if [ "$(wc -l <"$FAKE_DIR/calls")" -le 2 ]; then
      printf '000 0.000000'
      exit 28
    fi
    emit_ok
    ;;
  wrong_body)
    printf 'Unhealthy\n' >"$out"
    printf '200 0.004'
    exit 0
    ;;
esac
FAKE
chmod +x "$work/curl"

run() {
  printf '%s' "$1" >"$work/mode"
  : >"$work/calls"
  FAKE_DIR="$work" PATH="$work:$PATH" \
    APP_BASE_URL=https://app.example.test \
    API_BASE_URL=https://api.example.test \
    SMOKE_ATTEMPTS=3 SMOKE_RETRY_DELAY=0 \
    "$subject" >"$work/out" 2>"$work/err"
}

# ── a healthy release passes ──────────────────────────────────────────────
run ok || fail "a healthy production must pass"
grep -q "Production smoke checks passed." "$work/out" ||
  fail "a passing run must say so"

# ── a blip is not a dead release ──────────────────────────────────────────
# The whole reason for retrying: one failed resolve used to end the release.
run flaky_then_ok || fail "a transient failure that clears must not fail the release"

# ── DNS down, app fine: fail, but say WHICH ───────────────────────────────
if run dns_but_serving; then
  fail "an unreachable production must still fail — users cannot reach it either"
fi
grep -q "did not RESOLVE" "$work/err" ||
  fail "a name-resolution failure must be named as one"
grep -q "THE DEPLOY IS FINE" "$work/err" ||
  fail "when the app serves on loopback, the log must say the deploy is fine"
grep -q "Do NOT roll back" "$work/err" ||
  fail "the log must warn against the rollback that cannot help"

# ── DNS down AND app down: must NOT claim the deploy is fine ──────────────
# The dangerous inversion. Saying "the deploy is fine" over a broken app would send the next
# person looking at a registrar while production is actually down.
if run dns_and_dead; then
  fail "a dead app must fail"
fi
grep -q "this is the app, not DNS" "$work/err" ||
  fail "a dead app must be reported as the app"
grep -q "THE DEPLOY IS FINE" "$work/err" &&
  fail "must never claim the deploy is fine when the app does not serve"

# ── a HUNG server is not a DNS story either ──────────────────────────────
# curl 28 is a timeout, and a timeout is exactly what an unresolvable name AND a hung server both
# produce. Only the name-lookup time tells them apart, so a hung server must not be blamed on DNS
# and must never be excused as "the deploy is fine".
if run hung_server; then
  fail "a hung server must fail"
fi
grep -q "did not RESOLVE" "$work/err" &&
  fail "a timeout AFTER a successful name lookup must not be blamed on DNS"
grep -q "THE DEPLOY IS FINE" "$work/err" &&
  fail "a hung server must never be reported as a healthy deploy"

# ── a refused connection is not a DNS story ──────────────────────────────
if run app_down; then
  fail "a refused connection must fail"
fi
grep -q "did not RESOLVE" "$work/err" &&
  fail "a connection refused after a successful lookup must not be blamed on DNS"

# ── 200 with the wrong body is the app being up and wrong ────────────────
if run wrong_body; then
  fail "a health endpoint answering 200 with a bad body must fail"
fi
grep -q "unexpected body" "$work/err" ||
  fail "a wrong body must be reported as a wrong body, not as unreachable"
# And it must not be retried: the service answered, it is simply wrong.
[ "$(wc -l <"$work/calls")" -le 2 ] ||
  fail "a wrong body must not be retried — the answer will not change"

echo "test-smoke-production: all contracts hold."
