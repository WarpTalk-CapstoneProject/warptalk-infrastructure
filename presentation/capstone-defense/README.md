# Capstone defense slides

The GSU26SE16 defense deck for **WarpTalk — An AI Speech Translation Platform for
Real-Time Multilingual Communication with Voice Cloning**. Every slide is HTML at
1920×1080; the PNGs, PDF and PPTX are rendered from it.

## Deck order (30 slides)

| Pages | Source |
|---|---|
| 01 Cover | `index.html` |
| 02 Team | `slide-02-team.html` |
| 03 Contents | `slide-03-contents.html` |
| 04, 07, 09, 11, 13, 19, 24, 28 — section covers | `section-covers.html?section=<key>` |
| 05–06, 08, 10, 12, 14–18, 20–23, 25–27, 29–30 — 19 body slides | `content-slides.html` |

## Layout

```
*.html                     slide sources
assets/                    logos, tech marks (assets/logos/), architecture diagram, noise tile
*.png                      rendered cover, team, contents and section covers
content-png/               rendered body slides, named by page number
exports/
  warptalk-capstone-30-slides.pdf            full deck; body-slide text is real vector text
  warptalk-capstone-30-slides-editable.pptx  full deck; 427 native text boxes
```

## Rendering

Needs Node with `playwright`. Scripts use Playwright's bundled Chromium; set
`CHROME_PATH` to use a local Chrome instead.

```bash
node render-content.mjs          # body slides -> content-png/ + storyboard
node render-section-covers.mjs   # section covers -> section-0N-*.png
node build-deck-pdf.mjs          # full deck -> canva-upload/warptalk-capstone-30-slides.pdf
```

`build-deck-pdf.mjs` expects JPEG copies of the cover images in `.pdf-covers/`
(the full-size PNGs push the PDF far past Canva's upload limit).

The editable PPTX is two steps: `node extract-layout.mjs` measures every element on
the rendered page, then `python build-canva-pptx.py` (python-pptx) rebuilds it from
native shapes and text boxes.

## Importing into Canva

Canva only turns **real text** into editable elements. Use the PDF or the editable
PPTX — a deck of full-slide screenshots imports as flat pictures.

- The **PDF** keeps every visual effect (gradients, noise, light sweeps).
- The **PPTX** loses the noise and light-sweep texture on slides 08, 14 and 27;
  PowerPoint has no native equivalent.
- Both use **Avenir Next**, which Canva may substitute.

## Sources of truth

- Architecture (slide 10) is `Warptalk-Architecture.png` from Report 4 (SDD), placed
  as-is rather than redrawn.
- Slide 25 (Limitations) has no Canva source; it was written from `DEMO-FLOWS.md`.
- The SignalR mark is Microsoft's Azure SignalR Service icon. WarpTalk hosts its own
  ASP.NET Core SignalR hub, not the managed Azure product.
