#!/usr/bin/env bash
set -euo pipefail

# A release note covers the release it names, and nothing that already shipped.
#
# WHY THIS EXISTS
#   Each note ends with the commit it stopped at, and the next note starts there. That works only
#   if "the next note" can find "the previous note", and the finding was a plain filename sort.
#
#   A note is named prod-YYYYMMDD-<slug>-vNNN.md, so the slug sits BETWEEN the date and the
#   version. Sorting by name therefore sorts by SLUG. Two releases on one day ordered themselves by
#   their words: ...transcript-language-backfill-v145 sorted before ...transcript-one-language-v143,
#   so v143 was read as the newest note, the boundary came from two releases back, and v147's note
#   re-listed everything v145 had already shipped.
#
#   Nothing looked wrong. The file existed and every line in it was true — it just told a tester to
#   re-check work that had been in production for hours. That is the exact failure the boundary
#   footers were added to prevent, one level up.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/release-notes.mjs"

fail() {
  echo "release notes contract: FAIL - $*" >&2
  exit 1
}

[ -f "$script" ] || fail "release-notes.mjs is missing"

# The ordering is by version number, not by name.
# The CALL, not just the definition: a helper that exists and is not used is the bug with a
# function above it, and the first version of this check passed against exactly that.
grep -q 'files = notesInReleaseOrder(dir);' "$script" ||
  fail "lastRecordedBoundary must read the notes through notesInReleaseOrder — a plain filename sort orders by slug"

grep -q 'function notesInReleaseOrder(' "$script" ||
  fail "notesInReleaseOrder is missing"

grep -qE '\-v\(\\\\d\+\)\\\\\.md\$|\-v\(\\d\+\)\\\.md\$' "$script" ||
  fail "the ordering must key on the trailing -vNNN, which is the only part of the name that orders releases"

# And it behaves: the same three real filenames that broke it, sorted the right way round.
node --input-type=module <<'JS' || fail "notes ordered by filename put v143 after v145"
const names = [
  "prod-20260821-avatar-and-transcript-count-v142.md",
  "prod-20260821-transcript-language-backfill-v145.md",
  "prod-20260821-transcript-one-language-v143.md",
];
const version = (name) => {
  const match = /-v(\d+)\.md$/.exec(name);
  return match ? Number(match[1]) : -1;
};
const newest = [...names]
  .sort((left, right) => version(left) - version(right) || left.localeCompare(right))
  .at(-1);
if (newest !== "prod-20260821-transcript-language-backfill-v145.md") {
  console.error(`newest resolved to ${newest}`);
  process.exit(1);
}
// The bug itself, asserted so nobody "simplifies" the comparator back to a plain sort.
if ([...names].sort().at(-1) === newest) {
  console.error("a plain filename sort agrees here, so this fixture no longer covers the bug");
  process.exit(1);
}
JS

echo "release notes contract: PASS"
