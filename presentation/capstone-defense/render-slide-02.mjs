import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { chromium } from "playwright";
import { pathToFileURL } from "node:url";

const htmlPath = path.join(path.dirname(fileURLToPath(import.meta.url)), "slide-02-team.html");
const outputPath = path.join(path.dirname(fileURLToPath(import.meta.url)), "slide-02-team.png");

const browser = await chromium.launch({
  headless: true,
  ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}),
});
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
await page.goto(pathToFileURL(htmlPath).href, { waitUntil: "networkidle" });
await page.evaluate(async () => { await document.fonts.ready; });
await page.screenshot({ path: outputPath, fullPage: false });
await browser.close();
