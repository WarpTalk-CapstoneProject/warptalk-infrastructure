#!/bin/sh
# Behavioural contract for scripts/deploy-k3s-release.sh's online path, with kubectl and Helm
# replaced by recording stubs (no cluster, no Docker for the stubs themselves). It pins the release
# order that the 24 Sep outages broke:
#
#   1. migrations run as their own Job BEFORE `helm upgrade`; a failed migration stops the release
#      with nothing rolled (no upgrade, no rollback);
#   2. `helm upgrade` runs with --wait and never --atomic;
#   3. a failed upgrade or failed acceptance rolls back to the last DEPLOYED revision, never to a
#      failed one;
#   4. a release left pending-* by an interrupted run is refused before anything changes;
#   5. the rollout surges when the App node has room for one more pod of the largest workload, and
#      replaces in place only when it has not.
#
# REAL_HELM renders the chart (default: the locked Helm, which needs Docker; CI has it).
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
infra_root="$(CDPATH='' cd -- "$script_dir/.." && pwd)"
matrix="$infra_root/deploy/production/image-matrix.json"
REAL_HELM="${REAL_HELM:-$script_dir/helm-locked.sh}"
# Absolute, resolved before the stubs go first on PATH (a bare `helm` would find the stub itself).
REAL_HELM="$(command -v "$REAL_HELM")" || {
  echo "release gate contract: cannot find $REAL_HELM" >&2
  exit 1
}
# The stubs below go first on PATH for the deploy script. Chart rendering must NOT see them: the
# locked Helm (helm-locked.sh) runs through `docker`, and on the CI runner it found the kubeconform
# stub instead, rendered nothing, and the gate failed with "could not render the migration Job".
# So `helm template` runs with the caller's PATH, and without the fake KUBECONFIG (helm-locked.sh
# would try to mount it).
REAL_PATH="$PATH"
export REAL_HELM REAL_PATH

work="$(mktemp -d "${TMPDIR:-/tmp}/warptalk-release-gate.XXXXXX")"
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/bin"

jq '{
  schemaVersion: 1,
  tag: "prod-20260924-gate-contract",
  images: [
    .images[] | {
      service,
      ref: ("ghcr.io/warptalk/" + .name + ":gatecontract01"),
      digest: ("sha256:" + ("1" * 64))
    }
  ]
}' "$matrix" >"$work/manifest.json"

# --- stubs --------------------------------------------------------------------------------------
cat >"$work/bin/docker" <<'EOF'
#!/bin/sh
# kubeconform only; the offline half of the deploy script is covered by test-k3s-release-contract.sh.
# Anything else reaching this stub is a wiring bug in the test: fail loudly, never render nothing.
case "$*" in
  *kubeconform*) cat >/dev/null ;;
  *) echo "release gate stub docker: unexpected call: $*" >&2; exit 97 ;;
esac
EOF

cat >"$work/bin/kubectl" <<'EOF'
#!/bin/sh
log="$FAKE_LOG"
case "$*" in
  "version -o json") echo '{"serverVersion":{"minor":"31"}}' ;;
  "get clustersecretstore "*) echo '{"status":{"conditions":[{"type":"Ready","status":"True"}]}}' ;;
  "auth can-i "*) echo yes ;;
  "get serviceaccount "*) exit 1 ;;
  "get secret warptalk-runtime "*) exit 1 ;;
  "delete job "*) echo "kubectl delete-job" >>"$log" ;;
  "apply "*) echo "kubectl apply-migration-gate" >>"$log" ;;
  "get job "*)
    if [ "$FAKE_MIGRATION" = ok ]; then
      echo '{"status":{"succeeded":1}}'
    else
      echo '{"status":{"conditions":[{"type":"Failed","status":"True"}]}}'
    fi
    ;;
  "logs "*) echo "fake migration log" ;;
  "get nodes "*)
    printf '{"items":[{"metadata":{"name":"app-1"},"status":{"allocatable":{"memory":"%s","cpu":"8"}}}]}\n' \
      "$FAKE_NODE_MEMORY"
    ;;
  "get pods "*) echo '{"items":[]}' ;;
  "wait "*) echo "kubectl wait" >>"$log"; exit 1 ;;
  *) exit 0 ;;
esac
EOF

cat >"$work/bin/helm" <<'EOF'
#!/bin/sh
log="$FAKE_LOG"
case "$1" in
  template) exec env -u KUBECONFIG PATH="$REAL_PATH" "$REAL_HELM" "$@" ;;
  status) [ -n "$FAKE_HELM_HISTORY" ] ;;
  history) printf '%s\n' "$FAKE_HELM_HISTORY" ;;
  upgrade)
    echo "helm upgrade $*" >>"$log"
    last_values=""
    previous=""
    for argument in "$@"; do
      [ "$previous" = "-f" ] && last_values="$argument"
      previous="$argument"
    done
    printf 'helm upgrade rollout-values: %s\n' "$(tr '\n' ' ' <"$last_values")" >>"$log"
    exit "$FAKE_HELM_UPGRADE_EXIT"
    ;;
  rollback) echo "helm rollback $2 $3" >>"$log" ;;
  uninstall) echo "helm uninstall" >>"$log" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$work/bin/docker" "$work/bin/kubectl" "$work/bin/helm"

# Fail fast, and say why, if the real Helm cannot render the chart here at all.
"$work/bin/helm" template warptalk "$infra_root/deploy/k3s/chart" --namespace warptalk \
  --set migrations.mode=job \
  --set global.releaseId=gate-preflight \
  --show-only templates/migration-job.yaml 2>"$work/preflight.err" |
  grep -q '^  name: warptalk-migrations-gate-preflight' || {
  echo "release gate contract: $REAL_HELM cannot render the chart:" >&2
  cat "$work/preflight.err" >&2
  exit 1
}

HISTORY_WITH_FAILURES='[{"revision":3,"status":"superseded"},{"revision":4,"status":"deployed"},{"revision":5,"status":"failed"},{"revision":6,"status":"failed"}]'

# run <name> <migration ok|fail> <upgrade exit> <node memory> <history json>
run() {
  FAKE_LOG="$work/$1.log"
  : >"$FAKE_LOG"
  if PATH="$work/bin:$PATH" \
    FAKE_LOG="$FAKE_LOG" \
    FAKE_MIGRATION="$2" \
    FAKE_HELM_UPGRADE_EXIT="$3" \
    FAKE_NODE_MEMORY="$4" \
    FAKE_HELM_HISTORY="$5" \
    REAL_HELM="$REAL_HELM" \
    K3S_HELM_COMMAND="$work/bin/helm" \
    KUBECONFIG=/dev/null \
    RELEASE_MANIFEST="$work/manifest.json" \
    K3S_VALUES_FILE="$infra_root/deploy/k3s/k8s-app-values.yaml" \
    K3S_SECRET_SOURCE=external-secrets \
    K3S_SECRET_STORE_NAME=warptalk-production-secret-store \
    K3S_STORAGE_CLASS=local-path \
    K3S_TLS_SECRET_NAME=warptalk-tls \
    K3S_DOMAIN=app.warptalk.io.vn \
    "$script_dir/deploy-k3s-release.sh" >"$work/$1.out" 2>&1; then
    echo pass
  else
    echo fail
  fi
}

fail() {
  echo "release gate contract: $*" >&2
  for file in "$work"/*.log "$work"/*.out; do
    [ -s "$file" ] && { echo "--- $file" >&2; tail -n 30 "$file" >&2; }
  done
  exit 1
}

# 1. A failed migration stops the release before Helm touches anything.
[ "$(run migration-fails fail 0 64Gi "$HISTORY_WITH_FAILURES")" = fail ] ||
  fail "a failed migration did not fail the release"
grep -Fq "kubectl apply-migration-gate" "$work/migration-fails.log" ||
  fail "the migration gate Job was never applied"
if grep -Eq '^helm (upgrade|rollback|uninstall)' "$work/migration-fails.log"; then
  fail "a failed migration must leave the release untouched (no upgrade, no rollback)"
fi
grep -Fq "nothing was rolled" "$work/migration-fails.out" ||
  fail "a failed migration must say that nothing was rolled"
grep -Fq "fake migration log" "$work/migration-fails.out" ||
  fail "a failed migration must print the migrator's logs"

# 2 + 3. Migrations first, then `helm upgrade --wait` (never --atomic); a failed upgrade goes back
# to revision 4, the last DEPLOYED one - not 6 or 5, which failed.
[ "$(run upgrade-fails ok 1 64Gi "$HISTORY_WITH_FAILURES")" = fail ] ||
  fail "a failed helm upgrade did not fail the release"
first_gate="$(grep -n "apply-migration-gate" "$work/upgrade-fails.log" | head -n 1 | cut -d: -f1)"
first_upgrade="$(grep -n "^helm upgrade " "$work/upgrade-fails.log" | head -n 1 | cut -d: -f1)"
[ -n "$first_gate" ] && [ -n "$first_upgrade" ] && [ "$first_gate" -lt "$first_upgrade" ] ||
  fail "migrations must complete before helm upgrade starts"
grep "^helm upgrade " "$work/upgrade-fails.log" | grep -Fq -- "--wait" ||
  fail "helm upgrade must --wait"
if grep "^helm upgrade " "$work/upgrade-fails.log" | grep -Fq -- "--atomic"; then
  fail "helm upgrade must not use --atomic; the script rolls back itself, to a known revision"
fi
grep -Fxq "helm rollback warptalk 4" "$work/upgrade-fails.log" ||
  fail "a failed upgrade must roll back to the last DEPLOYED revision (4)"

# 3. Acceptance failing after a good upgrade rolls back to the same revision.
[ "$(run acceptance-fails ok 0 64Gi "$HISTORY_WITH_FAILURES")" = fail ] ||
  fail "failed acceptance did not fail the release"
grep -Fxq "helm rollback warptalk 4" "$work/acceptance-fails.log" ||
  fail "failed acceptance must roll back to the last DEPLOYED revision (4)"

# 3b. Production's history on 24 Sep: the latest revision is FAILED (not pending) - rev 8's upgrade
# and the manual rollback to 4 (rev 9) both hit "context deadline exceeded" - and the only DEPLOYED
# revision is 3. A failed latest revision must not block the release: it upgrades from it, and a
# failure goes back to 3, never to 9, 8 or the superseded 4.
PROD_HISTORY='[{"revision":3,"status":"deployed"},{"revision":4,"status":"superseded"},{"revision":5,"status":"failed"},{"revision":6,"status":"failed"},{"revision":7,"status":"failed"},{"revision":8,"status":"failed"},{"revision":9,"status":"failed"}]'
[ "$(run latest-failed-ok ok 0 64Gi "$PROD_HISTORY")" = fail ] ||
  fail "the stubbed acceptance always fails; this scenario must end in a rollback"
grep -q "^helm upgrade " "$work/latest-failed-ok.log" ||
  fail "a latest-FAILED revision must not block the upgrade"
grep -Fxq "helm rollback warptalk 3" "$work/latest-failed-ok.log" ||
  fail "with rev 9 failed, the rollback target must be rev 3, the last DEPLOYED revision"
[ "$(run latest-failed-upgrade-fails ok 1 64Gi "$PROD_HISTORY")" = fail ] ||
  fail "a failed upgrade over a failed latest revision did not fail the release"
grep -Fxq "helm rollback warptalk 3" "$work/latest-failed-upgrade-fails.log" ||
  fail "a failed upgrade over a failed latest revision must roll back to rev 3"
if grep -Eq '^helm rollback warptalk (4|8|9)$' "$work/latest-failed-upgrade-fails.log"; then
  fail "rolled back to a superseded or failed revision"
fi

# 4. A release left pending by an interrupted run is refused before anything changes.
[ "$(run pending ok 0 64Gi '[{"revision":4,"status":"deployed"},{"revision":5,"status":"pending-upgrade"}]')" = fail ] ||
  fail "a pending-upgrade release was not refused"
if grep -Eq 'apply-migration-gate|^helm (upgrade|rollback)' "$work/pending.log"; then
  fail "a pending release must be refused before the migration gate and the upgrade"
fi
grep -Fq "helm rollback warptalk 4" "$work/pending.out" ||
  fail "the pending-release message must name the last deployed revision to restore"

# 4b. No deployed revision at all: nothing to roll back to, so do not start.
[ "$(run no-deployed ok 0 64Gi '[{"revision":1,"status":"failed"}]')" = fail ] ||
  fail "a release with no DEPLOYED revision was upgraded without a rollback target"

# 5. Rollout shape from measured headroom.
run surge ok 0 64Gi "$HISTORY_WITH_FAILURES" >/dev/null
grep -Fq "surge rollout (maxSurge 1 / maxUnavailable 0)" "$work/surge.out" ||
  fail "with room on the App node the release must surge"
if grep -Fq "maxSurge: 0" "$work/surge.log"; then
  fail "with room on the App node the release must not replace pods in place"
fi
run in-place ok 0 256Mi "$HISTORY_WITH_FAILURES" >/dev/null
grep "rollout-values:" "$work/in-place.log" | grep -Fq "maxSurge: 0, maxUnavailable: 1" ||
  fail "with no room for one more pod the release must replace pods in place"
grep -Fq "::warning::" "$work/in-place.out" ||
  fail "an in-place release must announce itself"

echo "K3s release gate contract: PASS"
