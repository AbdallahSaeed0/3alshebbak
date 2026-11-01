// "Tickets are out": after a sync, tells each phone that follows a film when
// the film opened a new day of showtimes at one of its cinemas. A day is new
// when this run is the first to see any showtime of that film, cinema and day
// — so a cinema adding a late show to a day already on sale says nothing.
// At most one notification per film per phone per day.

import type { SupabaseClient } from '@supabase/supabase-js';
import { Fcm, StaleToken } from './fcm.js';
import { errorMessage } from './http.js';
import { cairoToday } from './time.js';

type Row = { movie_id: string; cinema_id: string; business_date: string };
type Device = { token: string; following: string[]; cinemas: string[] };

const PAGE = 1000;

async function all<T>(query: () => any): Promise<T[]> {
  const rows: T[] = [];
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await query().range(from, from + PAGE - 1);
    if (error) throw new Error(error.message);
    rows.push(...(data as T[]));
    if (data.length < PAGE) return rows;
  }
}

const key = (r: Row) => `${r.movie_id}|${r.cinema_id}|${r.business_date}`;

/** Film id → the cinemas where it opened a new day in this run. */
async function drops(db: SupabaseClient, runStartedAt: string): Promise<Map<string, Set<string>>> {
  const now = new Date().toISOString();
  const fresh = await all<Row>(() =>
    db
      .from('showtimes')
      .select('movie_id,cinema_id,business_date')
      .gte('first_seen_at', runStartedAt)
      .gt('starts_at', now)
      .order('id'),
  );
  if (!fresh.length) return new Map();

  const movies = [...new Set(fresh.map((r) => r.movie_id))];
  const known = new Set(
    (
      await all<Row>(() =>
        db
          .from('showtimes')
          .select('movie_id,cinema_id,business_date')
          .in('movie_id', movies)
          .lt('first_seen_at', runStartedAt)
          .gt('starts_at', now)
          .order('id'),
      )
    ).map(key),
  );

  const opened = new Map<string, Set<string>>();
  for (const r of fresh) {
    if (known.has(key(r))) continue;
    let at = opened.get(r.movie_id);
    if (!at) opened.set(r.movie_id, (at = new Set()));
    at.add(r.cinema_id);
  }
  return opened;
}

export async function notifyDrops(db: SupabaseClient, runStartedAt: string) {
  const fcm = Fcm.fromEnv();
  if (!fcm) return console.log('  notifications: FIREBASE_SERVICE_ACCOUNT not set, skipped');

  const opened = await drops(db, runStartedAt);
  if (!opened.size) return console.log('  notifications: no new days on sale');

  const movieIds = [...opened.keys()];
  const devices = await all<Device>(() =>
    db.from('devices').select('token,following,cinemas').overlaps('following', movieIds).order('token'),
  );
  if (!devices.length) return console.log(`  notifications: ${movieIds.length} films opened days, nobody follows them`);

  const [{ data: movies }, { data: cinemas }] = await Promise.all([
    db.from('movies').select('id,title,title_ar').in('id', movieIds),
    db.from('cinemas').select('id,chain,name').in('id', [...new Set([...opened.values()].flatMap((s) => [...s]))]),
  ]);
  const title = new Map((movies ?? []).map((m) => [m.id, (m.title_ar ?? m.title) as string]));
  const cinemaLabel = new Map(
    (cinemas ?? []).map((c) => [c.id, c.chain === 'Independent' ? c.name : `${c.chain} · ${c.name}`]),
  );

  const today = cairoToday();
  let sent = 0;
  for (const device of devices) {
    for (const movieId of device.following) {
      const at = [...(opened.get(movieId) ?? [])];
      // A phone that picked its cinemas hears only about those.
      const where = device.cinemas.length ? at.filter((c) => device.cinemas.includes(c)) : at;
      if (!where.length) continue;

      // The primary key makes this the once-a-day check: a second insert fails.
      const { error: seen } = await db
        .from('notifications_sent')
        .insert({ token: device.token, movie_id: movieId, sent_on: today });
      if (seen) continue;

      const first = cinemaLabel.get(where[0]) ?? where[0];
      const more = where.length > 1 ? ` و${where.length - 1} سينما كمان` : '';
      try {
        await fcm.send({
          token: device.token,
          title: `🎟 تذاكر «${title.get(movieId) ?? movieId}» نزلت`,
          body: `حجز أيام جديدة في ${first}${more}`,
          data: { movieId },
        });
        sent++;
      } catch (e) {
        if (e instanceof StaleToken) {
          await db.from('devices').delete().eq('token', device.token);
          break;
        }
        console.log(`  ! notification to …${device.token.slice(-6)}: ${errorMessage(e)}`);
      }
    }
  }
  console.log(`✓ notifications: ${opened.size} films opened days, ${sent} sent`);
}
