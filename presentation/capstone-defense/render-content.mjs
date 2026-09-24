import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';

const dir = path.dirname(fileURLToPath(import.meta.url));
const out = `${dir}/content-png`;
mkdirSync(out, { recursive: true });

const browser = await chromium.launch({ ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}) });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
await page.goto(pathToFileURL(`${dir}/content-slides.html`).href, { waitUntil: 'networkidle' });
await page.evaluate(() => document.fonts.ready);

const names = await page.$$eval('.slide', els => els.map(e => e.dataset.name));
const slides = await page.$$('.slide');
for (let i = 0; i < slides.length; i++) {
  await slides[i].screenshot({ path: `${out}/${names[i]}.png` });
  console.log('rendered', names[i]);
}

// contact sheet — written next to the PNGs so relative <img> paths resolve
const thumbs = names.map(n => `<figure><img src="content-png/${n}.png"><figcaption><b>${n.slice(0,2)}</b><span>${n.slice(3).replace(/-/g,' ')}</span></figcaption></figure>`).join('');
writeFileSync(`${dir}/.contact-sheet.html`, `<style>*{box-sizing:border-box}body{margin:0;padding:34px;background:#d9d9dc;font-family:Arial;color:#555}main{display:grid;grid-template-columns:repeat(3,1fr);gap:26px 22px}figure{margin:0}img{display:block;width:100%;border-radius:14px;box-shadow:0 2px 14px rgba(0,0,0,.08)}figcaption{display:flex;gap:10px;padding:9px 3px 0;text-transform:uppercase;letter-spacing:.06em;font-size:13px}b{color:#4b5cff}</style><main>${thumbs}</main>`);
await page.setViewportSize({ width: 2400, height: 1800 });
await page.goto(pathToFileURL(`${dir}/.contact-sheet.html`).href, { waitUntil: 'networkidle' });
await page.screenshot({ path: `${dir}/content-slides-storyboard.png`, fullPage: true });
await browser.close();
console.log('done →', out);
