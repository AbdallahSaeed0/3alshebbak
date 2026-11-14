// How many people use the app, from shebbak.app_opens (the app reports each
// install once a day with a random id; see app/lib/services/usage.dart).
//
//   npm run users              the last 14 days
//   npm run users -- --days 60
//
// Needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (scraper/.env), and
// supabase/migrations/20261110090000_users_and_inbox.sql run once (and
// 20261113121000_retention.sql for the "do they come back" table).
import { supabaseFromEnv } from '../src/supabase.js';

try { process.loadEnvFile(); } catch { /* CI may supply the environment. */ }

const args = process.argv.slice(2);
const at = args.indexOf('--days');
const days = at >= 0 ? Number(args[at + 1]) || 14 : 14;

const maybe = supabaseFromEnv();
if (!maybe) {
  console.error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (scraper/.env).');
  process.exit(1);
}
const db = maybe;
const { data: daily, error } = await db.from('daily_users').select('day,users,android,ios').limit(days);
if (error) {
  console.error(`Couldn't read daily_users: ${error.message}`);
  console.error('Has supabase/migrations/20261110090000_users_and_inbox.sql been run?');
  process.exit(1);
}

const since = new Date(Date.now() - 30 * 86_400_000).toISOString().slice(0, 10);
const installs = async (from?: string) => {
  const ids = new Set<string>();
  for (let page = 0; ; page += 1000) {
    let q = db.from('app_opens').select('install_id').order('install_id').range(page, page + 999);
    if (from) q = q.gte('day', from);
    const { data, error } = await q;
    if (error) throw new Error(error.message);
    for (const r of data) ids.add(r.install_id as string);
    if (data.length < 1000) return ids.size;
  }
};

console.log(`كل اللي فتحوا التطبيق من أول العدّ: ${await installs()}`);
console.log(`فتحوه في آخر 30 يوم:              ${await installs(since)}\n`);
console.log('اليوم         يوزرز   أندرويد   آيفون');
for (const d of daily ?? []) {
  console.log(`${d.day}   ${String(d.users).padStart(5)}   ${String(d.android).padStart(7)}   ${String(d.ios).padStart(5)}`);
}

// Do they come back? Installs by the week they first opened the app.
const { data: cohorts, error: rErr } = await db.from('retention')
  .select('cohort_week,new_installs,d1_pct,week1_pct,week2_pct').limit(8);
if (rErr) {
  console.log(`
(retention: ${rErr.message} — run supabase/migrations/20261113121000_retention.sql)`);
} else {
  const pct = (v: number | null) => (v == null ? '…' : `${v}%`).padStart(9);
  console.log('\nبيرجعوا؟ (حسب أسبوع أول فتح)');
  console.log('الأسبوع       جداد   تاني يوم   أول أسبوع   تاني أسبوع');
  for (const c of cohorts ?? []) {
    console.log(`${c.cohort_week}   ${String(c.new_installs).padStart(4)}  ${pct(c.d1_pct)}  ${pct(c.week1_pct)}   ${pct(c.week2_pct)}`);
  }
  console.log('… = الأسبوع ده لسه مخلصش');
}
