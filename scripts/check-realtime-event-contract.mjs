/**
 * Realtime (SignalR) event contract — WT-322.
 *
 * A `connection.on("SomethingHappened", …)` handler for an event no server ever sends looks
 * exactly like working code and does nothing. That is how WT-322 survived: the meeting page had
 * always listened for "TranslationRoomStarted", nothing in the backend ever emitted it, and a
 * participant already in the room when the host pressed Start got no audio and no captions
 * because the flag that handler sets gates both.
 *
 * This script diffs the two sides:
 *   - every event name the web client registers a handler for, and
 *   - every event name the backend broadcasts over SignalR.
 *
 * A handler with no emitter fails the build unless it is listed in KNOWN_UNEMITTED below with a
 * reason. That ledger cannot rot: an entry that DOES turn out to have an emitter is also an
 * error, so a fix forces the exception to be removed.
 *
 * Emitters with no handler are reported the same way, through KNOWN_UNHANDLED. Those are dead
 * weight rather than a broken feature, so they are held to the same explicitness but described
 * separately.
 *
 * Run:  node scripts/check-realtime-event-contract.mjs
 * Env:  WARPTALK_WEB_ROOT / WARPTALK_BACKEND_ROOT override the sibling-checkout defaults.
 */

import { readdirSync, readFileSync, existsSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const infraRoot = fileURLToPath(new URL("../", import.meta.url));
const webRoot = process.env.WARPTALK_WEB_ROOT ?? join(infraRoot, "..", "warptalk-web");
const backendRoot =
  process.env.WARPTALK_BACKEND_ROOT ?? join(infraRoot, "..", "warptalk-backend");

/**
 * Client handlers this script cannot match to a `SendAsync("Name", …)` call.
 *
 * `status` says WHY, and the three values mean very different things:
 *
 *   relayed     — an emitter provably exists, but names the event at runtime rather than as a
 *                 literal, so no static scan can see it. Not a defect.
 *   alias       — no emitter, and that is harmless: the same handler is also bound to a live
 *                 event name, so the feature works through the other binding.
 *   known-dead  — genuinely dead, confirmed, and deliberately not fixed by the change that added
 *                 this entry. Printed as a defect every run so it stays visible.
 *
 * Add an entry ONLY with a reason that says what you checked. "I could not find it" is not a
 * reason — an unexplained dead handler is the defect this script exists to catch.
 */
const KNOWN_UNEMITTED = new Map([
  [
    "DocumentDeleted",
    {
      status: "relayed",
      reason:
        "WorkspaceDocumentService passes WorkspaceDocumentConstants.LifecycleEvents.Deleted " +
        "(= \"DocumentDeleted\") to WorkspaceDocumentAuxiliaryPublisher, which publishes it as " +
        "the eventType field on warptalk:documents:events; NotificationRedisSubscriberService " +
        "re-broadcasts every such message under its own eventType. The name never appears as a " +
        "SendAsync literal because that relay is SendAsync(eventType, …).",
    },
  ],
  [
    "MeetingCreated",
    {
      status: "alias",
      reason:
        "NotificationRedisSubscriberService relays every warptalk:meetings:events message twice " +
        "— once as the generic 'MeetingEvent' and once under its own eventType — and the client " +
        "binds the SAME handler to both names. Nothing publishes eventType 'MeetingCreated', but " +
        "'MeetingEvent' is emitted, so the room list still refreshes through the other binding.",
    },
  ],
  [
    "MeetingDeleted",
    {
      status: "alias",
      reason:
        "Same arrangement as MeetingCreated: bound alongside the live 'MeetingEvent' fan-out, " +
        "which is what actually refreshes the room list.",
    },
  ],
  [
    "MemberRoleUpdated",
    {
      status: "known-dead",
      reason:
        "Nothing publishes to warptalk:workspace:events at all — the Gateway's fourth subscriber " +
        "has no producer. WorkspaceService's role change goes to the workspace outbox Redis " +
        "STREAM (WorkspaceOutboxDelivery.PublishRedisCompatibilityEventAsync), which other " +
        "services consume and the Gateway does not. The compatibility name there is also " +
        "'MemberRoleChanged', not 'MemberRoleUpdated'. Found by the WT-322 audit; out of scope.",
    },
  ],
  [
    "MemberRemoved",
    {
      status: "known-dead",
      reason:
        "Same cause as MemberRoleUpdated: WorkspaceService publishes MemberRemoved to the " +
        "workspace outbox stream, never to the warptalk:workspace:events pub/sub channel the " +
        "Gateway relays. Found by the WT-322 audit; out of scope.",
    },
  ],
  [
    "WorkspaceSettingsUpdated",
    {
      status: "known-dead",
      reason:
        "Declared in RealtimeConstants.ClientMethods and never sent by anything, and its channel " +
        "(warptalk:workspace:events) has no producer either. Found by the WT-322 audit; out of " +
        "scope.",
    },
  ],
  [
    "UserProfileUpdated",
    {
      status: "known-dead",
      reason:
        "Declared in RealtimeConstants.ClientMethods and never sent. Same dead channel as " +
        "WorkspaceSettingsUpdated. Found by the WT-322 audit; out of scope.",
    },
  ],
  [
    "DocumentCommentAdded",
    {
      status: "known-dead",
      reason:
        "Declared in RealtimeConstants.ClientMethods; the string appears nowhere else in the " +
        "backend, and no document lifecycle event uses it. Found by the WT-322 audit; out of " +
        "scope.",
    },
  ],
  [
    "AISummaryProgress",
    {
      status: "known-dead",
      reason:
        "The string appears nowhere in the backend in any form. The AI summary surface refetches " +
        "over REST instead. Found by the WT-322 audit; out of scope.",
    },
  ],
]);

/**
 * Server events no web handler binds. Same three-way `status`, read from the other direction:
 * `alias` means another live event covers the same need, `known-dead` means the broadcast is
 * genuinely going nowhere.
 */
const KNOWN_UNHANDLED = new Map([
  [
    "BillingNotification",
    {
      status: "alias",
      reason:
        "BillingService and the Gateway both broadcast it, but the web billing pages bind " +
        "'NewNotification' on the notification hub, which the same Redis message also produces.",
    },
  ],
  [
    "NotificationError",
    {
      status: "alias",
      reason:
        "Caller-scoped advisory on NotificationHub. The REST response already carries the " +
        "failure, so no client is required to bind it.",
    },
  ],
  [
    "WorkspaceEvent",
    {
      status: "known-dead",
      reason:
        "The generic fan-out of the warptalk:workspace:events relay, which has no producer — see " +
        "MemberRoleUpdated. The client does define SIGNALR_EVENTS.WORKSPACE_EVENT but never " +
        "binds it. Found by the WT-322 audit; out of scope.",
    },
  ],
  [
    "TranslatedAudioReceived",
    {
      status: "alias",
      reason:
        "Translated speech reaches the listener as a LiveKit audio track published by tts_worker " +
        "(see filtered-room-audio.tsx's ai-interpreter-* filtering), not over SignalR. This " +
        "broadcast is a second copy of the same result that no surface consumes.",
    },
  ],
  [
    "AiAssistantResult",
    {
      status: "alias",
      reason:
        "The in-meeting assistant renders from AssistantHub's Assistant* events and the chat " +
        "hub; this room-group copy is unbound.",
    },
  ],
  [
    "ChatAssistantResponsePending",
    {
      status: "known-dead",
      reason:
        "MeetingChatNotifier broadcasts it; the meeting chat panel shows its own optimistic " +
        "pending state instead and binds only ChatMessageReceived/ChatMessageHidden. Found by " +
        "the WT-322 audit; out of scope.",
    },
  ],
  [
    "ParticipantAdmitted",
    {
      status: "known-dead",
      reason:
        "TranslationRoomHub broadcasts it, but the lobby admits over REST " +
        "(useAdmitParticipant) and the waiting page refetches rather than listening. Found by " +
        "the WT-322 audit; out of scope.",
    },
  ],
  [
    "ParticipantMuteChanged",
    {
      status: "alias",
      reason:
        "Mute state is read off the LiveKit track publication rather than this hub event.",
    },
  ],
  [
    "ParticipantLanguageChanged",
    {
      status: "known-dead",
      reason:
        "The listen-language counterpart of ParticipantSpeakLanguageChanged, which the client " +
        "DOES bind. Listen language is a purely local preference on the web client, so nothing " +
        "consumes the broadcast. Found by the WT-322 audit; out of scope.",
    },
  ],
  [
    "ParticipantVoiceChanged",
    {
      status: "known-dead",
      reason:
        "TranslationRoomHub broadcasts a participant's voice preference change; the in-meeting " +
        "voice picker applies it locally and no handler binds the event. Found by the WT-322 " +
        "audit; out of scope.",
    },
  ],
  ...["PollCreated", "PollVoted", "PollClosed"].map((name) => [
    name,
    {
      status: "known-dead",
      reason:
        "The polls relay is complete end to end, but PollsPanel is no longer mounted in the " +
        "meeting side panel, so the handlers that use-polls.ts's comment says are 'wired in " +
        "page.tsx' no longer exist. Found by the WT-322 audit; out of scope.",
    },
  ]),
  ...["QuestionAsked", "QuestionUpvoted", "QuestionAnswered"].map((name) => [
    name,
    {
      status: "known-dead",
      reason:
        "Same as the Poll* events: the Q&A relay is complete, but no mounted component binds " +
        "these. Found by the WT-322 audit; out of scope.",
    },
  ]),
]);

// ---------------------------------------------------------------------------
// Corpus
// ---------------------------------------------------------------------------

function walk(dir, accept, out = []) {
  if (!existsSync(dir)) return out;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      if (["node_modules", ".git", ".next", "obj", "bin", "out", "dist"].includes(entry.name))
        continue;
      walk(full, accept, out);
    } else if (accept(entry.name)) {
      out.push(full);
    }
  }
  return out;
}

function requireDir(path, label) {
  if (!existsSync(path) || !statSync(path).isDirectory()) {
    console.error(
      `Realtime event contract: cannot find ${label} at ${path}.\n` +
        "Check out warptalk-web and warptalk-backend beside warptalk-infrastructure, or set " +
        "WARPTALK_WEB_ROOT / WARPTALK_BACKEND_ROOT.",
    );
    process.exit(1);
  }
}

requireDir(join(webRoot, "src"), "the web client");
requireDir(backendRoot, "the backend");

function lineOf(source, index) {
  return source.slice(0, index).split("\n").length;
}

// ---------------------------------------------------------------------------
// Side A — every event the web client registers a handler for
// ---------------------------------------------------------------------------

/**
 * SIGNALR_EVENTS is the client's own name table; several handlers are registered through it
 * rather than with a literal, so it has to be resolved before the scan means anything.
 */
function readEventConstants() {
  const file = join(webRoot, "src", "constants", "realtime.ts");
  if (!existsSync(file)) return {};
  const block = readFileSync(file, "utf8").match(
    /export const SIGNALR_EVENTS\s*=\s*\{([\s\S]*?)\n\}/,
  );
  if (!block) return {};
  return Object.fromEntries([...block[1].matchAll(/(\w+)\s*:\s*"([^"]+)"/g)].map((m) => [m[1], m[2]]));
}

/**
 * `.on(...)` is not unique to SignalR — TipTap editors, LiveKit rooms and hls.js all use it. Two
 * conditions keep those out: the file must actually pull in a hub connection, and the receiver
 * must be named like one. Both are deliberately conservative; a hub variable named something
 * else entirely would be missed rather than mis-reported.
 */
const HUB_RECEIVER = /(^|[a-z])(conn|connection)([A-Z_]|Ref)?$|^hub\w*$/i;

function collectClientHandlers() {
  const eventConstants = readEventConstants();
  const handlers = new Map(); // event name -> ["file:line", …]

  for (const file of walk(join(webRoot, "src"), (n) => /\.tsx?$/.test(n))) {
    const source = readFileSync(file, "utf8");
    const usesSignalR =
      source.includes("@microsoft/signalr") ||
      source.includes("@/lib/signalr") ||
      source.includes("HubConnection");
    if (!usesSignalR) continue;

    const pattern =
      /([A-Za-z_$][\w$]*)\s*\.on\s*\(\s*(?:"([^"]+)"|'([^']+)'|SIGNALR_EVENTS\.(\w+))/gs;
    for (const match of source.matchAll(pattern)) {
      if (!HUB_RECEIVER.test(match[1])) continue;
      const name = match[2] ?? match[3] ?? eventConstants[match[4]];
      if (!name) continue;
      const at = `${relative(webRoot, file)}:${lineOf(source, match.index)}`;
      handlers.set(name, [...(handlers.get(name) ?? []), at]);
    }
  }

  if (handlers.size === 0) {
    console.error(
      "Realtime event contract: found no SignalR handlers in the web client at all. That is a " +
        "broken scan, not a clean tree — refusing to pass.",
    );
    process.exit(1);
  }

  return handlers;
}

// ---------------------------------------------------------------------------
// Side B — every event the backend broadcasts
// ---------------------------------------------------------------------------

/**
 * Roughly half of the backend's SendAsync calls name the event through a `const string`
 * (RealtimeConstants.ClientMethods.*, BillingMessageConstants…). Resolving those by their
 * declared value is what keeps them out of the "unemitted" bucket.
 */
function readCsConstants(files) {
  const constants = new Map();
  for (const file of files) {
    for (const match of readFileSync(file, "utf8").matchAll(
      /const\s+string\s+(\w+)\s*=\s*"([^"]+)"/g,
    )) {
      constants.set(match[1], match[2]);
    }
  }
  return constants;
}

function collectServerEmitters() {
  const all = walk(backendRoot, (n) => n.endsWith(".cs"));
  const constants = readCsConstants(all);
  const production = all.filter((f) => !/[\\/]tests?[\\/]/i.test(f));
  const emitters = new Map(); // event name -> ["file:line", …]
  const dynamic = []; // SendAsync sites whose event name is a runtime value

  for (const file of production) {
    const source = readFileSync(file, "utf8");
    // Only hub broadcasts count. HttpClient.SendAsync/SmtpClient.SendAsync share the name, so
    // the call has to be reached through a SignalR client proxy.
    if (!/IHubContext|Clients\s*\.|Hub\b/.test(source)) continue;

    for (const match of source.matchAll(
      /(?:Clients|hubContext|_hubContext|Group\([^)]*\)|All|Caller|OthersInGroup\([^)]*\)|Client\([^)]*\))\s*[\s\S]{0,80}?SendAsync\s*\(\s*(?:"([^"]+)"|([A-Za-z_][\w.]*))/g,
    )) {
      const at = `${relative(backendRoot, file)}:${lineOf(source, match.index)}`;
      if (match[1]) {
        emitters.set(match[1], [...(emitters.get(match[1]) ?? []), at]);
        continue;
      }
      const resolved = constants.get(match[2].split(".").pop());
      if (resolved) {
        emitters.set(resolved, [...(emitters.get(resolved) ?? []), `${at} (${match[2]})`]);
      } else {
        dynamic.push(`${at} SendAsync(${match[2]}, …)`);
      }
    }
  }

  if (emitters.size === 0) {
    console.error(
      "Realtime event contract: found no SignalR broadcasts in the backend at all. That is a " +
        "broken scan, not a clean tree — refusing to pass.",
    );
    process.exit(1);
  }

  return { emitters, dynamic };
}

// ---------------------------------------------------------------------------
// Diff
// ---------------------------------------------------------------------------

const handlers = collectClientHandlers();
const { emitters, dynamic } = collectServerEmitters();

const failures = [];
const excused = [];
const tracked = [];

function record(name, entry, direction) {
  const line = `${name} (${direction}) — ${entry.reason}`;
  if (entry.status === "known-dead") tracked.push(line);
  else excused.push(`[${entry.status}] ${line}`);
}

for (const [name, sites] of [...handlers].sort()) {
  const entry = KNOWN_UNEMITTED.get(name);

  if (emitters.has(name)) {
    if (entry) {
      failures.push(
        `"${name}" is listed in KNOWN_UNEMITTED but the backend does emit it ` +
          `(${emitters.get(name)[0]}). Remove the stale exception.`,
      );
    }
    continue;
  }

  if (entry) {
    record(name, entry, "handled, never emitted");
    continue;
  }

  failures.push(
    `DEAD HANDLER: the web client listens for "${name}" (${sites.join(", ")}) and no backend ` +
      "service ever sends it. Either emit it from the server, delete the handler, or — if the " +
      "emitter genuinely lives outside this checkout — add it to KNOWN_UNEMITTED with the reason.",
  );
}

for (const [name, sites] of [...emitters].sort()) {
  const entry = KNOWN_UNHANDLED.get(name);

  if (handlers.has(name)) {
    if (entry) {
      failures.push(
        `"${name}" is listed in KNOWN_UNHANDLED but the web client does handle it ` +
          `(${handlers.get(name)[0]}). Remove the stale exception.`,
      );
    }
    continue;
  }

  if (entry) {
    record(name, entry, "emitted, never handled");
    continue;
  }

  failures.push(
    `UNHANDLED EVENT: the backend broadcasts "${name}" (${sites.join(", ")}) and no web client ` +
      "handler binds it. Either wire it up, delete the broadcast, or add it to KNOWN_UNHANDLED " +
      "with the reason it is deliberately unbound.",
  );
}

// Every ledger entry must correspond to a real name on one side or the other, or it is rot.
for (const [ledger, label, present] of [
  [KNOWN_UNEMITTED, "KNOWN_UNEMITTED", handlers],
  [KNOWN_UNHANDLED, "KNOWN_UNHANDLED", emitters],
]) {
  for (const name of ledger.keys()) {
    if (!present.has(name)) {
      failures.push(
        `"${name}" is listed in ${label} but no longer exists on that side of the contract. ` +
          "Remove the stale entry.",
      );
    }
  }
}

console.log(
  `Realtime event contract: ${handlers.size} client handlers, ${emitters.size} server events, ` +
    `${dynamic.length} relay sites whose event name is a runtime value.`,
);

if (excused.length > 0) {
  console.log(`\nDocumented exceptions (${excused.length}) — not defects:`);
  for (const line of excused) console.log(`  ~ ${line}`);
}

if (tracked.length > 0) {
  console.log(
    `\nKnown dead, tracked and deliberately not fixed here (${tracked.length}) — each one is a ` +
      "handler or broadcast that does nothing:",
  );
  for (const line of tracked) console.log(`  ! ${line}`);
}

if (failures.length > 0) {
  console.error("\nRealtime event contract: FAIL");
  for (const failure of failures) console.error(`  ✗ ${failure}`);
  process.exit(1);
}

console.log("\nRealtime event contract: PASS");
