// Messages from the app's "send feedback" page (shebbak.feedback).
//
//   npm run feedback                  the ones not handled yet, newest first
//   npm run feedback -- --all         everything
//   npm run feedback -- --done 12 15  mark messages 12 and 15 handled
//
// Needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (scraper/.env), and
// supabase/migrations/20261111120000_settings_backup_and_feedback.sql run once.
import { supabaseFromEnv } from '../src/supabase.js';

try { process.loadEnvFile(); } catch { /* CI may supply the environment. */ }

const KIND: Record<string, string> = {
  complaint: '😠 شكوى',
  idea: '💡 اقتراح',
  showtimes: '🕐 ميعاد غلط',
  other: '💬 حاجة تانية',
};

const maybe = supabaseFromEnv();
if (!maybe) {
  console.error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (scraper/.env).');
  process.exit(1);
}
const db = maybe;
const args = process.argv.slice(2);

const done = args.indexOf('--done');
if (done >= 0) {
  const ids = args.slice(done + 1).map(Number).filter(Number.isInteger);
  const { error } = await db.from('feedback').update({ handled: true }).in('id', ids);
  if (error) throw new Error(error.message);
  console.log(`✓ handled: ${ids.join(', ')}`);
  process.exit(0);
}

let q = db.from('feedback').select('*').order('created_at', { ascending: false }).limit(200);
if (!args.includes('--all')) q = q.eq('handled', false);
const { data, error } = await q;
if (error) {
  console.error(`Couldn't read feedback: ${error.message}`);
  console.error('Has supabase/migrations/20261111120000_settings_backup_and_feedback.sql been run?');
  process.exit(1);
}
if (!data?.length) console.log('مفيش رسايل جديدة.');
for (const f of data ?? []) {
  const when = new Date(f.created_at).toLocaleString('en-GB', { timeZone: 'Africa/Cairo' });
  console.log(`\n#${f.id} · ${KIND[f.kind] ?? f.kind} · ${when} · ${f.platform ?? ''} ${f.version ?? ''}${f.handled ? ' · ✓' : ''}`);
  if (f.contact) console.log(`  للرد: ${f.contact}`);
  console.log(`  ${String(f.message).replace(/\n/g, '\n  ')}`);
}
