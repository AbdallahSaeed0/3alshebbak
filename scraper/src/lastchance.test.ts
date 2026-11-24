import assert from 'node:assert/strict';
import { test } from 'node:test';
import { leavingByCinema, leavingFor, manyMessage, oneMessage, type Show } from './lastchance.js';
import { collectNews } from './snapshot.js';

const program = (films: string[], days: string[], cinema = 'scene:cfc'): Show[] =>
  films.flatMap((f) => days.map((d) => ({ cinema_id: cinema, movie_id: f, business_date: d })));

const today = '2026-11-23';
const thisWeek = ['2026-11-23', '2026-11-24', '2026-11-25'];
const nextWeek = ['2026-11-26', '2026-11-27', '2026-11-28'];
const phone = { cinemas: ['scene:cfc'], following: ['*'] };

test('a film missing from the next week is leaving', () => {
  const shows = [...program(['a', 'b', 'going'], thisWeek), ...program(['a', 'b'], nextWeek)];
  const leaving = leavingByCinema(shows, today);
  assert.deepEqual([...leaving.get('scene:cfc')!], [['going', '2026-11-25']]);
  assert.deepEqual(leavingFor(phone, shows, leaving, today), [
    { movieId: 'going', lastDay: '2026-11-25', cinemas: ['scene:cfc'] },
  ]);
});

test('next week not out yet, or a few presale films far ahead: nothing leaving', () => {
  const shows = [...program(['a', 'b', 'c', 'd'], thisWeek), ...program(['big'], ['2026-12-20'])];
  assert.deepEqual(leavingFor(phone, shows, leavingByCinema(shows, today), today), []);
});

test("still on at another of the phone's cinemas: not last chance", () => {
  const shows = [
    ...program(['a', 'b', 'x'], thisWeek),
    ...program(['a', 'b'], nextWeek),
    ...program(['x', 'y'], [...thisWeek, ...nextWeek], 'vox:moe'),
  ];
  const leaving = leavingByCinema(shows, today);
  assert.deepEqual(leavingFor({ cinemas: ['scene:cfc', 'vox:moe'], following: ['*'] }, shows, leaving, today), []);
  // A phone with only Scene starred hears about it.
  assert.equal(leavingFor(phone, shows, leaving, today).length, 1);
});

test('a cinema of one-off screenings is left out', () => {
  const shows = [
    ...program(['a', 'b', 'c'], ['2026-11-23']),
    ...program(['d', 'e', 'f'], ['2026-11-24']),
    ...program(['g', 'h', 'i'], ['2026-11-25']),
  ];
  assert.equal(leavingByCinema(shows, today).has('scene:cfc'), false);
});

test('today and tomorrow are said so', () => {
  assert.equal(oneMessage('X', today, 'سين', today).body, 'النهارده آخر يوم في سين');
  assert.equal(oneMessage('X', '2026-11-24', 'سين', today).body, 'بكره آخر يوم في سين');
});

test('the messages read naturally', () => {
  assert.deepEqual(oneMessage('Fate', '2026-11-26', 'رينيسانس · وسط البلد', today), {
    title: '⏳ آخر فرصة تشوف «Fate»',
    body: 'آخر يوم الخميس 26 نوفمبر في رينيسانس · وسط البلد',
  });
  assert.equal(manyMessage(['A', 'B', 'C']).title, '⏳ 3 أفلام خارجين من سينماتك قريب');
  assert.equal(manyMessage(['A', 'B', 'C']).body, '«A» و«B» وفيلم كمان: آخر فرصة تشوفهم');
});

test("last-chance notices aren't listed as new showtimes", () => {
  const news = collectNews([
    { run_at: '2026-11-23T10:00:00Z', since: null, movie_id: 'tmdb:1', kind: 'last_chance', cinemas: ['scene:cfc'] },
    { run_at: '2026-11-23T10:00:00Z', since: null, movie_id: 'tmdb:2', kind: 'opened', cinemas: ['scene:cfc'] },
  ]);
  assert.deepEqual(news.map((n) => n.m), ['tmdb:2']);
});
