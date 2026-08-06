#!/usr/bin/env bash
# Proves scripts/check-demo-flows-contract.mjs actually fires.
#
# A checker nobody has seen fail is indistinguishable from a checker that
# always passes. This builds a throwaway pair of fake sibling repos, breaks one
# claim at a time, and asserts the checker fails AND names the right thing.
#
# Both directions are covered, because only one of them is intuitive:
#   * a positive claim ("this route exists") when the route is deleted
#   * a negative claim ("nothing calls this") when something starts calling it
#
# Runs in about a second and touches neither the real document nor the real
# sibling repositories.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT_DIR/scripts/check-demo-flows-contract.mjs"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

failures=0

# --- fixture: two minimal sibling repos -------------------------------------

WEB="$WORK/warptalk-web"
BACKEND="$WORK/warptalk-backend"
mkdir -p "$WEB/.git" "$BACKEND/.git"
mkdir -p "$WEB/src/app/(app)/voice-profiles" "$WEB/src/hooks" "$WEB/src/app/(app)/members"
mkdir -p "$BACKEND/svc/Controllers"

echo 'export default function Page() { return null; }' \
  >"$WEB/src/app/(app)/voice-profiles/page.tsx"
echo 'export default function Page() { return null; }' \
  >"$WEB/src/app/(app)/members/page.tsx"
echo 'export function useChangeWorkspaceMemberRole(id: string) { return id; }' \
  >"$WEB/src/hooks/use-workspace.ts"

cat >"$BACKEND/svc/Controllers/WorkspaceMembersController.cs" <<'CS'
[ApiController]
[Route("api/v1/workspaces")]
public class WorkspaceMembersController : ControllerBase
{
    [HttpPut("{workspaceId:guid}/members/{userId:guid}/role")]
    public async Task<IActionResult> ChangeMemberRole() => Ok();
}
CS

# --- fixture: a miniature document and its contract -------------------------

DOC="$WORK/DEMO-FLOWS.md"
cat >"$DOC" <<'MD'
# Fixture

1. Voice profiles live at `/voice-profiles`.
2. Role change: `PUT .../members/{userId}/role` exists but
   **Đổi role member chưa có trên giao diện.**
MD

CONTRACT="$WORK/contract.json"
cat >"$CONTRACT" <<'JSON'
{
  "requires": ["web", "backend"],
  "claims": [
    {
      "id": "fixture.route",
      "anchor": "`/voice-profiles`",
      "claim": "The voice profiles page exists",
      "covers": ["/voice-profiles"],
      "check": { "type": "route_exists", "route": "/voice-profiles" }
    },
    {
      "id": "fixture.endpoint",
      "anchor": "`PUT .../members/{userId}/role`",
      "claim": "The role endpoint exists in the backend",
      "covers": ["PUT .../members/{userId}/role"],
      "check": {
        "type": "endpoint_exists",
        "method": "PUT",
        "path": "/api/v1/workspaces/{workspaceId}/members/{userId}/role"
      }
    },
    {
      "id": "fixture.negative",
      "anchor": "**Đổi role member chưa có trên giao diện.**",
      "claim": "Nothing in the frontend calls the role-change hook",
      "check": {
        "type": "symbol_unused",
        "repo": "web",
        "subdir": "src",
        "symbol": "useChangeWorkspaceMemberRole",
        "definitions": 1
      }
    }
  ],
  "humanVerifyOnly": {}
}
JSON

run_checker() {
  DEMO_FLOWS_DOC="$DOC" \
  DEMO_FLOWS_CONTRACT="$CONTRACT" \
  WARPTALK_WEB_DIR="$WEB" \
  WARPTALK_BACKEND_DIR="$BACKEND" \
    node "$CHECKER" 2>&1
}

expect_pass() {
  local label="$1" out
  if out="$(run_checker)"; then
    echo "  ok   $label"
  else
    echo "  FAIL $label — expected the checker to pass, it did not:" >&2
    echo "$out" | sed 's/^/       /' >&2
    failures=$((failures + 1))
  fi
}

# expect_fail <label> <expected substring>...
expect_fail() {
  local label="$1"
  shift
  local out status=0
  out="$(run_checker)" || status=$?
  if [ "$status" -eq 0 ]; then
    echo "  FAIL $label — the checker PASSED on a broken claim." >&2
    failures=$((failures + 1))
    return
  fi
  local needle
  for needle in "$@"; do
    if ! printf '%s' "$out" | grep -qF -- "$needle"; then
      echo "  FAIL $label — failure message did not mention: $needle" >&2
      echo "$out" | sed 's/^/       /' >&2
      failures=$((failures + 1))
      return
    fi
  done
  echo "  ok   $label"
}

echo "demo-flows contract self-test"

# 1. The fixture starts consistent.
expect_pass "baseline: an unbroken contract passes"

# 2. POSITIVE claim broken: the document says the page exists; delete it.
mv "$WEB/src/app/(app)/voice-profiles/page.tsx" "$WORK/parked-page.tsx"
expect_fail "positive claim: deleted route is reported" \
  "DEMO-FLOWS.md:3" \
  "fixture.route" \
  "/voice-profiles"
mv "$WORK/parked-page.tsx" "$WEB/src/app/(app)/voice-profiles/page.tsx"

# 3. POSITIVE claim broken: the endpoint the document names is removed.
mv "$BACKEND/svc/Controllers/WorkspaceMembersController.cs" "$WORK/parked.cs"
expect_fail "positive claim: removed endpoint is reported" \
  "fixture.endpoint" \
  "PUT /api/v1/workspaces/{workspaceId}/members/{userId}/role"
mv "$WORK/parked.cs" "$BACKEND/svc/Controllers/WorkspaceMembersController.cs"

# 4. NEGATIVE claim broken: the document says nothing calls the hook, so wire
#    it up. This is the direction that rots silently in real life — the feature
#    gets built and the document goes on saying it does not exist.
mkdir -p "$WEB/src/app/(app)/members"
cat >"$WEB/src/app/(app)/members/role-menu.tsx" <<'TSX'
import { useChangeWorkspaceMemberRole } from "@/hooks/use-workspace";
export function RoleMenu({ id }: { id: string }) {
  const change = useChangeWorkspaceMemberRole(id);
  return change;
}
TSX
expect_fail "negative claim: newly-wired UI is reported" \
  "DEMO-FLOWS.md:5" \
  "fixture.negative" \
  "role-menu.tsx" \
  "now has 3 occurrence"
rm "$WEB/src/app/(app)/members/role-menu.tsx"

# 5. The contract must not be allowed to describe deleted document text.
cat >"$DOC" <<'MD'
# Fixture

1. Voice profiles live at `/voice-profiles`.
2. Role change: `PUT .../members/{userId}/role` exists.
MD
expect_fail "dangling anchor: contract entry with no document text is reported" \
  "fixture.negative" \
  "not there any more"
cat >"$DOC" <<'MD'
# Fixture

1. Voice profiles live at `/voice-profiles`.
2. Role change: `PUT .../members/{userId}/role` exists but
   **Đổi role member chưa có trên giao diện.**
MD

# 6. A route the document names but the contract ignores must be surfaced.
cat >>"$DOC" <<'MD'
3. Also open `/terminology` before the defence.
MD
expect_fail "uncovered mention: an unchecked route in the document is reported" \
  "/terminology" \
  "not in the contract"

# 7. A missing sibling repository must FAIL, never pass quietly.
MOVED="$WORK/moved-web"
mv "$WEB" "$MOVED"
out=""
status=0
out="$(run_checker)" || status=$?
if [ "$status" -eq 0 ]; then
  echo "  FAIL missing repo: the checker PASSED with warptalk-web absent." >&2
  failures=$((failures + 1))
elif printf '%s' "$out" | grep -qF "CANNOT RUN"; then
  echo "  ok   missing sibling repo fails loudly (exit $status)"
else
  echo "  FAIL missing repo: exited $status but without a clear message." >&2
  echo "$out" | sed 's/^/       /' >&2
  failures=$((failures + 1))
fi
mv "$MOVED" "$WEB"

if [ "$failures" -ne 0 ]; then
  echo "demo-flows contract self-test: $failures FAILED" >&2
  exit 1
fi

echo "demo-flows contract self-test: PASS"
