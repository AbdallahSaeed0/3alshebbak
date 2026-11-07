// Tells every phone that installed the APK from GitHub that a new version is
// out, once per release. Run it right after publishing a GitHub release:
//
//   npm run announce-release              the newest release
//   npm run announce-release -- --dry-run who would get it, nothing sent
//   npm run announce-release -- --force   again, even if already announced
//
// iPhones are skipped (they update from the App Store / TestFlight).
// Phones from Google Play ("@play" in their following list) are skipped:
// Play updates them, and its policy forbids pointing them at an APK.
// Tapping the notification opens the download page, which always offers the
// newest APK (app/web/download/). Needs SUPABASE_* and FIREBASE_SERVICE_ACCOUNT.
import { Fcm, StaleToken } from '../src/fcm.js';
import { errorMessage } from '../src/http.js';
import { supabaseFromEnv } from '../src/supabase.js';

try { process.loadEnvFile(); } catch { /* CI may supply the environment. */ }

const DOWNLOAD_PAGE = 'https://abdallahsaeed0.github.io/3alshebbak/download/';
const dryRun = process.argv.includes('--dry-run');
const force = process.argv.includes('--force');

const db = supabaseFromEnv();
if (!db) throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing');
const fcm = Fcm.fromEnv();
if (!fcm && !dryRun) throw new Error('FIREBASE_SERVICE_ACCOUNT missing');

const res = await fetch('https://api.github.com/repos/AbdallahSaeed0/3alshebbak/releases?per_page=5', {
  headers: { Accept: 'application/vnd.github+json' },
});
if (!res.ok) throw new Error(`GitHub releases: HTTP ${res.status}`);
const release = ((await res.json()) as { tag_name: string; draft: boolean; body: string | null }[])
  .find((r) => !r.draft);
if (!release) throw new Error('No published release');
const version = release.tag_name.replace(/^v/, '');

// scrape_runs keeps one row per announced release, so a rerun doesn't spam.
const marker = `release:${release.tag_name}`;
const { data: done, error: doneError } = await db.from('scrape_runs').select('id').eq('source', marker).limit(1);
if (doneError) throw new Error(doneError.message);
if (done?.length && !force) {
  console.log(`${release.tag_name} was already announced (use --force to send again).`);
  process.exit(0);
}

const firstNote = (release.body ?? '')
  .split('\n')
  .find((l) => l.trimStart().startsWith('- '))
  ?.trimStart().slice(2).replaceAll('**', '').trim();
const title = `📲 نسخة جديدة من عالشباك (${version})`;
// A note's headline is the part before its colon ("🔔 إشعارات من كل السينمات: …").
const headline = firstNote?.split(':')[0].trim();
const body = headline && headline.length <= 60 ? `${headline} · دوس عشان تنزّلها` : 'دوس عشان تنزّلها';

const devices: { token: string; platform: string; following: string[] }[] = [];
for (let from = 0; ; from += 1000) {
  const { data, error } = await db.from('devices').select('token,platform,following').order('token').range(from, from + 999);
  if (error) throw new Error(error.message);
  devices.push(...data);
  if (data.length < 1000) break;
}
const targets = devices.filter((d) => d.platform !== 'ios' && !d.following.includes('@play'));
console.log(`${title}\n${body}\n→ ${targets.length} phones (${devices.length - targets.length} from Play skipped)`);
if (dryRun) process.exit(0);

let sent = 0, stale = 0, failed = 0;
for (const d of targets) {
  try {
    await fcm!.send({ token: d.token, title, body, data: { type: 'update', url: DOWNLOAD_PAGE, version } });
    sent++;
  } catch (e) {
    if (e instanceof StaleToken) {
      stale++;
      await db.from('devices').delete().eq('token', d.token);
    } else {
      failed++;
      console.log(`  ! …${d.token.slice(-6)}: ${errorMessage(e)}`);
    }
  }
}
const { error } = await db.from('scrape_runs').insert({ source: marker, started_at: new Date().toISOString(), ok: failed === 0 });
if (error) console.log(`  ! could not record the announcement: ${error.message}`);
console.log(`✓ sent ${sent}, removed ${stale} uninstalled, ${failed} failed`);
