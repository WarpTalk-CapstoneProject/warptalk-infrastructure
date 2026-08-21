# prod-20260821-transcript-language-backfill-v145

_Generated 2026-08-21 from what was promoted to main._

> **v144 does not exist.** It built, scanned and signed cleanly and then failed its production
> deploy: `translation-backfill-worker` was in the Compose file and not in `image-matrix.json`, so
> it kept `${IMAGE_REGISTRY}/${IMAGE_TAG}` from the host's `.env` — values no release rewrites, and
> still July's — and 403'd on a tag that no longer exists. Production was never touched; the pull
> aborts before anything is replaced. v145 is the same release with that fixed, plus the check that
> would have caught it.

## What to test

**Reading a meeting in one language.** Open a multilingual meeting's record → Transcript. The
language picker now lists every language the product supports, not only the ones the meeting
happened to produce — so a meeting where translation was never started has entries where it used
to have none. Pick one that is not fully covered: the line under the toolbar becomes a progress
bar, and lines fill in as they land. Picking a language that is already complete does nothing and
costs nothing.

Worth checking specifically:

- A meeting whose target language was switched mid-way. Every language should reach the whole
  meeting, not just the stretch where it was live.
- The picker rows: "The whole meeting" only when nothing is missing, "N of M entries · translate
  the rest" otherwise, "Translate the meeting into this" for one with no coverage yet.
- The live tab (a meeting still running) still only marks the gap — there is no saved transcript
  to work on there, and that is deliberate.

**A correction reaching its translations.** Correct a transcript line that has translations. The
line updates immediately, and its translations are redone a few seconds later — previously they
kept the old sentence forever. The toast says so. Check a second language on the same line: all of
them should change, not just the one on screen.

**New in the app stack:** `warptalk-translation-backfill-worker-1`. The app host should hold 21
containers rather than 20 after this deploys; if it does not, the backfill will queue work nothing
consumes.


## Web

**New**

- `transcript` picking a language means the whole meeting is in it

**Fixed**

- `transcript` a corrected line does not keep the old translation on screen

## Backend

**New**

- `transcript` reading a meeting in one language means the whole meeting

**Fixed**

- `transcript` a client hanging up must not cancel the retranslation it asked for
- `transcript` a correction now reaches the translations of the line it corrected
- `transcript` a failed backfill must not block its own retry

## AI

**New**

- `translation` a redo carries the translation it replaces
- `translation` translate the parts of a meeting nobody was listening for

**Housekeeping**

- `redis` the backfill streams are shared, so they must never be given a TTL

## Infrastructure

**New**

- `deploy` run the translation backfill worker alongside the live one

**Fixed**

- `release` pin every service an image backs, not just the first one named

**Docs**

- `release` v143 — a multilingual meeting can be read back in one language


<!-- warptalk-web: 75ab90b8686d349783958aab87ca61f288e71de5 -->
<!-- warptalk-backend: 64de51a6534fee63cab9f03005706567239ca676 -->
<!-- warptalk-ai: d30122b9cfd06410c66f0e49c3a123aca6801f69 -->
<!-- warptalk-infrastructure: 128c318b82585274b1b69448dfa5d668e8d71c91 -->
