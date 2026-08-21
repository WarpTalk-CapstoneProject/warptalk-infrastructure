#!/usr/bin/env node
/**
 * What went into a release, written down before it ships.
 *
 * WHY THIS EXISTS
 *   A release tag is a version number and nothing else. After dispatching one there was no
 *   answer to "what is in v139 that was not in v138" short of reading four repositories' git
 *   logs, so nobody knew what to test and the testing that did happen was whatever the person
 *   happened to remember asking for.
 *
 * WHERE THE BOUNDARY COMES FROM
 *   There are no git tags for releases — the version lives in the dispatch inputs and the run
 *   logs. What every release DOES leave behind is a merge commit on `main`:
 *
 *       Merge pull request #341 from WarpTalk-CapstoneProject/development
 *
 *   So "since the last release" is the range between the two most recent of those. That needs
 *   no tags, no API and no permissions, and it cannot drift out of step with what was actually
 *   promoted, because it IS what was promoted.
 *
 * WHY IT IS NOT A WORKFLOW STEP
 *   release.yml checks each repo out at a single SHA with the default fetch-depth of 1. There
 *   is no history in the runner to walk. Deepening four checkouts to write a changelog is a
 *   cost paid on every release for a file that can be produced here in a second.
 *
 * Usage:
 *   node scripts/release-notes.mjs --tag prod-20260821-something-v142
 *   node scripts/release-notes.mjs --tag <tag> --write     # also writes docs/releases/<tag>.md
 */

import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const infraRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const projectRoot = resolve(infraRoot, "..");

const REPOS = [
  ["warptalk-web", "Web"],
  ["warptalk-backend", "Backend"],
  ["warptalk-ai", "AI"],
  ["warptalk-infrastructure", "Infrastructure"],
];

/** Conventional-commit type → the heading a reader scans for. */
const SECTIONS = [
  ["feat", "New"],
  ["fix", "Fixed"],
  ["perf", "Faster"],
  ["chore", "Housekeeping"],
  ["docs", "Docs"],
  ["refactor", "Housekeeping"],
  ["test", "Housekeeping"],
];

function git(repo, args) {
  try {
    return execFileSync("git", args, { cwd: join(projectRoot, repo), encoding: "utf8" }).trim();
  } catch {
    return "";
  }
}

/**
 * The two most recent promotions of development onto main. The newest is this release; the one
 * before it is where the last release stopped.
 */
function promoteBoundary(repo) {
  const merges = git(repo, [
    "log", "origin/main", "--merges", "--first-parent",
    "--grep=from WarpTalk-CapstoneProject/development",
    "--format=%H", "-n", "2",
  ]).split("\n").filter(Boolean);
  if (merges.length === 0) return null;
  // Only one promotion ever: everything on main is new.
  return { to: merges[0], from: merges[1] ?? null };
}

function changesFor(repo) {
  const bounds = promoteBoundary(repo);
  if (!bounds) return [];
  const range = bounds.from ? `${bounds.from}..${bounds.to}` : bounds.to;
  const lines = git(repo, ["log", range, "--no-merges", "--format=%s"]).split("\n").filter(Boolean);

  return lines.map((subject) => {
    const match = /^(\w+)(?:\(([^)]*)\))?!?:\s*(.+)$/.exec(subject);
    return match
      ? { type: match[1].toLowerCase(), scope: match[2] ?? "", text: match[3] }
      : { type: "other", scope: "", text: subject };
  });
}

const args = process.argv.slice(2);
const tag = args[args.indexOf("--tag") + 1];
if (!tag || tag.startsWith("--")) {
  console.error("usage: release-notes.mjs --tag <release-tag> [--write]");
  process.exit(1);
}

const out = [`# ${tag}`, "", `_Generated ${new Date().toISOString().slice(0, 10)} from what was promoted to main._`, ""];
let total = 0;

for (const [repo, label] of REPOS) {
  const changes = changesFor(repo);
  if (changes.length === 0) continue;
  total += changes.length;

  out.push(`## ${label}`, "");
  const seen = new Set();
  for (const [type, heading] of SECTIONS) {
    const group = changes.filter((change) => change.type === type);
    if (group.length === 0) continue;
    if (!seen.has(heading)) {
      out.push(`**${heading}**`, "");
      seen.add(heading);
    }
    for (const change of group) {
      out.push(`- ${change.scope ? `\`${change.scope}\` ` : ""}${change.text}`);
    }
    out.push("");
  }
  const rest = changes.filter((change) => !SECTIONS.some(([type]) => type === change.type));
  if (rest.length > 0) {
    out.push("**Other**", "", ...rest.map((change) => `- ${change.text}`), "");
  }
}

if (total === 0) {
  out.push("_No commits between this promotion and the previous one._", "");
}

const markdown = out.join("\n");
console.log(markdown);

if (args.includes("--write")) {
  const target = join(infraRoot, "docs/releases", `${tag}.md`);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, markdown.endsWith("\n") ? markdown : `${markdown}\n`);
  console.error(`\nwrote docs/releases/${tag}.md`);
}
