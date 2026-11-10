import assert from 'node:assert/strict';
import { test } from 'node:test';
import { alertData, alertFor, dayName, digest, message, NotificationLog, showCount, type Seen } from './notify.js';

const show = (business_date: string, cinema_id = 'scene:cfc', time = '19:00'): Seen => ({
  movie_id: 'tmdb:1',
  cinema_id,
  business_date,
  starts_at: `${business_date}T${time}:00+02:00`,
});

test('nothing new, nothing to say', () => {
  assert.equal(alertFor([], [show('2026-11-05')]), null);
});

test('the first showtimes at my cinemas open booking', () => {
  assert.deepEqual(alertFor([show('2026-11-05'), show('2026-11-06')], []), {
    kind: 'opened',
    cinemas: ['scene:cfc'],
  });
});

test('a week added is new days, up to the last one', () => {
  const before = [show('2026-11-05'), show('2026-11-06')];
  const fresh = [show('2026-11-13'), show('2026-11-12'), show('2026-11-06')];
  assert.deepEqual(alertFor(fresh, before), { kind: 'days', cinemas: ['scene:cfc'], lastDay: '2026-11-13' });
});

test('a day already on sale at one cinema is new at another', () => {
  const alert = alertFor([show('2026-11-05', 'vox:cfc')], [show('2026-11-05')]);
  assert.equal(alert?.kind, 'days');
  assert.deepEqual(alert?.cinemas, ['vox:cfc']);
});

test('more showtimes on days already on sale', () => {
  const before = [show('2026-11-05'), show('2026-11-06')];
  assert.deepEqual(alertFor([show('2026-11-05', 'scene:cfc', '22:00'), show('2026-11-06', 'scene:cfc', '22:00')], before), {
    kind: 'shows',
    cinemas: ['scene:cfc'],
    count: 2,
  });
});

test('the same show listed by another source is not news', () => {
  // VOX's presale copy of a show, then elCinema's: same cinema, same start.
  const before = [show('2026-12-16', 'elcinema:mall-of-egypt')];
  const fresh = [{ ...show('2026-12-16', 'elcinema:mall-of-egypt'), starts_at: '2026-12-16T17:00:00Z' }];
  assert.equal(alertFor(fresh, before), null);
});

test('the messages read naturally', () => {
  const label = (id: string) => ({ 'scene:cfc': 'سين · كايرو فستيفال سيتي', 'vox:cfc': 'ڤوكس' })[id] ?? id;
  assert.deepEqual(message({ kind: 'opened', cinemas: ['scene:cfc'] }, 'Clayface', label), {
    title: '🎟 تذاكر «Clayface» نزلت',
    body: 'الحجز فتح في سين · كايرو فستيفال سيتي',
  });
  assert.equal(
    message({ kind: 'days', cinemas: ['scene:cfc', 'vox:cfc'], lastDay: '2026-11-12' }, 'Clayface', label).body,
    'الحجز بقى لحد الخميس 12 نوفمبر في سين · كايرو فستيفال سيتي وسينما كمان',
  );
  assert.equal(
    message({ kind: 'shows', cinemas: ['vox:cfc'], count: 3 }, 'Clayface', label).body,
    '3 حفلات جديدة في ڤوكس',
  );
});

test('days and counts in Egyptian Arabic', () => {
  assert.equal(dayName('2026-11-12'), 'الخميس 12 نوفمبر');
  assert.equal(showCount(1), 'حفلة جديدة');
  assert.equal(showCount(2), 'حفلتين جداد');
  assert.equal(showCount(7), '7 حفلات جديدة');
  assert.equal(showCount(14), '14 حفلة جديدة');
});

test('a phone hearing about every film gets one digest for many', () => {
  assert.deepEqual(digest(['Godzilla', 'Dune', 'Hope', 'Verity']), {
    title: '🎬 مواعيد جديدة لـ4 أفلام',
    body: '«Godzilla» و«Dune» وفيلمين كمان',
  });
  assert.equal(digest(['A', 'B', 'C', 'D', 'E']).body, '«A» و«B» و3 أفلام كمان');
});

test('a log that cannot be written never stops the run', async () => {
  const broken = { from: () => ({ insert: async () => ({ error: { message: 'relation does not exist' } }) }) };
  const log = new NotificationLog(broken as never, '2026-11-06T12:00:00Z');
  log.add({ movie_id: 'tmdb:1', film: 'Clayface', device: 'abcd1234', outcome: 'sent', kind: 'opened' });
  await log.flush();
  assert.equal(log.rows.length, 0);
});

test('the log is written as it goes, so a cancelled run keeps what it sent', async () => {
  const inserted: number[] = [];
  let pruned = 0;
  const db = {
    from: () => ({
      insert: async (rows: unknown[]) => (inserted.push(rows.length), { error: null }),
      delete: () => ({ lt: async () => (pruned++, { error: null }) }),
    }),
  };
  const log = new NotificationLog(db as never, '2026-11-06T12:00:00Z');
  log.add({ movie_id: 'tmdb:1', film: 'Clayface', device: 'abcd1234', outcome: 'sent', kind: 'opened' });
  await log.flush();
  assert.deepEqual(inserted, [1]); // on the database before the run ends
  await log.flush(); // nothing new: no empty insert
  log.add({ movie_id: 'tmdb:2', film: 'Hope', device: 'efgh5678', outcome: 'daily_limit' });
  log.add({ movie_id: 'tmdb:3', film: 'Wildwood', device: 'efgh5678', outcome: 'sent', kind: 'days' });
  assert.equal(pruned, 0);
  await log.close();
  assert.deepEqual(inserted, [1, 2]);
  assert.equal(pruned, 1);
});

test('a notification says which films, where and since when, for the app to show', () => {
  const data = alertData(
    [{ movieId: 'tmdb:1003596', alert: { kind: 'shows', cinemas: ['elcinema:americana-plaza'], count: 15 } }],
    '2026-11-09T02:23:00.000Z',
    '2026-11-09T10:23:00.000Z',
  );
  assert.deepEqual(data, {
    type: 'alert',
    films: '[{"m":"tmdb:1003596","k":"shows","c":["elcinema:americana-plaza"]}]',
    since: '2026-11-09T02:23:00.000Z',
    until: '2026-11-09T10:23:00.000Z',
  });
  for (const v of Object.values(data)) assert.equal(typeof v, 'string'); // FCM data is strings only
});

test('a huge digest stays under the FCM size limit', () => {
  const cinemas = Array.from({ length: 40 }, (_, i) => `elcinema:some-long-cinema-name-${i}`);
  const many = Array.from({ length: 30 }, (_, i) => ({ movieId: `tmdb:${100000 + i}`, alert: { kind: 'opened' as const, cinemas } }));
  const films = JSON.parse(alertData(many, 'a', 'b').films);
  assert.equal(films.length, 30);
  assert.equal(films[0].c, undefined); // cinemas dropped, films kept
  const huge = Array.from({ length: 400 }, (_, i) => ({ movieId: `tmdb:${100000 + i}`, alert: { kind: 'opened' as const, cinemas } }));
  const data = alertData(huge, 'a', 'b');
  assert.ok(data.films.length <= 3000);
  assert.ok(JSON.parse(data.films).length > 50);
});
