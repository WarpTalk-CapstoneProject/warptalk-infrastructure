# prod-20260822-echo-guard-and-mic-check-v149

_Generated 2026-08-22 from what was promoted to main._

> Covers **v148 and v149** together. v148 shipped ("faces everywhere") and no note was written
> for it; the boundary footers make that self-correcting — this note starts where v147's
> stopped.

## What to test

**The transcript no longer hears itself.** Two machines, speakers on (no headphones), translation
running. Speak Vietnamese on one; the English dub plays out of the other machine's speakers. The
transcript must NOT gain English lines credited to the listener — that exact leak produced 77
false segments in ten minutes in the "Hieu Clone" meeting, and then taught the pipeline that the
listener speaks English. Every dropped echo is a `filtered_dub_echo` line in the stt-worker log,
so a quiet log plus a clean transcript is the pass; a clean transcript alone could just mean
headphones.

**The noise-suppression switch now carries evidence.** In a meeting: Settings → the strip
directly under **Noise suppression**. Speak — the bars are what others hear (measured after
Krisp when it is attached, not the raw mic). Stay quiet — the line under the strip is the
verdict: "Background: silent" means suppression is holding; "noticeable" means your room is
audible to everyone. The badge says which engine is carrying the load, **Krisp** or **Browser**.
This is also the first honest way to test whether the paid Krisp entitlement works at all:
toggle the row and watch the badge and the floor, instead of trusting a toast.

**Faces on the room record and in chat** (v148). The room detail page's Organizer/Invited chips
show real pictures instead of a hardcoded monogram, and a chat message's sender has a face. The
meeting tiles, live transcript and subtitles had theirs since v147.

## AI

**Fixed**

- `stt` the room's own dub, re-captured by a listener's microphone, is dropped before it becomes
  transcript, translation, billing, or language evidence — matched against the translations the
  room played in the last 25s, deliberately without a language condition, because the language
  label is the one thing echo corrupts
- `stt` the per-language confidence floor now applies to the completed path, the one path with
  real logprobs — early and speculative already had it

## Web

**New**

- `meeting` a mic check under the switch it proves: live wave strip of the published signal, a
  background-floor verdict, and a Krisp/Browser engine badge

**Fixed**

- `avatar` (v148) a face on every surface a person appears on: the room record's people chips
  and the meeting chat's senders stopped drawing hardcoded monograms

## Infrastructure

**CI**

- `release` the release-notes ordering contract runs in CI — filename sort ordered notes by slug,
  which is how v147's note nearly re-listed what v145 had shipped

**Docs**

- `release` v147 — avatars everywhere, and the note ordering that hid v146


<!-- warptalk-web: 7475a20cf07738eb2e27dff4c582c70384eed47c -->
<!-- warptalk-backend: 89141e36e3ed360f703a707f5417eaa99faa3cd8 -->
<!-- warptalk-ai: 89f220912daf17c615b924e3758eef951fdd0ed9 -->
<!-- warptalk-infrastructure: ab885d7420bd9c9ad0a9af8abdd426856b290584 -->
