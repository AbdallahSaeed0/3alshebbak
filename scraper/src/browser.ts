// One shared headless Chromium for the sources that need a real browser
// (VOX's bot protection, Premiere's encrypted API). Plain-HTML sources never
// start it.

import { chromium, type Browser, type BrowserContext } from 'playwright';

let browser: Browser | null = null;

export async function newContext(): Promise<BrowserContext> {
  browser ??= await chromium.launch({ headless: true });
  const context = await browser.newContext({ locale: 'en-US', timezoneId: 'Africa/Cairo', viewport: { width: 1366, height: 900 } });
  // tsx (esbuild) wraps named functions in `__name(...)`; functions handed to
  // page.evaluate carry that call into the page, where it doesn't exist.
  await context.addInitScript('window.__name = window.__name || ((f) => f);');
  return context;
}

export async function closeBrowser() {
  await browser?.close();
  browser = null;
}
