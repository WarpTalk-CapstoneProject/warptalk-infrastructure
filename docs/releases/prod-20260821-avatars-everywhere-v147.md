# prod-20260821-avatars-everywhere-v147

_Generated 2026-08-21 from what was promoted to main._

> Covers **v146 and v147** together. v146 shipped and no note was written for it; the boundary
> footers made that self-correcting once the note ordering was fixed — see the Infrastructure
> section.

## What to test

**Your own face, everywhere.** Upload a profile picture under Settings → Profile, then look at:
the account card at the bottom of the sidebar, the members list, the rooms list, documents, and
**your tile in a meeting**. All of them should show it. Until now only the profile page did —
a Google-hosted picture worked everywhere by accident, an uploaded one worked nowhere else.

Two separate things had to be fixed for this, so if it still fails, they fail differently:

- a **401** on `/api/v1/auth/profile/avatar/…` means the gateway route is missing (v146);
- **initials beside a working profile page** means the URL is not being resolved (v147).

**Reading a long meeting.** Open a meeting record → Transcript. Each speaker now has a colour that
runs the height of what they said — a stripe down their rows, the rail beside their turn on the
timeline — and a face beside their name. Switch between the three layouts; the cue survives all
three. Most people have no picture, so initials in their colour is the normal state, not a fault.

**Getting back to the newest line.** Scroll up in the WarpBot widget, the meeting chat, the live
transcript or the saved one. A `↓ Latest` chip appears only once you have actually left the
bottom. The widget also fades its bottom edge.

**WarpBot's steps.** Ask it something that needs tools. While it works the steps are listed with a
violet sweep across them; when it answers they fold into one `Worked for Ns` line you can open
again. A failed turn keeps its trail too — that is the case it matters most.

**The landing page** says "Get Started", not "Get Started for Free". Both buttons: header and hero.


## Web

**New**

- `ui` a way back to the newest line, and WarpBot's work folded away after it
- `transcript` you can see who is talking without reading the name

**Fixed**

- `avatar` a face uploaded once shows up everywhere

**Other**

- the button says Get Started

## Backend

**Fixed**

- `gateway` let an <img> tag actually fetch an avatar

## Infrastructure

**Docs**

- `release` v145 — a language you pick is a language you get
- `release` the v144 note goes with the release that never deployed
- `release` v144 — a language you pick is a language you get


<!-- warptalk-web: ed8e51db7159e4db974be701070280380155faf0 -->
<!-- warptalk-backend: 89141e36e3ed360f703a707f5417eaa99faa3cd8 -->
<!-- warptalk-ai: d30122b9cfd06410c66f0e49c3a123aca6801f69 -->
<!-- warptalk-infrastructure: 5d59ae366607f66901bbc71231ef48179cad5546 -->
