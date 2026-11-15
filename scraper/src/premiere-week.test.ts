import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { ScrapeResult, Showtime } from './model.js';
import { leaveToPremiere, premiereBranches } from './premiere-week.js';

const p90 = 'elcinema:premiere-point90';
const show = (filmId: string, date: string, time: string, cinemaId = p90): Showtime => ({
  cinemaId, filmId, businessDate: date, start: `${date}T${time}:00+02:00`, format: 'Standard',
});
const result = (source: ScrapeResult['source'], showtimes: Showtime[]): ScrapeResult => ({
  source, fetchedAt: '2026-11-15T10:00:00Z', cinemas: [], films: [], showtimes, warnings: [],
});
const left = (r: ScrapeResult) => r.showtimes.map((s) => `${s.cinemaId} ${s.businessDate}`);
const premiere = result('premiere', [
  show('premiere:5.1', '2026-11-15', '11:00'),
  show('premiere:5.1', '2026-11-15', '13:30', 'premiere:nile-cinema'),
]);

test("a branch Premiere's site lists shows only Premiere's shows", async () => {
  const elcinema = result('elcinema', [
    show('elcinema:1', '2026-11-15', '12:00'), // Premiere has it at 11:00
    show('elcinema:1', '2026-11-19', '12:00'), // a day Premiere hasn't put on sale
    show('elcinema:2', '2026-11-15', '12:00'), // a film Premiere doesn't list there
    show('elcinema:1', '2026-11-15', '12:00', 'elcinema:sun-city'), // another cinema
  ]);
  const booking = result('elcinema-presales', [show('elcinema:1', '2026-11-16', '12:30')]);
  const results = [elcinema, booking, premiere];
  assert.deepEqual([...(await premiereBranches(results, null))], [p90]);
  assert.equal(leaveToPremiere(results, await premiereBranches(results, null)), 4);
  assert.deepEqual(left(elcinema), ['elcinema:sun-city 2026-11-15']);
  assert.deepEqual(left(booking), []);
  assert.equal(premiere.showtimes.length, 2);
});

test('without Premiere in the run or a database, elCinema keeps everything', async () => {
  const elcinema = result('elcinema', [show('elcinema:1', '2026-11-15', '12:00')]);
  assert.equal(leaveToPremiere([elcinema], await premiereBranches([elcinema], null)), 0);
  assert.equal(elcinema.showtimes.length, 1);
});
