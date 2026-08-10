#!/usr/bin/env node
/**
 * Every GrpcSettings/GrpcUrls key a service demands must be supplied by every descriptor that
 * deploys it.
 *
 * This exists because of a bug nobody could see. GetRequiredServiceUri THROWS outside
 * Development when its key is absent, and gRPC client options are built lazily — on first
 * resolution, inside whatever worker happens to need the client. So a missing key does not
 * fail the deploy, does not fail a health check, and does not degrade the feature: it takes
 * the client down the moment anything asks for it, quietly, forever.
 *
 * translation-room-service required four keys and production supplied two. The two missing
 * ones were NotificationServiceUrl and TranscriptServiceUrl, which is why no reminder
 * notification had ever been delivered — the ReminderNotificationWorker was registered,
 * running, and unable to construct its client. auth-service was missing the key its workspace
 * invitation client needs.
 *
 * A unit test cannot catch this and neither can a type checker: the requirement lives in C#
 * and the supply lives in YAML. This script is the only place the two meet.
 */
import { readFileSync, readdirSync, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const infraRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const backendRoot = path.resolve(infraRoot, "..", "warptalk-backend");

/** Source directory name -> the name the descriptors give that service. */
const SERVICE_NAMES = {
  "translation-room": "translation-room-service",
  meeting: "meeting-service",
  auth: "auth-service",
  workspace: "workspace-service",
  billing: "billing-service",
  notification: "notification-service",
  transcript: "transcript-service",
  assistant: "assistant-service",
  gateway: "gateway",
};

const DESCRIPTORS = [
  "deploy/production/app.compose.yml",
  "docker-compose.yml",
];

function requiredKeysByService() {
  const required = new Map();
  for (const dir of readdirSync(backendRoot, { withFileTypes: true })) {
    if (!dir.isDirectory()) continue;
    const srcDir = path.join(backendRoot, dir.name, "src");
    if (!existsSync(srcDir)) continue;
    for (const project of readdirSync(srcDir)) {
      const program = path.join(srcDir, project, "Program.cs");
      if (!existsSync(program)) continue;
      const keys = [
        ...readFileSync(program, "utf8").matchAll(/"Grpc(?:Settings|Urls):([A-Za-z]+)"/g),
      ].map((match) => match[1]);
      if (keys.length === 0) continue;
      const name = SERVICE_NAMES[dir.name] ?? dir.name;
      required.set(name, new Set([...(required.get(name) ?? []), ...keys]));
    }
  }
  return required;
}

/** Keys supplied per service block. Only top-level two-space service keys start a block. */
function suppliedKeysByService(descriptorPath) {
  const supplied = new Map();
  let current = null;
  for (const line of readFileSync(descriptorPath, "utf8").split("\n")) {
    const header = /^ {2}([a-z0-9-]+):\s*$/.exec(line);
    if (header) {
      current = header[1];
      supplied.set(current, new Set());
      continue;
    }
    if (!current) continue;
    const setting = /^\s+Grpc(?:Settings|Urls)__([A-Za-z]+):/.exec(line);
    if (setting) supplied.get(current).add(setting[1]);
  }
  return supplied;
}

const required = requiredKeysByService();
const failures = [];

for (const descriptor of DESCRIPTORS) {
  const full = path.join(infraRoot, descriptor);
  if (!existsSync(full)) continue;
  const supplied = suppliedKeysByService(full);

  for (const [service, keys] of required) {
    // A descriptor that does not deploy a service owes it nothing.
    if (!supplied.has(service)) continue;
    const missing = [...keys].filter((key) => !supplied.get(service).has(key)).sort();
    if (missing.length > 0) {
      failures.push(
        `${descriptor}: ${service} is missing ${missing.join(", ")} — ` +
          `its Program.cs resolves these through GetRequiredServiceUri, which throws outside Development.`,
      );
    }
  }
}

if (failures.length > 0) {
  console.error("gRPC configuration coverage contract FAILED:\n");
  for (const failure of failures) console.error(`  ${failure}`);
  process.exit(1);
}

console.log(
  `gRPC configuration coverage contract passed (${required.size} services across ${DESCRIPTORS.length} descriptors).`,
);
