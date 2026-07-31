import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const migrationsUrl = new URL(
  "./service-migrations/translation-room/",
  new URL("./", import.meta.url),
);
const migrationSql = readdirSync(migrationsUrl)
  .filter((name) => name.endsWith(".sql"))
  .sort()
  .map((name) => readFileSync(new URL(name, migrationsUrl), "utf8"))
  .join("\n");
const canonicalMigrationsUrl = new URL(
  "../../warptalk-backend/translation-room/database/migrations/",
  import.meta.url,
);
const canonicalMigrationSql = readdirSync(canonicalMigrationsUrl)
  .filter((name) => name.endsWith(".sql"))
  .sort()
  .map((name) => readFileSync(new URL(name, canonicalMigrationsUrl), "utf8"))
  .join("\n");

assert.match(
  migrationSql,
  /INSERT\s+INTO\s+translation_room\.supported_languages/i,
  "Logical Translation Room migrations must seed the service-owned language catalog.",
);

for (const locale of [
  "en-US",
  "vi-VN",
  "ja-JP",
  "ko-KR",
  "fr-FR",
  "es-ES",
]) {
  assert.match(
    migrationSql,
    new RegExp(`'${locale}'`),
    `Translation Room language seed must include ${locale}.`,
  );
}

assert.match(
  migrationSql,
  /ON\s+CONFLICT\s*\(\s*code\s*\)\s+DO\s+UPDATE/i,
  "Translation Room language seed must be idempotent.",
);
assert.match(
  canonicalMigrationSql,
  /INSERT\s+INTO\s+translation_room\.supported_languages/i,
  "The language seed must live in the backend's canonical Translation Room migrations, not only in deployment staging.",
);

console.log("Translation Room language seed contract: PASS");
