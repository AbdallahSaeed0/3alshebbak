// What happened to notifications lately, from shebbak.notification_log.
//
//   npm run notify-log                  everything in the last 24 hours
//   npm run notify-log -- Godzilla      one film (any part of its title or id)
//   npm run notify-log -- --hours 72    a longer window
//   npm run notify-log -- --problems    only what didn't go out
//
// Needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (scraper/.env).
import { supabaseFromEnv } from '../src/supabase.js';

try { process.loadEnvFile(); } catch { /* CI may supply the environment. */ }

const WHY: Record<string, string> = {
  sent: '✅ اتبعت',
  failed: '❌ فشل (هيتعاد المرة الجاية)',
  stale_device: '🗑️ الموبايل مسح التطبيق',
  daily_limit: '⏸️ اتبعتله عن الفيلم ده النهارده قبل كده',
  not_new: '♻️ المواعيد مش جديدة عليه',
  other_cinemas: '📍 المواعيد في سينمات مش من سينماته',
  nobody_follows: '👤 محدش متابع الفيلم',
  no_firebase: '🔑 الرن ملوش مفتاح Firebase',
};

const args = process.argv.slice(2);
const flag = (name: string) => args.includes(name);
const hoursAt = args.indexOf('--hours');
const hours = hoursAt >= 0 ? Number(args[hoursAt + 1]) : 24;
const film = args.filter((a, i) => !a.startsWith('--') && i !== hoursAt + 1).join(' ');

const db = supabaseFromEnv();
if (!db) throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing');

let query = db
  .from('notification_log')
  .select('run_at,film,movie_id,device,outcome,kind,cinemas,new_shows,title,body,error')
  .gte('run_at', new Date(Date.now() - hours * 3_600_000).toISOString())
  .order('run_at', { ascending: false })
  .limit(500);
if (film) query = query.or(`film.ilike.%${film}%,movie_id.ilike.%${film}%`);
if (flag('--problems')) query = query.neq('outcome', 'sent').neq('outcome', 'nobody_follows');

const { data, error } = await query;
if (error) throw new Error(error.message);
if (!data.length) console.log(`مفيش حاجة في آخر ${hours} ساعة${film ? ` لـ«${film}»` : ''}.`);

const time = (iso: string) =>
  new Date(iso).toLocaleString('en-GB', { timeZone: 'Africa/Cairo', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });

for (const r of data) {
  const who = r.device ? ` · موبايل …${r.device}` : '';
  console.log(`${time(r.run_at)}  ${r.film ?? '—'}${who}`);
  console.log(`   ${WHY[r.outcome] ?? r.outcome}${r.kind ? ` (${r.kind})` : ''}${r.new_shows ? ` · ${r.new_shows} حفلة` : ''}`);
  if (r.cinemas?.length) console.log(`   السينمات: ${r.cinemas.slice(0, 5).join(', ')}${r.cinemas.length > 5 ? ` +${r.cinemas.length - 5}` : ''}`);
  if (r.title) console.log(`   الإشعار: ${r.title} — ${r.body}`);
  if (r.error) console.log(`   الخطأ: ${r.error}`);
}
