// Composes the Play Store graphics from play/raw into play/store.
const { chromium } = require('F:/3alShebbak/scraper/node_modules/playwright');
const fs = require('fs');
const uri = (f) => 'data:image/png;base64,' + fs.readFileSync(f).toString('base64');
const R = (name) => uri('F:/3alShebbak/play/raw/' + name + '.png');
const out = 'F:/3alShebbak/play/store/';
const shots = [
  ['home', 'كل مواعيد سينمات مصر', 'في مكان واحد، وبتتحدث على طول'],
  ['5-assistant-final', 'اسأل عالشباك', 'اختار بس من غير كتابة، وهو يقولك المواعيد'],
  ['4-ticket', 'دوس على الميعاد', 'واحجز من موقع السينما على طول'],
  ['3-film-times', 'كل حفلات الفيلم', 'في كل السينمات، يوم بيوم'],
  ['2-film', 'تابع الفيلم', 'وأول ما الحجز يفتح يوصلك إشعار'],
  ['6b-share-card', 'نروح سوا؟', 'ابعت المواعيد لصحابك في صورة'],
  ['8-map', 'أقرب سينما ليك', 'كل سينمات مصر على الخريطة'],
  ['7-cinemas', 'سينماتك المفضلة', 'علّم عليها وهتظهرلك الأول'],
];
const css = `
@import url('https://fonts.googleapis.com/css2?family=Lalezar&family=IBM+Plex+Sans+Arabic:wght@500;600&display=block');
*{margin:0;box-sizing:border-box} body{width:1080px;height:1920px;overflow:hidden;direction:rtl;
background:radial-gradient(900px 700px at 50% 8%, rgba(242,184,75,.22), transparent 70%), linear-gradient(#17120b,#0b0906 60%);
font-family:'IBM Plex Sans Arabic',sans-serif;color:#f5ecdc;display:flex;flex-direction:column;align-items:center}
h1{font-family:Lalezar;font-weight:400;font-size:112px;line-height:1.1;margin-top:96px;color:#f2b84b;text-align:center}
p{font-size:46px;font-weight:600;margin-top:14px;color:#e9dcc4;text-align:center}
.phone{margin-top:70px;width:820px;height:1458px;border-radius:64px;overflow:hidden;border:3px solid rgba(242,184,75,.45);
box-shadow:0 40px 120px rgba(0,0,0,.7),0 0 0 14px #1d1810}
.phone img{width:100%;display:block}`;
(async () => {
  const b = await chromium.launch({ channel: 'chrome' });
  const page = await b.newPage({ viewport: { width: 1080, height: 1920 } });
  for (const [i, [f, t, s]] of shots.entries()) {
    await page.setContent(`<html><head><meta charset="utf-8"><style>${css}</style></head><body><h1>${t}</h1><p>${s}</p><div class="phone"><img src="${R(f)}"></div></body></html>`);
    await page.evaluate(() => document.fonts.ready); await page.waitForTimeout(800);
    await page.screenshot({ path: `${out}screenshot-${i + 1}.png` });
  }
  // Feature graphic 1024x500.
  await page.setViewportSize({ width: 1024, height: 500 });
  await page.setContent(`<html><head><meta charset="utf-8"><style>
@import url('https://fonts.googleapis.com/css2?family=Lalezar&family=IBM+Plex+Sans+Arabic:wght@600&family=Bebas+Neue&display=block');
*{margin:0;box-sizing:border-box} body{width:1024px;height:500px;overflow:hidden;direction:rtl;position:relative;
background:radial-gradient(520px 380px at 75% 45%, rgba(242,184,75,.25), transparent 70%), linear-gradient(120deg,#1b150c,#0b0906);font-family:'IBM Plex Sans Arabic'}
.txt{position:absolute;right:60px;top:100px;text-align:right;width:470px}
.logo{display:flex;align-items:center;gap:22px}
.logo img{width:120px;height:120px;border-radius:28px}
h1{font-family:Lalezar;font-weight:400;font-size:104px;color:#f2b84b;line-height:1}
.en{font-family:'Bebas Neue';letter-spacing:8px;color:#a8987e;font-size:30px;margin-top:4px}
p{color:#f5ecdc;font-size:36px;line-height:1.45;margin-top:30px}
.ph{position:absolute;width:230px;height:409px;border-radius:30px;overflow:hidden;border:2px solid rgba(242,184,75,.5);box-shadow:0 20px 60px rgba(0,0,0,.7)}
.ph img{width:100%}
</style></head><body>
<div class="ph" style="left:50px;top:120px;transform:rotate(-6deg)"><img src="${R('5-assistant-final')}"></div>
<div class="ph" style="left:250px;top:60px;transform:rotate(4deg)"><img src="${R('home')}"></div>
<div class="txt"><div class="logo"><div><h1>عالشباك</h1><div class="en">3AL SHEBBAK</div></div><img src="${uri('F:/3alShebbak/app/assets/brand/icon.png')}"></div>
<p>مواعيد سينمات مصر<br>كلها في مكان واحد</p></div></body></html>`);
  await page.evaluate(() => document.fonts.ready); await page.waitForTimeout(800);
  await page.screenshot({ path: `${out}feature-graphic.png` });
  await b.close();
})();
