#!/bin/sh
# Produce a fail-closed deployment plan from the active and desired manifests.
set -eu

CURRENT_MANIFEST="${1:-}"
DESIRED_MANIFEST="${2:-}"
MATRIX_FILE="${MATRIX_FILE:-$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)/deploy/production/image-matrix.json}"
FORCE_FULL_DEPLOY="${FORCE_FULL_DEPLOY:-false}"

fail() {
  echo "release planner: $*" >&2
  exit 1
}

case "$FORCE_FULL_DEPLOY" in
  true|false) ;;
  *) fail "FORCE_FULL_DEPLOY must be true or false" ;;
esac

[ -r "$CURRENT_MANIFEST" ] || fail "current release manifest is not readable"
[ -r "$DESIRED_MANIFEST" ] || fail "desired release manifest is not readable"
[ -r "$MATRIX_FILE" ] || fail "image matrix is not readable"

jq -e '
  .schemaVersion == 1 and
  (.images | type == "array") and
  all(.images[];
    (.service | test("^[a-z0-9][a-z0-9-]*$")) and
    (.role == "app" or .role == "data" or .role == "infra" or .role == "none") and
    ((.triggersMigrations // false) | type == "boolean")
  )
' "$MATRIX_FILE" >/dev/null || fail "image matrix has invalid deployment roles"

jq -e '
  .schemaVersion == 1 and
  (.repositories["warptalk-infrastructure"].commit | type == "string") and
  (.images | type == "array") and
  all(.images[];
    (.service | test("^[a-z0-9][a-z0-9-]*$")) and
    (.digest | test("^sha256:[a-f0-9]{64}$"))
  )
' "$DESIRED_MANIFEST" >/dev/null || fail "desired release manifest is invalid"

jq -n \
  --slurpfile current "$CURRENT_MANIFEST" \
  --slurpfile desired "$DESIRED_MANIFEST" \
  --slurpfile matrix "$MATRIX_FILE" \
  --argjson force "$FORCE_FULL_DEPLOY" '
  def digest_map($manifest):
    reduce ($manifest.images // [])[] as $image
      ({}; .[$image.service] = $image.digest);
  def role_plan($role; $full; $old; $new):
    ([
      $matrix[0].images[] |
      select(.role == $role) |
      select(($old[.service] // "") != ($new[.service] // ""))
    ]) as $changed_entries |
    # Every container the changed image backs, not just the first one named. An image can run as
    # more than one service — the live translation worker and the post-meeting backfill worker are
    # the same code reading different streams — and leaving the others out of a selective deploy
    # keeps them on the previous digest while the release reports success.
    ([$changed_entries[] | ([.service] + (.alsoServices // []))[]] | unique | sort) as $changed |
    {
      deploy: ($full or ($changed | length > 0)),
      fullDeploy: $full,
      changedServices: (if $full then [] else $changed end),
      runMigrations: (
        $role == "app" and
        ($full or any($changed_entries[]; (.triggersMigrations // false) == true))
      )
    };

  $current[0] as $current_release |
  $desired[0] as $desired_release |
  digest_map($current_release) as $old |
  digest_map($desired_release) as $new |
  (
    $force or
    ($current_release.schemaVersion != 1) or
    (($current_release.repositories["warptalk-infrastructure"].commit // "") !=
      $desired_release.repositories["warptalk-infrastructure"].commit)
  ) as $full |
  {
    schemaVersion: 1,
    fullDeployReason:
      (if $force then "forced"
       elif $current_release.schemaVersion != 1 then "no-current-release"
       elif $full then "infrastructure-changed"
       else null
       end),
    roles: {
      data: role_plan("data"; $full; $old; $new),
      infra: role_plan("infra"; $full; $old; $new),
      app: role_plan("app"; $full; $old; $new)
    }
  }
' >"${DEPLOYMENT_PLAN_OUTPUT:-/dev/stdout}"
