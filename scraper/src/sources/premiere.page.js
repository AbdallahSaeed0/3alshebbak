// Init script for Premiere Cinemas pages (see premiere.ts). Ported from the
// Pitflix desktop app's premiere_scrape.js.
//
// Premiere's showtime API responses are deliberately encrypted, so this never
// touches the API: it reads listings from the rendered DOM and gets times the
// way a visitor does — clicking cinema → date → format → experience on the
// now-showing page and reading the "Choose Time" buttons.
(function () {
  if (window.__shebbakPremiere) return;
  if (!/(^|\.)premiere-cinemas\.com$/.test(location.hostname)) return;

  // Count in-flight XHRs (the site uses axios) so clicks can wait for the
  // data they trigger instead of sleeping a fixed time.
  var pending = 0;
  var send = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function () {
    pending++;
    this.addEventListener('loadend', function () { pending--; });
    return send.apply(this, arguments);
  };

  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }

  async function settle() {
    await sleep(60);
    for (var i = 0; i < 150 && pending > 0; i++) await sleep(100);
    await sleep(80);
  }

  async function waitFor(fn, timeoutMs) {
    var deadline = Date.now() + timeoutMs;
    for (;;) {
      var v = fn();
      if (v || Date.now() > deadline) return v;
      await sleep(150);
    }
  }

  function text(el) { return el ? el.textContent.replace(/\s+/g, ' ').trim() : ''; }

  function abs(href) {
    try { return href ? new URL(href, location.origin).href : null; } catch (_) { return null; }
  }

  // `/_next/image?url=<original>&w=…` → the original upload URL.
  function imageUrl(img) {
    if (!img) return null;
    var src = img.getAttribute('src') || '';
    try {
      var u = new URL(src, location.origin);
      return u.searchParams.get('url') || u.href;
    } catch (_) {
      return src || null;
    }
  }

  // Sections are a <p> heading ("Choose Date", …) two levels under the block
  // that also holds that step's buttons. The site uses utility classes only,
  // so headings are the stable hook.
  function section(root, re) {
    var p = Array.prototype.find.call(root.querySelectorAll('p'), function (p) { return re.test(text(p)); });
    return p ? p.parentElement.parentElement : null;
  }

  function buttons(sec) { return sec ? Array.prototype.slice.call(sec.querySelectorAll('button')) : []; }

  function clickButton(root, re, label) {
    var b = buttons(section(root, re)).find(function (b) { return text(b) === label; });
    if (b) b.click();
    return !!b;
  }

  var CINEMA = /^choose your cinema$/i;
  var FORMAT = /^choose formats?$/i;
  var EXPERIENCE = /^choose experiences?$/i;
  var TIME = /^choose time$/i;
  var MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

  function cards() {
    return Array.prototype.map.call(
      document.querySelectorAll('a[href*="/now-showing/"] + div.flex-1'),
      function (d) { return d.parentElement; }
    );
  }

  function idFromHref(href) {
    var m = /\/(?:now-showing|movie-details|coming-soon-movie-details)\/([^/?#]+)/.exec(href || '');
    return m ? m[1] : null;
  }

  function nowShowing() {
    return cards().map(function (card) {
      var href = card.querySelector('a').getAttribute('href');
      var ps = Array.prototype.filter.call(card.querySelectorAll('.flex-1 > p'), function (p) { return text(p); });
      return {
        id: idFromHref(href),
        title: text(card.querySelector('h1')),
        posterUrl: imageUrl(card.querySelector('img')),
        info: text(ps[0]) || null,
        cinemas: buttons(section(card, CINEMA)).map(text),
        url: abs('/en/movie-details/' + idFromHref(href) + '/1'),
      };
    });
  }

  // "2026-10-08" → the date tile showing "08" / "Oct".
  function dateTile(card, isoDate) {
    var parts = isoDate.split('-');
    var month = MONTHS[parseInt(parts[1], 10) - 1];
    return Array.prototype.find.call(card.querySelectorAll('.dates-container'), function (d) {
      var ps = Array.prototype.map.call(d.querySelectorAll('p'), function (p) { return text(p).toLowerCase(); });
      return ps[1] === parts[2] && ps[2] === month;
    });
  }

  // The show data the card's picker holds for the selected date, every branch's
  // shows with their hall: the site decrypts its API answer into React state,
  // which a page script can read like any other. Shows without it are fine.
  function pickerShows(card) {
    var p = Array.prototype.find.call(card.querySelectorAll('p'), function (p) { return CINEMA.test(text(p)); });
    var key = p && Object.keys(p).find(function (k) { return k.indexOf('__reactFiber') === 0; });
    var shows = [];
    for (var f = key && p[key], i = 0; f && i < 15; f = f.return, i++) {
      for (var s = f.memoizedState, j = 0; s && j < 50; s = s.next, j++) {
        var v = s.memoizedState;
        if (!v || typeof v !== 'object' || !Array.isArray(v.Records)) continue;
        v.Records.forEach(function (r) {
          (r.cinemaShowTimes || []).forEach(function (t) {
            (t.movieDetailsData || []).forEach(function (m) { shows.push(m); });
          });
        });
        return shows;
      }
    }
    return shows;
  }

  // "11:00 PM" → "23:00"
  function hhmm(label) {
    var m = /^(\d{1,2}):(\d{2})\s*([AP]M)$/i.exec(label);
    if (!m) return null;
    var h = parseInt(m[1], 10) % 12 + (/p/i.test(m[3]) ? 12 : 0);
    return (h < 10 ? '0' : '') + h + ':' + m[2];
  }

  // Each time's hall at `branch` on `date` ("prm:<cinema id>:<screen id>",
  // as data/halls.json's premiereScreenId), for the app's seat view.
  function hallsFor(card, branch, date, format, times) {
    var byTime = {};
    pickerShows(card).forEach(function (m) {
      if (m.cinema_name !== branch || m.ss_start_date !== date || m.screen_id == null) return;
      if (m.mf_name + ' · ' + m.movie_experience !== format) return;
      byTime[m.ss_start_time] = 'prm:' + m.cinema_id + ':' + m.screen_id;
    });
    var halls = {};
    times.forEach(function (t) { var h = byTime[hhmm(t)]; if (h) halls[t] = h; });
    return halls;
  }

  // Reads every format · experience → times for the date currently selected on `card`.
  async function readFormats(card, branch, date) {
    var formats = [];
    var formatNames = buttons(section(card, FORMAT)).map(text);
    for (var fi = 0; fi < formatNames.length; fi++) {
      clickButton(card, FORMAT, formatNames[fi]);
      await settle();
      var experienceNames = buttons(section(card, EXPERIENCE)).map(text);
      for (var ei = 0; ei < experienceNames.length; ei++) {
        clickButton(card, EXPERIENCE, experienceNames[ei]);
        await settle();
        var times = buttons(section(card, TIME)).map(text);
        if (!times.length) continue;
        var name = formatNames[fi] + ' · ' + experienceNames[ei];
        var halls = {};
        try { halls = hallsFor(card, branch, date, name, times); } catch (_) { /* layout changed: no halls */ }
        formats.push({ name: name, times: times, halls: halls });
      }
    }
    return formats;
  }

  // One job covers several dates: each branch is picked once, then every
  // requested date tile under it. Returns { "yyyy-mm-dd": [{ name, formats }] }.
  // `job.skip` ({ branch: ["yyyy-mm-dd", …] }) leaves out days already known
  // elsewhere; a branch with all its days skipped isn't even opened.
  async function crawl(job) {
    var card = cards().find(function (c) { return idFromHref(c.querySelector('a').getAttribute('href')) === job.movieId; });
    if (!card) throw new Error('Movie is no longer on the now-showing page.');
    // After ready({ all: false }) this card's branches may still be loading.
    await waitFor(function () { return buttons(section(card, CINEMA)).length; }, 20000);
    var names = buttons(section(card, CINEMA)).map(text);
    var skip = job.skip || {};

    var days = {};
    job.dates.forEach(function (d) { days[d] = []; });
    for (var ci = 0; ci < names.length; ci++) {
      var skipped = skip[names[ci]] || [];
      var wanted = job.dates.filter(function (d) { return skipped.indexOf(d) < 0; });
      if (!wanted.length) continue;
      clickButton(card, CINEMA, names[ci]);
      await settle();
      // The first click can land before React hydrates; one retry covers it.
      if (!card.querySelector('.dates-container')) {
        await sleep(800);
        clickButton(card, CINEMA, names[ci]);
        await settle();
      }
      for (var di = 0; di < wanted.length; di++) {
        var tile = dateTile(card, wanted[di]);
        if (!tile) continue; // not playing at this branch that day
        tile.click();
        await settle();
        var formats = await readFormats(card, names[ci], wanted[di]);
        if (formats.length) {
          days[wanted[di]].push({ name: names[ci], formats: formats });
          // The app (a Flutter web view) shows each day as soon as it's read.
          if (job.progress && window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler(job.progress, { date: wanted[di], name: names[ci], formats: formats });
          }
        }
      }
    }
    return days;
  }

  // Resolves with the now-showing listing once every card's branch buttons
  // have loaded (and React has hydrated, so clicks work). With
  // `{ all: false }` (the app, which wants one film) it returns as soon as
  // the first card has them; crawl() waits for its own card's.
  async function ready(opts) {
    var all = !opts || opts.all !== false;
    await waitFor(function () { return cards().length; }, 30000);
    if (!cards().length) throw new Error("Site layout changed: no movie cards on Premiere's now-showing page");
    await waitFor(function () {
      var loaded = function (c) { return buttons(section(c, CINEMA)).length; };
      return all ? pending === 0 && cards().every(loaded) : cards().some(loaded);
    }, 30000);
    if (!cards().some(function (c) { return buttons(section(c, CINEMA)).length; })) {
      throw new Error("Site layout changed: Premiere's movie cards have no cinema picker");
    }
    await sleep(all ? 300 : 0);
    return nowShowing();
  }

  window.__shebbakPremiere = { ready: ready, crawl: crawl };
})();
