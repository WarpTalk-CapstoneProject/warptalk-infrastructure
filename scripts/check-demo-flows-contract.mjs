#!/usr/bin/env node
// Verifies that demo/DEMO-FLOWS.md still matches the product code.
//
// DEMO-FLOWS.md is the script the team reads on stage at the capstone defence.
// Every claim in it that a machine can check is listed in
// demo/DEMO-FLOWS.contract.json, and this script runs those checks in BOTH
// directions:
//
//   * a claim that says something EXISTS and it does not  -> fail
//   * a claim that says something DOES NOT exist and it does -> fail
//
// The second direction is the one that matters. Negative claims ("no UI calls
// this", "polls have no UI") rot silently and in the dangerous direction: if
// someone wires the feature up, the document still says it is missing and the
// team undersells what they built. Nothing in the normal process ever prompts
// anyone to re-check a negative claim, which is exactly why a machine does.
//
// The contract lives beside the document rather than inside it, so the document
// stays readable prose. To stop the two drifting apart, every contract entry
// carries an `anchor`: an exact substring that must still appear in the
// document. Delete or reword the line and the anchor check fails, forcing
// whoever changed the document to revisit the claim.
//
// Dependencies: none. Node built-ins only, matching the house style in
// scripts/check-translation-room-language-seed.mjs and the sibling repos'
// scripts/check-*-contract.mjs.
//
// Usage:
//   ./scripts/check-demo-flows-contract.mjs
//   WARPTALK_WEB_DIR=... WARPTALK_BACKEND_DIR=... ./scripts/check-demo-flows-contract.mjs
//   DEMO_FLOWS_DOC=... DEMO_FLOWS_CONTRACT=...   (used by the self-test)

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join, resolve, dirname, relative } from "node:path";
import { fileURLToPath } from "node:url";

const INFRA_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SIBLINGS = resolve(INFRA_ROOT, "..");

const DOC_PATH =
  process.env.DEMO_FLOWS_DOC || join(INFRA_ROOT, "demo", "DEMO-FLOWS.md");
const CONTRACT_PATH =
  process.env.DEMO_FLOWS_CONTRACT ||
  join(INFRA_ROOT, "demo", "DEMO-FLOWS.contract.json");

const REPOS = {
  web: process.env.WARPTALK_WEB_DIR || join(SIBLINGS, "warptalk-web"),
  backend: process.env.WARPTALK_BACKEND_DIR || join(SIBLINGS, "warptalk-backend"),
};

// ---------------------------------------------------------------------------
// Sibling repositories: absent means FAIL, never a quiet pass.
// ---------------------------------------------------------------------------

function requireRepos(needed) {
  const missing = [];
  for (const name of needed) {
    const dir = REPOS[name];
    // A path that exists but is not a checkout of the repo is just as useless.
    if (!existsSync(dir) || !existsSync(join(dir, ".git"))) {
      missing.push([name, dir]);
    }
  }
  if (missing.length === 0) return;

  console.error("\nDEMO-FLOWS contract: CANNOT RUN\n");
  for (const [name, dir] of missing) {
    const envVar = `WARPTALK_${name.toUpperCase()}_DIR`;
    console.error(
      `  warptalk-${name} is not checked out at: ${dir}\n` +
        `    override with ${envVar}=/path/to/warptalk-${name}`,
    );
  }
  console.error(
    "\nThe document makes claims about that code, so without it these checks\n" +
      "prove nothing. This exits non-zero rather than passing quietly.\n" +
      "In CI the sibling repos are checked out beside warptalk-infrastructure\n" +
      "by .github/workflows/demo-flows-contract.yml.\n",
  );
  process.exit(2);
}

// ---------------------------------------------------------------------------
// Source scanning
// ---------------------------------------------------------------------------

const SKIP_DIRS = new Set([
  ".git", "node_modules", ".next", "dist", "build", "out",
  "bin", "obj", "coverage", ".turbo", ".vercel", ".vs", "TestResults",
]);

function walk(dir, exts, acc = []) {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return acc;
  }
  for (const e of entries) {
    if (SKIP_DIRS.has(e.name)) continue;
    const full = join(dir, e.name);
    if (e.isDirectory()) walk(full, exts, acc);
    else if (exts.some((x) => e.name.endsWith(x))) acc.push(full);
  }
  return acc;
}

const fileCache = new Map();
function read(path) {
  if (!fileCache.has(path)) {
    try {
      fileCache.set(path, readFileSync(path, "utf8"));
    } catch {
      fileCache.set(path, null);
    }
  }
  return fileCache.get(path);
}

const listCache = new Map();
function sourceFiles(root, exts) {
  const key = `${root}|${exts.join(",")}`;
  if (!listCache.has(key)) listCache.set(key, walk(root, exts));
  return listCache.get(key);
}

/** Every `token` occurrence as file:line. `subdir` may name a directory or a single file. */
function findOccurrences(repo, subdir, exts, token) {
  const root = join(REPOS[repo], subdir);
  const re = new RegExp(`(?<![\\w$])${escapeRe(token)}(?![\\w$])`);
  const hits = [];
  const targets = /\.[a-z]+$/i.test(subdir) ? [root] : sourceFiles(root, exts);
  for (const file of targets) {
    const src = read(file);
    if (src === null || !src.includes(token)) continue;
    src.split("\n").forEach((line, i) => {
      if (re.test(line)) {
        hits.push(`${relative(REPOS[repo], file)}:${i + 1}`);
      }
    });
  }
  return hits.sort();
}

function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// ---------------------------------------------------------------------------
// Next.js route resolution (warptalk-web, App Router under src/app)
// ---------------------------------------------------------------------------
//
// A URL segment comes from a directory name, except that route groups `(x)`
// and private folders `_x` contribute nothing to the URL. Dynamic segments
// `[x]` / `[...x]` are canonicalised to `[*]` on both sides of the comparison,
// so the contract can keep the document's own `[slug]` / `[id]` placeholders
// even though the directories are named `[workspaceSlug]` / `[id]`.

const PAGE_FILES = ["page.tsx", "page.ts", "page.jsx", "page.js"];

let webRoutesCache = null;
function webRoutes() {
  if (webRoutesCache) return webRoutesCache;
  const appRoot = join(REPOS.web, "src", "app");
  const map = new Map(); // canonical route -> relative file path
  for (const file of sourceFiles(appRoot, PAGE_FILES)) {
    if (!PAGE_FILES.includes(file.split("/").pop())) continue;
    const rel = relative(appRoot, file);
    const segments = rel.split("/").slice(0, -1).filter((s) => {
      if (/^\(.*\)$/.test(s)) return false; // route group
      if (s.startsWith("_")) return false; // private folder
      if (s.startsWith("@")) return false; // parallel route slot
      return true;
    });
    map.set(canonicalRoute("/" + segments.join("/")), relative(REPOS.web, file));
  }
  webRoutesCache = map;
  return map;
}

function canonicalRoute(route) {
  const parts = route
    .split("?")[0]
    .split("#")[0]
    .split("/")
    .filter(Boolean)
    .map((s) => (/^\[.*\]$/.test(s) ? "[*]" : s));
  return "/" + parts.join("/");
}

// ---------------------------------------------------------------------------
// ASP.NET controller route resolution (warptalk-backend)
// ---------------------------------------------------------------------------
//
// Full path = class-level [Route("...")] + the action's [HttpX("...")] template.
// Route constraints are stripped, so `{workspaceId:guid}` and the document's
// `{workspaceId}` compare equal. Parameter NAMES are also dropped: the document
// writes `{id}` where the controller writes `{workspaceId}` and neither is
// more correct than the other.

let backendEndpointsCache = null;
function backendEndpoints() {
  if (backendEndpointsCache) return backendEndpointsCache;
  const found = new Map(); // "POST /api/v1/..." -> "file:line ActionName"
  for (const file of sourceFiles(REPOS.backend, [".cs"])) {
    const src = read(file);
    if (src === null || !src.includes("[Route(")) continue;
    const lines = src.split("\n");

    let classRoute = null;
    for (let i = 0; i < lines.length; i++) {
      const routeMatch = lines[i].match(/\[Route\("([^"]+)"\)\]/);
      // A [Route] directly above a class declaration is the controller prefix.
      if (routeMatch) {
        const lookahead = lines.slice(i + 1, i + 8).join(" ");
        if (/\bclass\s+\w+/.test(lookahead)) classRoute = routeMatch[1];
      }
      const verbMatch = lines[i].match(
        /\[Http(Get|Post|Put|Patch|Delete)(?:\("([^"]*)"\))?\]/,
      );
      if (!verbMatch || classRoute === null) continue;
      const method = verbMatch[1].toUpperCase();
      const template = verbMatch[2] ?? "";
      const full = [classRoute, template].filter(Boolean).join("/");
      // Name of the action method, for a useful failure message.
      const after = lines.slice(i + 1, i + 12).join("\n");
      const nameMatch = after.match(/\b(\w+)\s*\(/);
      found.set(`${method} ${normalizePath(full)}`, {
        at: `${relative(REPOS.backend, file)}:${i + 1}`,
        action: nameMatch ? nameMatch[1] : "?",
      });
    }
  }
  backendEndpointsCache = found;
  return found;
}

function normalizePath(p) {
  return (
    "/" +
    p
      .replace(/\{[^}]*\}/g, "{}") // {workspaceId:guid} and {id} both -> {}
      .split("/")
      .filter(Boolean)
      .join("/")
  ).toLowerCase();
}

function endpointKey(method, path) {
  return `${method.toUpperCase()} ${normalizePath(path)}`;
}

// ---------------------------------------------------------------------------
// Failure collection
// ---------------------------------------------------------------------------

const failures = [];
let checksRun = 0;

function fail(entry, actual, fix) {
  failures.push({ entry, actual, fix });
}

function pass() {
  checksRun += 1;
}

// ---------------------------------------------------------------------------
// Check implementations
// ---------------------------------------------------------------------------

const CHECKS = {
  // ---- routes ----------------------------------------------------------
  route_exists(entry, c) {
    const want = canonicalRoute(c.route);
    const file = webRoutes().get(want);
    if (file) return pass();
    fail(
      entry,
      `no page file resolves to ${c.route} in warptalk-web/src/app`,
      `Either the page was moved/deleted (fix the code, or fix the route in the document), ` +
        `or it was renamed — nearest existing routes: ${nearest(want)}`,
    );
  },

  route_absent(entry, c) {
    const want = canonicalRoute(c.route);
    const file = webRoutes().get(want);
    if (!file) return pass();
    fail(
      entry,
      `${c.route} NOW EXISTS at warptalk-web/${file}`,
      `The document says this page does not exist. It does now — update the document.`,
    );
  },

  // ---- backend endpoints ------------------------------------------------
  endpoint_exists(entry, c) {
    const key = endpointKey(c.method, c.path);
    const hit = backendEndpoints().get(key);
    if (hit) return pass();
    fail(
      entry,
      `no controller action serves ${c.method} ${c.path} in warptalk-backend`,
      `The document names this endpoint. Either it was renamed/removed in the backend, ` +
        `or the document's path is wrong.`,
    );
  },

  endpoint_absent(entry, c) {
    const key = endpointKey(c.method, c.path);
    const hit = backendEndpoints().get(key);
    if (!hit) return pass();
    fail(
      entry,
      `${c.method} ${c.path} NOW EXISTS at ${hit.at} (${hit.action})`,
      `The document says this endpoint does not exist. Update the document.`,
    );
  },

  // ---- "exists in code but nothing calls it" ----------------------------
  //
  // The workhorse for negative claims. A symbol that is defined but never
  // referenced anywhere else has exactly one occurrence in the tree. The
  // moment somebody imports it to build the UI, the count rises and this
  // fires — which is the whole point.
  symbol_unused(entry, c) {
    const hits = findOccurrences(
      c.repo || "web",
      c.subdir || "src",
      c.exts || [".ts", ".tsx"],
      c.symbol,
    );
    const expected = c.definitions ?? 1;
    if (hits.length === expected) return pass();
    if (hits.length < expected) {
      return fail(
        entry,
        `${c.symbol} has ${hits.length} occurrence(s), expected ${expected} ` +
          `(the definition). It looks DELETED.`,
        `The document describes this symbol as existing-but-unused. If it was ` +
          `removed, drop the claim from the document and this contract entry.`,
      );
    }
    fail(
      entry,
      `${c.symbol} now has ${hits.length} occurrence(s), expected ${expected}:\n` +
        hits.map((h) => `        warptalk-${c.repo || "web"}/${h}`).join("\n"),
      `The document says nothing calls this. Something does now — the feature ` +
        `has been wired up. Update the document (and stop under-selling it on stage).`,
    );
  },

  // ---- literal presence in one named file -------------------------------
  file_contains(entry, c) {
    const path = join(REPOS[c.repo], c.file);
    const src = read(path);
    if (src === null) {
      return fail(
        entry,
        `file not found: warptalk-${c.repo}/${c.file}`,
        `The file the claim depends on has moved. Re-point this contract entry.`,
      );
    }
    const missing = c.needles.filter((n) => !src.includes(n));
    if (missing.length === 0) return pass();
    fail(
      entry,
      `warptalk-${c.repo}/${c.file} no longer contains: ${missing
        .map((m) => JSON.stringify(m))
        .join(", ")}`,
      c.fix || `The behaviour the document describes has changed.`,
    );
  },

  file_lacks(entry, c) {
    const path = join(REPOS[c.repo], c.file);
    const src = read(path);
    if (src === null) {
      return fail(
        entry,
        `file not found: warptalk-${c.repo}/${c.file}`,
        `The file the claim depends on has moved. Re-point this contract entry.`,
      );
    }
    const present = c.needles.filter((n) => src.includes(n));
    if (present.length === 0) return pass();
    const where = present.map((n) => {
      const line = src.split("\n").findIndex((l) => l.includes(n)) + 1;
      return `${JSON.stringify(n)} at warptalk-${c.repo}/${c.file}:${line}`;
    });
    fail(
      entry,
      `these appeared and the document says they do not exist:\n` +
        where.map((w) => `        ${w}`).join("\n"),
      c.fix || `The document says this is absent. It is present now — update the document.`,
    );
  },

  // ---- the meeting-type table (6 rows x 5 claims) -----------------------
  meeting_type_matrix(entry, c) {
    const path = join(REPOS.backend, c.file);
    const src = read(path);
    if (src === null) {
      return fail(
        entry,
        `meeting-type policy not found at warptalk-backend/${c.file}`,
        `The backend source that drives the table has moved. Re-point this entry.`,
      );
    }

    // Named defaults, e.g. `Neutral = new(RequiresApproval: false, ...)`.
    const named = new Map();
    const namedRe =
      /(\w+)\s*=\s*\n?\s*new\(RequiresApproval:\s*(\w+),\s*MuteOnEntry:\s*(\w+),\s*AutoRecord:\s*(\w+),\s*BreakoutsEnabled:\s*(\w+),\s*MaxParticipants:\s*(\d+)\)/g;
    for (const m of src.matchAll(namedRe)) {
      named.set(m[1], {
        approval: m[2] === "true",
        muteOnEntry: m[3] === "true",
        autoRecord: m[4] === "true",
        breakout: m[5] === "true",
        seats: Number(m[6]),
      });
    }

    // `[TranslationRoomTypes.Webinar] = new(...)` or `... = Neutral,`
    const byType = new Map();
    const entryRe =
      /\[TranslationRoomTypes\.(\w+)\]\s*=\s*(?:\n\s*)?(?:new\(RequiresApproval:\s*(\w+),\s*MuteOnEntry:\s*(\w+),\s*AutoRecord:\s*(\w+),\s*BreakoutsEnabled:\s*(\w+),\s*MaxParticipants:\s*(\d+)\)|(\w+))/g;
    for (const m of src.matchAll(entryRe)) {
      if (m[7]) {
        if (named.has(m[7])) byType.set(m[1], named.get(m[7]));
      } else {
        byType.set(m[1], {
          approval: m[2] === "true",
          muteOnEntry: m[3] === "true",
          autoRecord: m[4] === "true",
          breakout: m[5] === "true",
          seats: Number(m[6]),
        });
      }
    }

    if (byType.size === 0) {
      return fail(
        entry,
        `could not parse any meeting-type defaults out of warptalk-backend/${c.file}`,
        `The shape of TranslationRoomTypePolicy.ByType changed. Update this parser ` +
          `rather than deleting the check — this table is 30 claims made on stage.`,
      );
    }

    const FIELDS = [
      ["approval", "approval-on-entry"],
      ["muteOnEntry", "mute-on-entry"],
      ["autoRecord", "auto-record"],
      ["breakout", "breakout"],
      ["seats", "seat count"],
    ];

    for (const [symbol, claimed] of Object.entries(c.rows)) {
      const actual = byType.get(symbol);
      if (!actual) {
        fail(
          entry,
          `meeting type TranslationRoomTypes.${symbol} is no longer configured ` +
            `in warptalk-backend/${c.file}`,
          `The document's table has a row for it. Either the type was removed ` +
            `(delete the row) or renamed (re-point this entry).`,
        );
        continue;
      }
      for (const [key, label] of FIELDS) {
        checksRun += 1;
        if (actual[key] !== claimed[key]) {
          checksRun -= 1;
          fail(
            entry,
            `meeting type ${symbol}: the table says ${label} = ` +
              `${JSON.stringify(claimed[key])}, backend says ` +
              `${JSON.stringify(actual[key])} (warptalk-backend/${c.file})`,
            `Fix whichever is wrong. A wrong cell here is a promise made to the ` +
              `panel that the product will not keep.`,
          );
        }
      }
    }
  },

  // ---- an exact set of string literals ----------------------------------
  //
  // Set equality, so it fires when an item is added AND when one is removed.
  //
  // `sources` lets one claim survive a refactor that moves the list to another
  // file: each candidate is tried until one actually yields values. Without
  // this, moving a list from a component to a shared registry would report
  // every value as "deleted" — a false alarm, and false alarms get checks
  // switched off.
  literal_set(entry, c) {
    const sources = c.sources || [
      { file: c.file, within: c.within, withinChars: c.withinChars, pattern: c.pattern },
    ];
    let found = null;
    let usedFile = null;
    const tried = [];

    for (const s of sources) {
      const src = read(join(REPOS[c.repo], s.file));
      tried.push(s.file);
      if (src === null) continue;
      if (s.within && !src.includes(s.within)) continue;
      const scope = s.within
        ? (src.split(s.within)[1] ?? "").slice(0, s.withinChars || 4000)
        : src;
      const hits = [...scope.matchAll(new RegExp(s.pattern, "g"))].map((m) => m[1]);
      if (hits.length > 0) {
        found = new Set(hits);
        usedFile = s.file;
        break;
      }
    }

    if (found === null) {
      return fail(
        entry,
        `could not find ${c.label} in any of: ` +
          tried.map((f) => `warptalk-${c.repo}/${f}`).join(", "),
        `The declaration this check reads has been refactored or moved — this is ` +
          `NOT necessarily a document error. Find where the list lives now and ` +
          `re-point the "sources" of this contract entry, then re-verify the claim.`,
      );
    }

    const want = new Set(c.values);
    const missing = [...want].filter((v) => !found.has(v));
    const extra = [...found].filter((v) => !want.has(v));
    if (missing.length === 0 && extra.length === 0) return pass();

    const parts = [];
    if (missing.length) parts.push(`GONE from the code: ${missing.join(", ")}`);
    if (extra.length) parts.push(`NEW in the code, not in the document: ${extra.join(", ")}`);
    fail(
      entry,
      `${c.label} in warptalk-${c.repo}/${usedFile} — ${parts.join("; ")}`,
      c.fix || `The document lists this set explicitly. Bring the two into step.`,
    );
  },
};

function nearest(route) {
  const all = [...webRoutes().keys()];
  const tail = route.split("/").pop();
  const close = all.filter((r) => r.includes(tail)).slice(0, 4);
  return close.length ? close.join(", ") : "(none similar)";
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

const doc = read(DOC_PATH);
if (doc === null) {
  console.error(`DEMO-FLOWS contract: document not found at ${DOC_PATH}`);
  process.exit(2);
}
const contract = JSON.parse(read(CONTRACT_PATH));
const docLines = doc.split("\n");

requireRepos(contract.requires || ["web", "backend"]);

// --- 1. anchors: every contract entry must still point at real document text.
//
// Without this the contract could go on describing a line somebody deleted,
// which is worse than having no contract at all.
const anchorFailures = [];
for (const entry of contract.claims) {
  const idx = docLines.findIndex((l) => l.includes(entry.anchor));
  if (idx === -1) {
    anchorFailures.push(entry);
    entry.__line = "?";
  } else {
    entry.__line = idx + 1;
  }
}

// --- 2. coverage: every route/endpoint the document names must be either
//        checked or explicitly registered as human-verify-only.
const covered = new Set();
for (const entry of contract.claims) {
  for (const t of entry.covers || []) covered.add(t);
}
const exempt = new Set(
  Object.keys(contract.humanVerifyOnly || {}).filter((k) => !k.startsWith("$")),
);
const mentioned = new Map(); // token -> first line
const TOKEN_RE = /`((?:GET|POST|PUT|PATCH|DELETE)\s+[^`]+|\/[A-Za-z0-9_\-\[\]/{}.]*)`/g;
docLines.forEach((line, i) => {
  for (const m of line.matchAll(TOKEN_RE)) {
    const tok = m[1].trim();
    if (!mentioned.has(tok)) mentioned.set(tok, i + 1);
  }
});
const uncovered = [...mentioned].filter(
  ([tok]) => !covered.has(tok) && !exempt.has(tok),
);

// --- 3. run the checks.
for (const entry of contract.claims) {
  const fn = CHECKS[entry.check.type];
  if (!fn) {
    fail(entry, `unknown check type ${entry.check.type}`, `Fix the contract file.`);
    continue;
  }
  fn(entry, entry.check);
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------

const ok = failures.length === 0 && anchorFailures.length === 0 && uncovered.length === 0;
const DOC_REL = inRepo(DOC_PATH);
const CONTRACT_REL = inRepo(CONTRACT_PATH);

/** Repo-relative when it is in the repo, absolute otherwise (the self-test's fixtures). */
function inRepo(p) {
  const rel = relative(INFRA_ROOT, p);
  return rel.startsWith("..") ? p : rel;
}

if (anchorFailures.length) {
  console.error(`\n=== ${anchorFailures.length} contract entr(ies) no longer match the document ===\n`);
  for (const e of anchorFailures) {
    console.error(`  [${e.id}]`);
    console.error(`    contract expects this text in ${DOC_REL}:`);
    console.error(`      ${JSON.stringify(e.anchor)}`);
    console.error(`    it is not there any more.`);
    console.error(`    claim: ${e.claim}`);
    console.error(
      `    -> Someone edited or deleted that line. Re-read it, decide whether the\n` +
        `       claim still holds, then update the 'anchor' in ${CONTRACT_REL}\n` +
        `       (or delete the entry if the claim is gone).\n`,
    );
  }
}

if (uncovered.length) {
  console.error(`\n=== ${uncovered.length} route/endpoint named in the document but not in the contract ===\n`);
  for (const [tok, line] of uncovered) {
    console.error(`  ${DOC_REL}:${line}  ${tok}`);
  }
  console.error(
    `\n  -> The document promises these on stage but nothing verifies them.\n` +
      `     Add a claim to ${CONTRACT_REL} covering each, or —\n` +
      `     if it genuinely cannot be checked — add it to "humanVerifyOnly" there\n` +
      `     with the reason. Do not leave it silent.\n`,
  );
}

if (failures.length) {
  console.error(`\n=== ${failures.length} claim(s) in ${DOC_REL} no longer match the code ===\n`);
  for (const f of failures) {
    console.error(`  ${DOC_REL}:${f.entry.__line}  [${f.entry.id}]`);
    console.error(`    the document says: ${f.entry.claim}`);
    console.error(`    the code says:     ${f.actual}`);
    console.error(`    -> ${f.fix}`);
    console.error(`    document text:     ${JSON.stringify(f.entry.anchor)}\n`);
  }
}

if (ok) {
  console.log(
    `DEMO-FLOWS contract: PASS — ${checksRun} machine-checked claims across ` +
      `${contract.claims.length} entries, ` +
      `${Object.keys(contract.humanVerifyOnly || {}).length} registered as human-verify-only.`,
  );
  console.log(`  web:     ${REPOS.web}`);
  console.log(`  backend: ${REPOS.backend}`);
  process.exit(0);
}

console.error(
  `DEMO-FLOWS contract: FAIL — ${failures.length} stale claim(s), ` +
    `${anchorFailures.length} dangling anchor(s), ${uncovered.length} uncovered mention(s).`,
);
console.error(`  web:     ${REPOS.web}`);
console.error(`  backend: ${REPOS.backend}`);
console.error(
  `\nWhich side is wrong? See demo/README.md — in short: if the code change was\n` +
    `intended, fix the document; if it was not, you have found a regression.\n`,
);
process.exit(1);
