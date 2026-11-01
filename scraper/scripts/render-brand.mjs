// Renders the عالشباك mark (same geometry as the app's TicketMark) to the PNGs
// the app's launcher-icon and splash tools read, in app/assets/brand/. Lives
// here because this package already has Playwright.
//
//   node scripts/render-brand.mjs
//   cd ../app && dart run flutter_launcher_icons && dart run flutter_native_splash:create

import { chromium } from 'playwright';

const OUT = new URL('../../app/assets/brand/', import.meta.url);

const TICKET =
  'M22 30H34A6 6 0 0 0 46 30H98A8 8 0 0 1 106 38V82A8 8 0 0 1 98 90H46A6 6 0 0 0 34 90H22A8 8 0 0 1 14 82V38A8 8 0 0 1 22 30Z';

const mark = ({ ink = '#1A1206', ticket = '#F2B544', back = '#FF8A3D' } = {}) => `
<svg viewBox="0 0 120 120" width="100%" height="100%">
  <g transform="rotate(6 60 60) translate(4 -3)"><path d="${TICKET}" fill="${back}"/></g>
  <g transform="rotate(-10 60 60)">
    <path d="${TICKET}" fill="${ticket}"/>
    <path d="M40 38V82" stroke="${ink}" stroke-width="2" stroke-dasharray="3 3" stroke-linecap="round"/>
    <circle cx="27" cy="46" r="3.2" fill="${ink}"/>
    <circle cx="27" cy="60" r="3.2" fill="${ink}"/>
    <circle cx="27" cy="74" r="3.2" fill="${ink}"/>
    <text x="73" y="57" text-anchor="middle" dominant-baseline="central"
          font-family="Lalezar" font-size="50" fill="${ink}">ع</text>
  </g>
</svg>`;

/** One colour with the stub, tear line and «ع» cut out — for themed icons. */
const monoMark = () => `
<svg viewBox="0 0 120 120" width="100%" height="100%">
  <mask id="cut">${mark({ ink: '#000', ticket: '#fff', back: 'transparent' }).replace(/<\/?svg[^>]*>/g, '')}</mask>
  <rect width="120" height="120" fill="#fff" mask="url(#cut)"/>
</svg>`;

/** file, canvas size, the mark's share of the canvas, background, colours */
const JOBS = [
  // Legacy Android and iOS: the whole tile.
  ['icon.png', 1024, 0.86, '#0B0A08'],
  // Adaptive icon foreground: kept inside the 66% safe zone launchers never crop.
  ['icon-foreground.png', 1024, 0.62, 'transparent'],
  // Android 13 themed icon: one colour, the system tints it.
  ['icon-monochrome.png', 1024, 0.62, 'transparent', 'mono'],
  // Android 12+ splash icon: shown inside a circle two thirds its size.
  ['splash.png', 1152, 0.55, 'transparent'],
  // Pre-12 splash and the web: the mark alone.
  ['splash-legacy.png', 600, 1, 'transparent'],
];

const browser = await chromium.launch();
const page = await browser.newPage();
for (const [file, size, share, background, colors] of JOBS) {
  const m = Math.round(size * share);
  await page.setViewportSize({ width: size, height: size });
  await page.setContent(`<!doctype html><html><head>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Lalezar&display=block"></head>
<body style="margin:0;background:${background}">
<div style="width:${size}px;height:${size}px;display:flex;align-items:center;justify-content:center">
<div style="width:${m}px;height:${m}px">${colors === 'mono' ? monoMark() : mark(colors)}</div></div></body></html>`);
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: new URL(file, OUT).pathname.slice(process.platform === 'win32' ? 1 : 0), omitBackground: background === 'transparent' });
  console.log(`wrote ${file}`);
}
await browser.close();
