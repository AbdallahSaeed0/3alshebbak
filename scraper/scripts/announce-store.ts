// Tells every phone that installed the APK from GitHub that عالشباك is now on
// Google Play, once. Tapping it opens the download page, which says to remove
// the APK first (the two are signed differently, so Play can't update over it).
//
//   npm run announce-store              send
//   npm run announce-store -- --dry-run who would get it, nothing sent
//   npm run announce-store -- --force   again, even if already sent
//
// Skips iPhones and phones already from Play ("@play" in their following list;
// Play build 15 lacked that flag, so phones still on it get this too).
// Needs SUPABASE_* and FIREBASE_SERVICE_ACCOUNT.
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

// scrape_runs keeps one row per announcement, so a rerun doesn't spam.
const marker = 'store:google-play';
const { data: done, error: doneError } = await db.from('scrape_runs').select('id').eq('source', marker).limit(1);
if (doneError) throw new Error(doneError.message);
if (done?.length && !force) {
  console.log('Already announced (use --force to send again).');
  process.exit(0);
}

const title = '🎉 عالشباك بقى على Google Play';
const body = 'نزّله من المتجر عشان يتحدّث لوحده · دوس للتفاصيل';

const devices: { token: string; platform: string; following: string[] }[] = [];
for (let from = 0; ; from += 1000) {
  const { data, error } = await db.from('devices').select('token,platform,following').order('token').range(from, from + 999);
  if (error) throw new Error(error.message);
  devices.push(...data);
  if (data.length < 1000) break;
}
const targets = devices.filter((d) => d.platform !== 'ios' && !d.following.includes('@play'));
console.log(`${title}\n${body}\n→ ${targets.length} phones (${devices.length - targets.length} iPhones / from Play skipped)`);
if (dryRun) process.exit(0);

let sent = 0, stale = 0, failed = 0;
for (const d of targets) {
  try {
    await fcm!.send({ token: d.token, title, body, data: { type: 'update', url: DOWNLOAD_PAGE } });
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
