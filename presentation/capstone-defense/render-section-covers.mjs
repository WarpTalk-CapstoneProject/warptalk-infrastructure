import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';

const dir=path.dirname(fileURLToPath(import.meta.url));
const sections=[
  ['context','01','Context & Problems'],['solution','02','Proposed Solution'],['architecture','03','System Architecture'],['tech','04','Tech Stack'],
  ['requirements','05','Functional Requirements'],['workflows','06','Core Workflows'],['achievements','07','Project Achievements'],['qa','08','Questions & Answers']
];
const browser=await chromium.launch({ ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {})});
const page=await browser.newPage({viewport:{width:1920,height:1080}});const url=pathToFileURL(`${dir}/section-covers.html`).href;
for(const [key,n] of sections){await page.goto(`${url}?section=${key}`,{waitUntil:'networkidle'});await page.evaluate(()=>document.fonts.ready);await page.screenshot({path:`${dir}/section-${n}-${key}.png`})}
const thumbs=sections.map(([key,n,title])=>`<figure><img src="section-${n}-${key}.png"><figcaption><b>${n}</b><span>${title}</span></figcaption></figure>`).join('');
await page.setViewportSize({width:1920,height:2160});await page.setContent(`<style>*{box-sizing:border-box}body{margin:0;padding:38px;background:#d9d9dc;font-family:Arial;color:#555}main{display:grid;grid-template-columns:1fr 1fr;gap:26px}figure{margin:0}img{display:block;width:100%;border-radius:16px}figcaption{display:flex;gap:10px;padding:9px 3px 0;text-transform:uppercase;letter-spacing:.06em;font-size:14px}b{color:#4b5cff}</style><main>${thumbs}</main>`);await page.screenshot({path:`${dir}/section-covers-contact-sheet.png`,fullPage:true});
const deck=[
  ['warptalk-cover-editorial-v2.png','Cover'],['slide-02-team.png','Team members'],['slide-03-contents.png','Table of contents'],
  ...sections.map(([key,n,title])=>[`section-${n}-${key}.png`,`${n} · ${title}`])
];
const deckThumbs=deck.map(([src,title],i)=>`<figure><img src="${src}"><figcaption><b>${String(i+1).padStart(2,'0')}</b><span>${title}</span></figcaption></figure>`).join('');
await page.setViewportSize({width:2400,height:1800});await page.setContent(`<style>*{box-sizing:border-box}body{margin:0;padding:34px;background:#d9d9dc;font-family:Arial;color:#555}main{display:grid;grid-template-columns:repeat(3,1fr);gap:26px 22px}figure{margin:0}img{display:block;width:100%;border-radius:14px}figcaption{display:flex;gap:10px;padding:9px 3px 0;text-transform:uppercase;letter-spacing:.06em;font-size:13px}b{color:#4b5cff}</style><main>${deckThumbs}</main>`);await page.screenshot({path:`${dir}/covers-only-deck-storyboard.png`,fullPage:true});
await browser.close();
