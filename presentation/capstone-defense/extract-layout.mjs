import path from 'node:path';
import { fileURLToPath } from 'node:url';
// Walks the rendered deck and records, for every slide, the real geometry and style of
// each surface, picture and run of text — so the PPTX can be rebuilt out of native
// PowerPoint shapes and text boxes rather than one flat screenshot per slide.
import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const dir = path.dirname(fileURLToPath(import.meta.url));
const out = `${dir}/.pptx-native`;
mkdirSync(out, { recursive: true });

const browser = await chromium.launch({ ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}) });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 3 });
await page.goto(pathToFileURL(`${dir}/content-slides.html`).href, { waitUntil: 'networkidle' });
await page.evaluate(() => document.fonts.ready);

const slides = await page.$$('.slide');
const names = await page.$$eval('.slide', els => els.map(e => e.dataset.name));
const deck = [];

for (let i = 0; i < slides.length; i++) {
  const data = await slides[i].evaluate(root => {
    const base = root.getBoundingClientRect();
    const rel = r => ({ x: r.left - base.left, y: r.top - base.top, w: r.width, h: r.height });
    const px = v => parseFloat(v) || 0;
    const surfaces = [], pictures = [], texts = [];
    let picId = 0;

    const walk = el => {
      const cs = getComputedStyle(el);
      if (cs.display === 'none' || cs.visibility === 'hidden') return;
      const r = el.getBoundingClientRect();
      if (r.width < 1 || r.height < 1) return;

      // pictures: anything we cannot rebuild as a native shape
      if (el.tagName === 'IMG' || el.tagName === 'svg') {
        el.dataset.picId = 'p' + (picId++);
        pictures.push({ id: el.dataset.picId, ...rel(r) });
        return;                                   // do not descend into svg internals
      }

      // surfaces: a filled or ruled box
      const bg = cs.backgroundColor, bgImg = cs.backgroundImage;
      const hasFill = bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent';
      const hasGrad = bgImg.includes('gradient');
      const bt = px(cs.borderTopWidth), bb = px(cs.borderBottomWidth);
      if (hasFill || hasGrad || bt || bb) {
        surfaces.push({
          ...rel(r), fill: hasFill ? bg : null, gradient: hasGrad,
          radius: px(cs.borderTopLeftRadius),
          borderTop: bt ? cs.borderTopColor : null,
          borderBottom: bb ? cs.borderBottomColor : null,
        });
      }

      // Text: an element owning a text node is one text box. Its inline children become
      // runs inside it — emitting them separately would print a bold phrase twice, once
      // in the sentence and once stacked on top of it.
      const ownsText = [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim());
      if (ownsText && !el.closest('[data-text-done]')) {
        const runs = [];
        const collect = node => {
          for (const n of node.childNodes) {
            if (n.nodeType === 3) {
              const v = n.textContent.replace(/\s+/g, ' ');
              if (v.trim()) runs.push({ text: v, ...style(node) });
            } else if (n.nodeType === 1) {
              if (n.tagName === 'BR') { runs.push({ text: '\n', ...style(node.parentElement) }); continue; }
              if (n.tagName === 'IMG' || n.tagName === 'svg') continue;
              // a block-level inline child starts its own line on the page, so it must
              // start its own paragraph here too — otherwise words run together
              const d = getComputedStyle(n).display;
              const isBlock = d === 'block' || d === 'flex' || d === 'grid';
              if (isBlock && runs.length) runs.push({ text: '\n', ...style(n) });
              collect(n);
              // and after it too: whatever follows a block starts on a new line
              if (isBlock) runs.push({ text: '\n', ...style(n) });
            }
          }
        };
        const style = node => {
          const e = node.nodeType === 3 ? node.parentElement : node;
          const c = getComputedStyle(e);
          return { size: px(c.fontSize), weight: c.fontWeight,
                   color: c.webkitTextFillColor === 'rgba(0, 0, 0, 0)' ? 'GRADIENT' : c.color,
                   upper: c.textTransform === 'uppercase' };
        };
        collect(el);
        while (runs.length && runs[runs.length - 1].text === '\n') runs.pop();
        if (runs.length) {
          el.setAttribute('data-text-done', '1');
          texts.push({ ...rel(r), runs, align: cs.textAlign,
                       lineHeight: px(cs.lineHeight) || px(cs.fontSize) * 1.2 });
        }
      }
      for (const c of el.children) walk(c);
    };
    for (const c of root.children) walk(c);
    return { w: base.width, h: base.height, surfaces, pictures, texts };
  });

  // crop each picture out of the page at 3x so it stays crisp in the deck
  for (const pic of data.pictures) {
    const h = await slides[i].$(`[data-pic-id="${pic.id}"]`);
    if (h) { await h.screenshot({ path: `${out}/${names[i]}__${pic.id}.png` }); pic.file = `${names[i]}__${pic.id}.png`; }
  }
  deck.push({ name: names[i], ...data });
  console.log(`${names[i]}: ${data.surfaces.length} surfaces, ${data.pictures.length} pictures, ${data.texts.length} texts`);
}

writeFileSync(`${out}/layout.json`, JSON.stringify(deck, null, 1));
await browser.close();
