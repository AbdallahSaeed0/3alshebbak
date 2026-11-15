import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { ScrapeResult, Showtime } from './model.js';
import { leaveToPremiere, premiereDays } from './premiere-week.js';

const p90 = 'elcinema:premiere-point90';
const show = (filmId: string, date: string, time: string, cinemaId = p90): Showtime => ({
  cinemaId, filmId, businessDate: date, start: `${date}T${time}:00+02:00`, format: 'Standard',
});
const result = (source: ScrapeResult['source'], showtimes: Showtime[]): ScrapeResult => ({
  source, fetchedAt: '2026-11-15T10:00:00Z', cinemas: [], films: [], showtimes, warnings: [],
});
const films = { 'elcinema:1': 'tmdb:9', 'premiere:5.1': 'tmdb:9', 'elcinema:2': 'tmdb:8' };

const elcinemaWeek = () =>
  result('elcinema', [
    show('elcinema:1', '2026-11-15', '12:00'), // Premiere has it at 11:00
    show('elcinema:1', '2026-11-18', '12:00'), // a day Premiere hasn't put up yet
    show('elcinema:2', '2026-11-15', '12:00'), // a film Premiere's site doesn't list that day
    show('elcinema:1', '2026-11-15', '12:00', 'elcinema:sun-city'), // another cinema
  ]);
const premiereShows = [
  show('premiere:5.1', '2026-11-15', '11:00'),
  show('premiere:5.1', '2026-11-15', '13:30', 'premiere:nile-cinema'),
];
const left = (r: ScrapeResult) => r.showtimes.map((s) => `${s.cinemaId} ${s.filmId} ${s.businessDate}`);

test("elCinema's shows step back on the film-days Premiere's site lists", async () => {
  const elcinema = elcinemaWeek();
  const results = [elcinema, result('premiere', premiereShows)];
  assert.equal(leaveToPremiere(results, films, await premiereDays(results, films, null)), 1);
  assert.deepEqual(left(elcinema), [
    `${p90} elcinema:1 2026-11-18`,
    `${p90} elcinema:2 2026-11-15`,
    'elcinema:sun-city elcinema:1 2026-11-15',
  ]);
});

test('without Premiere in the run or a database, elCinema keeps everything', async () => {
  const elcinema = result('elcinema', [show('elcinema:1', '2026-11-15', '12:00')]);
  assert.equal(leaveToPremiere([elcinema], films, await premiereDays([elcinema], films, null)), 0);
  assert.equal(elcinema.showtimes.length, 1);
});
