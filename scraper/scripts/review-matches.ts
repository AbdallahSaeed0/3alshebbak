// A local page for checking how cinema listings were matched to TMDB, and
// fixing the wrong ones by pinning them in data/tmdb-overrides.json.
//
//   npm run review-matches          then open http://localhost:5177
//
// It lists films with no TMDB match, and matches that look off: an old film
// (a re-release, or a wrong match like «حدوته» → a 1985 film), or a TMDB title
// that doesn't resemble what the cinemas call it. Pinning writes the override
// for every title the cinemas use for that film; it takes effect on the next
// pipeline run once the file is committed and pushed.
//
// Needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (scraper/.env); TMDB_API_KEY
// or TMDB_READ_TOKEN to show what an id is before pinning it. Listens on
// localhost only.
import { createServer } from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import { supabaseFromEnv } from '../src/supabase.js';
import { normalizeTitle, similarity } from '../src/tmdb.js';

try { process.loadEnvFile(); } catch { /* CI may supply the environment. */ }

const PORT = 5177;
const OVERRIDES = 'data/tmdb-overrides.json';
const OLD_YEARS = 3;

const maybe = supabaseFromEnv();
if (!maybe) {
  console.error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (scraper/.env).');
  process.exit(1);
}
const db = maybe;

type MovieRow = {
  id: string; tmdb_id: number | null; title: string; title_ar: string | null;
  original_title: string | null; release_date: string | null; poster_path: string | null;
  fallback_poster_url: string | null;
};
type SourceFilm = { id: string; source: string; movie_id: string; title: string; url: string | null };

interface Review {
  movie: MovieRow;
  listings: SourceFilm[];
  reasons: string[];
  overrides: Record<string, number | null>;
}

async function reviews(): Promise<Review[]> {
  const [{ data: movies, error: e1 }, { data: films, error: e2 }] = await Promise.all([
    db.from('movies').select('id,tmdb_id,title,title_ar,original_title,release_date,poster_path,fallback_poster_url'),
    db.from('source_films').select('id,source,movie_id,title,url').limit(5000),
  ]);
  if (e1 || e2) throw new Error((e1 ?? e2)!.message);
  const overrides = JSON.parse(await readFile(OVERRIDES, 'utf8').catch(() => '{}')) as Record<string, number | null>;
  const byMovie = new Map<string, SourceFilm[]>();
  for (const f of films as SourceFilm[]) byMovie.set(f.movie_id, [...(byMovie.get(f.movie_id) ?? []), f]);

  const out: Review[] = [];
  for (const movie of movies as MovieRow[]) {
    const listings = byMovie.get(movie.id) ?? [];
    const reasons: string[] = [];
    const pinned = Object.fromEntries(
      listings.map((l) => normalizeTitle(l.title)).filter((t) => t in overrides).map((t) => [t, overrides[t]]),
    );
    if (movie.tmdb_id == null) {
      reasons.push('مش متطابق مع TMDB');
    } else {
      const year = movie.release_date ? Number(movie.release_date.slice(0, 4)) : null;
      if (year && new Date().getFullYear() - year >= OLD_YEARS) reasons.push(`فيلم قديم (${year})`);
      const names = [movie.title, movie.title_ar, movie.original_title].filter(Boolean).map((t) => normalizeTitle(t!));
      const best = Math.max(0, ...listings.map((l) => Math.max(...names.map((n) => similarity(normalizeTitle(l.title), n)))));
      if (listings.length && best < 0.5) reasons.push('اسم TMDB مش شبه اسم السينما');
    }
    // Already pinned to exactly this: reviewed, nothing to flag.
    const settled = Object.keys(pinned).length > 0 && Object.values(pinned).every((v) => v === movie.tmdb_id);
    if (reasons.length && !settled) out.push({ movie, listings, reasons, overrides: pinned });
  }
  return out.sort((a, b) => Number(a.movie.tmdb_id != null) - Number(b.movie.tmdb_id != null));
}

async function tmdbLookup(id: number) {
  const key = process.env.TMDB_API_KEY;
  const token = process.env.TMDB_READ_TOKEN;
  const url = new URL(`https://api.themoviedb.org/3/movie/${id}`);
  url.searchParams.set('language', 'ar-EG');
  if (key && !token) url.searchParams.set('api_key', key);
  const res = await fetch(url, { headers: token ? { Authorization: `Bearer ${token}` } : {} });
  if (!res.ok) throw new Error(`TMDB ${id}: HTTP ${res.status}`);
  const m = (await res.json()) as { title: string; original_title: string; release_date: string; poster_path: string | null };
  return { title: m.title, original: m.original_title, year: m.release_date?.slice(0, 4), poster: m.poster_path };
}

async function pin(titles: string[], tmdbId: number | null) {
  const overrides = JSON.parse(await readFile(OVERRIDES, 'utf8').catch(() => '{}')) as Record<string, number | null>;
  for (const t of titles) overrides[normalizeTitle(t)] = tmdbId;
  await writeFile(OVERRIDES, JSON.stringify(overrides, null, 2) + '\n');
}

const esc = (s: unknown) => String(s ?? '').replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
const poster = (m: MovieRow) =>
  m.poster_path ? `https://image.tmdb.org/t/p/w154${m.poster_path}` : m.fallback_poster_url ?? '';

function page(list: Review[]) {
  const cards = list.map((r, i) => {
    const m = r.movie;
    const titles = [...new Set(r.listings.map((l) => l.title))];
    const search = encodeURIComponent(titles[0] ?? m.title);
    return `<article>
  <img src="${esc(poster(m))}" alt="">
  <div class="body">
    <div class="reasons">${r.reasons.map((x) => `<span>${esc(x)}</span>`).join('')}</div>
    <h2>${m.tmdb_id ? `<a href="https://www.themoviedb.org/movie/${m.tmdb_id}" target="_blank">${esc(m.title)}</a>` : esc(m.title)}
      ${m.title_ar ? `<small>${esc(m.title_ar)}</small>` : ''} ${m.release_date ? `<small>${esc(m.release_date.slice(0, 4))}</small>` : ''}</h2>
    <p class="muted">${esc(m.id)}</p>
    <ul>${r.listings.map((l) => `<li><b>${esc(l.source)}</b>: ${l.url ? `<a href="${esc(l.url)}" target="_blank">${esc(l.title)}</a>` : esc(l.title)}</li>`).join('')}</ul>
    <form data-titles='${esc(JSON.stringify(titles))}' data-i="${i}">
      <input name="id" inputmode="numeric" placeholder="TMDB id">
      <button type="button" class="check">اعرض</button>
      <button type="submit">ثبّت</button>
      <button type="button" class="none">مش على TMDB</button>
      <a href="https://www.themoviedb.org/search/movie?query=${search}" target="_blank">دوّر على TMDB ↗</a>
      ${m.tmdb_id ? `<button type="button" class="ok" data-id="${m.tmdb_id}">المطابقة صح</button>` : ''}
      <output></output>
    </form>
  </div>
</article>`;
  }).join('\n');
  return `<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>مراجعة المطابقات</title>
<style>
:root{--bg:#f6f3ee;--card:#fff;--text:#1d1a16;--muted:#77706a;--accent:#b5761b;--warn:#b3401d}
@media (prefers-color-scheme:dark){:root{--bg:#0f0d0b;--card:#1b1815;--text:#efe8de;--muted:#9a9187;--accent:#e2a948;--warn:#ef7a55}}
body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 system-ui,"Segoe UI",Tahoma,sans-serif}
main{max-width:900px;margin:auto;padding:24px 16px}
h1{margin:0 0 4px}p.muted,.muted{color:var(--muted)}
article{display:flex;gap:16px;background:var(--card);border-radius:14px;padding:14px;margin:14px 0}
article img{width:92px;height:138px;object-fit:cover;border-radius:8px;background:#0002;flex:none}
.body{flex:1;min-width:0}h2{margin:4px 0;font-size:18px}h2 small{color:var(--muted);font-weight:400;margin-inline-start:6px}
.reasons span{display:inline-block;background:var(--warn);color:#fff;border-radius:99px;padding:1px 10px;font-size:12px;margin-inline-end:6px}
ul{margin:6px 0;padding-inline-start:18px}a{color:var(--accent)}
form{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-top:8px}
input{width:110px;padding:6px 8px;border-radius:8px;border:1px solid var(--muted);background:transparent;color:inherit}
button{padding:6px 12px;border-radius:8px;border:0;background:var(--accent);color:#fff;cursor:pointer}
button.none,button.check{background:transparent;color:var(--accent);border:1px solid var(--accent)}
button.ok{background:transparent;color:var(--muted);border:1px solid var(--muted)}
output{flex-basis:100%;color:var(--muted)}
</style></head><body><main>
<h1>مراجعة المطابقات</h1>
<p class="muted">${list.length} فيلم محتاج نظرة. التثبيت بيتكتب في <code>${OVERRIDES}</code>، وبيتطبّق في أول run للـ pipeline بعد ما تعمل commit و push.</p>
${cards || '<p>كله تمام، مفيش حاجة محتاجة مراجعة.</p>'}
</main><script>
for (const form of document.querySelectorAll('form')) {
  const out = form.querySelector('output');
  const titles = JSON.parse(form.dataset.titles);
  const send = async (id) => {
    const r = await fetch('/pin', {method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({titles, id})});
    out.textContent = r.ok ? (id === null ? '✓ اتثبّت: مش على TMDB' : '✓ اتثبّت على ' + id) : '✗ ' + await r.text();
  };
  form.querySelector('.check').onclick = async () => {
    const id = form.id.value.trim(); if (!/^\\d+$/.test(id)) return out.textContent = 'اكتب رقم TMDB';
    const r = await fetch('/tmdb/' + id); out.textContent = r.ok ? Object.values(await r.json()).filter(Boolean).slice(0, 3).join(' · ') : '✗ ' + await r.text();
  };
  form.onsubmit = (e) => { e.preventDefault(); const id = form.id.value.trim(); if (/^\\d+$/.test(id)) send(Number(id)); else out.textContent = 'اكتب رقم TMDB'; };
  form.querySelector('.none').onclick = () => send(null);
  const ok = form.querySelector('.ok'); if (ok) ok.onclick = () => send(Number(ok.dataset.id));
}
</script></body></html>`;
}

createServer(async (req, res) => {
  try {
    if (req.method === 'GET' && req.url === '/') {
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' }).end(page(await reviews()));
    } else if (req.method === 'GET' && req.url?.startsWith('/tmdb/')) {
      res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(await tmdbLookup(Number(req.url.slice(6)))));
    } else if (req.method === 'POST' && req.url === '/pin') {
      let body = '';
      for await (const chunk of req) body += chunk;
      const { titles, id } = JSON.parse(body) as { titles: string[]; id: number | null };
      if (!Array.isArray(titles) || !titles.length || (id !== null && !Number.isInteger(id))) throw new Error('bad request');
      await pin(titles, id);
      console.log(`pinned ${JSON.stringify(titles)} → ${id}`);
      res.writeHead(204).end();
    } else {
      res.writeHead(404).end();
    }
  } catch (e) {
    res.writeHead(500).end(e instanceof Error ? e.message : String(e));
  }
}).listen(PORT, '127.0.0.1', () => console.log(`مراجعة المطابقات: http://localhost:${PORT}`));
