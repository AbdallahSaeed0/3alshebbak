import assert from 'node:assert/strict';
import { test } from 'node:test';
import { alertFor, dayName, message, showCount, type Seen } from './notify.js';

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
