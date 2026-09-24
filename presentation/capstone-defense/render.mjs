import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { chromium } from "playwright";
import { pathToFileURL } from "node:url";

const htmlPath = path.join(path.dirname(fileURLToPath(import.meta.url)), "index.html");
const outputPath = path.join(path.dirname(fileURLToPath(import.meta.url)), "warptalk-cover-editorial-v2.png");

const browser = await chromium.launch({
  headless: true,
  ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}),
});

const page = await browser.newPage({
  viewport: { width: 1920, height: 1080 },
  deviceScaleFactor: 1,
});

await page.goto(pathToFileURL(htmlPath).href, { waitUntil: "networkidle" });
await page.evaluate(async () => {
  await document.fonts.ready;
  await Promise.all(
    Array.from(document.images).map((img) =>
      img.complete
        ? Promise.resolve()
        : new Promise((resolve) => {
            img.addEventListener("load", resolve, { once: true });
            img.addEventListener("error", resolve, { once: true });
          }),
    ),
  );
});

await page.screenshot({ path: outputPath, fullPage: false });
await browser.close();
