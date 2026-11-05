// Renders the Play Store screenshots (1080x1920) from the web build served
// on localhost:6060. Usage: node play/tools/shots.cjs [step...]
const { chromium } = require('F:/3alShebbak/scraper/node_modules/playwright');
const out = 'F:/3alShebbak/play/raw/';

async function labels(page) {
  return page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map(e => {
    const r = e.getBoundingClientRect();
    return { role: e.getAttribute('role') || '', text: (e.getAttribute('aria-label') || e.innerText || '').trim().replace(/\s+/g, ' '), x: r.x + r.width / 2, y: r.y + r.height / 2, w: r.width };
  }).filter(e => e.text));
}
async function tap(page, text, { exact = false, nth = 0, role = 'button' } = {}) {
  const all = (await labels(page)).filter(e => (!role || e.role === role) && (exact ? e.text === text : e.text.includes(text)) && e.x > 0 && e.x < 405 && e.y > 0 && e.y < 720);
  if (!all[nth]) { console.log('NOT FOUND', text, '\n' + (await labels(page)).map(e => `${e.role}|${e.text.slice(0, 50)}|${Math.round(e.x)},${Math.round(e.y)}`).join('\n')); throw new Error(text); }
  await page.mouse.click(all[nth].x, all[nth].y);
  await page.waitForTimeout(1800);
}
async function dump(page) { console.log((await labels(page)).map(e => `${e.role}|${e.text.slice(0, 50)}|${Math.round(e.x)},${Math.round(e.y)}`).join('\n')); }
async function semantics(page) { await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); await page.waitForTimeout(1200); }

async function fresh(browser) {
  const ctx = await browser.newContext({ viewport: { width: 405, height: 720 }, deviceScaleFactor: 1080 / 405, locale: 'ar-EG', colorScheme: 'dark' });
  const page = await ctx.newPage();
  await page.goto('http://localhost:6060/');
  await page.evaluate(() => { localStorage.setItem('flutter.onboarded', 'true'); localStorage.setItem('flutter.tour_seen', 'true'); });
  await page.reload();
  await page.waitForTimeout(9000);
  await semantics(page);
  return page;
}
async function scroll(page, dy, n = 6) { for (let i = 0; i < n; i++) { await page.mouse.move(200, 400); await page.mouse.wheel(0, dy); await page.waitForTimeout(250); } await page.waitForTimeout(1200); }
const shot = (page, name) => page.screenshot({ path: out + name + '.png' });

const steps = {
  async debug(b) {
    const ctx = await b.newContext({ viewport: { width: 405, height: 3000 }, deviceScaleFactor: 1080 / 405, locale: 'ar-EG', colorScheme: 'dark' });
    const p = await ctx.newPage();
    await p.goto('http://localhost:6060/');
    await p.evaluate(() => { localStorage.setItem('flutter.onboarded', 'true'); localStorage.setItem('flutter.tour_seen', 'true'); });
    await p.reload(); await p.waitForTimeout(9000); await semantics(p);
    const t = async (x, o) => { const all = (await labels(p)).filter(e => e.role === (o||'button') && e.text.includes(x)); await p.mouse.click(all[0].x, all[0].y); await p.waitForTimeout(1800); };
    await t('اسأل عالشباك'); await t('مواعيد فيلم', 'checkbox'); await t('القاهرة', 'checkbox'); await t('ولا كان عالبال', 'checkbox'); await t('الخميس', 'checkbox');
    await p.screenshot({ path: out + 'assistant-tall.png' });
    const h = (await labels(p)).filter(e => e.text.startsWith('«ولا كان') || e.text.includes('حفلة في') || e.text.includes('حفلات في'));
    console.log(h.map(e => Math.round(e.y) + '|' + e.text.slice(0, 40)).join(' / '));
  },
  async home(b) { const p = await fresh(b); await shot(p, '1-home'); },
  async film(b) {
    const p = await fresh(b); await tap(p, 'Digger'); await shot(p, '2-film');
    await p.mouse.wheel(0, 500); await p.waitForTimeout(1500); await shot(p, '3-film-times'); await dump(p);
  },
  async film2(b) {
    const p = await fresh(b);
    for (let i = 0; i < 6; i++) { await p.mouse.move(200, 400); await p.mouse.wheel(0, 150); await p.waitForTimeout(300); } await p.waitForTimeout(1200);
    await tap(p, 'ولا كان عالبال', { exact: true });
    await shot(p, '2-film');
    await scroll(p, 400, 6); await shot(p, '3-film-times');
    await tap(p, 'نروح سوا');
    const times = (await labels(p)).filter(e => e.role === 'checkbox' || (e.role === 'button' && /^\d/.test(e.text)));
    console.log(times.map(t => t.role + '|' + t.text.slice(0, 40)).join(' / '));
    for (const t of times.slice(0, 3)) { await p.mouse.click(t.x, t.y); await p.waitForTimeout(500); }
    await shot(p, '6-go-together');
    await tap(p, 'ابعت 3 مواعيد'); await p.waitForTimeout(2500); await shot(p, '6b-share-card');
  },
  async cinemas(b) {
    const p = await fresh(b); await tap(p, 'السينمات', { exact: true }); await p.waitForTimeout(4000); await shot(p, '7-cinemas');
    await tap(p, 'خريطة', { exact: true }); await p.waitForTimeout(6000); await shot(p, '8-map');
  },
  async ticket(b) {
    const p = await fresh(b); await tap(p, 'ولا كان عالبال رينيسانس', { nth: 0 }); await shot(p, '4-ticket'); await dump(p);
  },
  async assistant(b) {
    const p = await fresh(b); await tap(p, 'اسأل عالشباك');
    await tap(p, 'مواعيد فيلم', { role: 'checkbox' });
    await tap(p, 'القاهرة', { role: 'checkbox' });
    await tap(p, 'ولا كان عالبال', { role: 'checkbox' });
    const days = (await labels(p)).filter(e => e.role === 'checkbox');
    console.log(days.map(d => d.text).join(' / '));
    await p.mouse.click(days[0].x, days[0].y); await p.waitForTimeout(2000);
    console.log((await labels(p)).filter(e => e.text.includes('حفلات') || e.text.includes('·')).map(e => e.role + '|' + e.text.slice(0, 90)).join(String.fromCharCode(10)));
    await shot(p, '5-assistant');
    for (let k = 0; k < 25; k++) { await scroll(p, -250, 1); const h = (await labels(p)).find(e => e.text.includes('حفلة في') || e.text.includes('حفلات في')); if (h && h.y > 160) { console.log('header at', h.y); break; } }
    await shot(p, '5b-assistant-top');
  },
};
(async () => {
  const browser = await chromium.launch({ channel: 'chrome' });
  for (const s of process.argv.slice(2)) { console.log('== ' + s); await steps[s](browser); }
  await browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
