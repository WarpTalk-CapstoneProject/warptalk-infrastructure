import path from 'node:path';
import { fileURLToPath } from 'node:url';
// One PDF of the whole 30-slide deck. The 19 body slides come straight from the live HTML,
// so their text stays real vector text that Canva can lift back out; the 11 cover/section
// slides are placed as their rendered images, since they are full-bleed gradient artwork.
import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';

const dir = path.dirname(fileURLToPath(import.meta.url));

const COVERS = {           // page number -> rendered cover image
  1: 'warptalk-cover-editorial-v2.png', 2: 'slide-02-team.png', 3: 'slide-03-contents.png',
  4: 'section-01-context.png', 7: 'section-02-solution.png', 9: 'section-03-architecture.png',
  11: 'section-04-tech.png', 13: 'section-05-requirements.png', 19: 'section-06-workflows.png',
  24: 'section-07-achievements.png', 28: 'section-08-qa.png',
};

let html = readFileSync(`${dir}/content-slides.html`, 'utf8');

// The inline feTurbulence noise is 67 MB of a 76 MB print — Chrome rasterises every
// instance at print resolution. A pre-rendered tile looks the same and costs nothing.
html = html.replace(/url\("data:image\/svg\+xml,[^"]*feTurbulence[^"]*"\)/g, 'url("assets/noise-tile.png")');
// and the heavy source images go in as JPEG for print
html = html.replace('assets/warptalk-architecture-sdd.png', '.pdf-covers/arch.jpg');

// print rules: one slide per page, no page margin, backgrounds kept
html = html.replace('</style>', `
  @page { size: 1920px 1080px; margin: 0; }
  @media print {
    html, body { background: #fff; }
    .slide { page-break-after: always; break-after: page; }
    .slide:last-of-type { page-break-after: auto; break-after: auto; }
  }
  .cover-page { padding: 0; }
  .cover-page img { display: block; width: 1920px; height: 1080px; }
</style>`);

// splice the cover pages into the running order
const parts = html.split(/(?=<main class="slide)/);
const head = parts.shift();
const body = parts;                                   // 19 body slides, in deck order
const bodyPages = [5,6,8,10,12,14,15,16,17,18,20,21,22,23,25,26,27,29,30];
const out = [];
let bi = 0;
for (let page = 1; page <= 30; page++) {
  if (COVERS[page]) out.push(`<main class="slide cover-page"><img src=".pdf-covers/${COVERS[page].replace(/\.png$/, ".jpg")}" alt="" /></main>\n\n`);
  else { if (bodyPages[bi] !== page) throw new Error(`order mismatch at page ${page}`); out.push(body[bi++]); }
}
if (bi !== body.length) throw new Error(`used ${bi} of ${body.length} body slides`);

const tmp = `${dir}/.deck-print.html`;
writeFileSync(tmp, head + out.join(''));

const browser = await chromium.launch({ ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}) });
const page = await browser.newPage();
await page.goto(pathToFileURL(tmp).href, { waitUntil: 'networkidle' });
await page.evaluate(() => document.fonts.ready);
await page.pdf({
  path: `${dir}/canva-upload/warptalk-capstone-30-slides.pdf`,
  width: '1920px', height: '1080px', printBackground: true, margin: {top:0,right:0,bottom:0,left:0},
});
await browser.close();
unlinkSync(tmp);
console.log('written');
