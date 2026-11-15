import assert from 'node:assert/strict';
import { test } from 'node:test';
import { applyHallHints } from './hall-hints.js';
import type { ScrapeResult, Showtime } from './model.js';

const p90 = 'elcinema:premiere-point90';
const show = (filmId: string, start: string, hall?: string): Showtime => ({
  cinemaId: p90, filmId, businessDate: start.slice(0, 10), start, format: 'Standard', ...(hall ? { hall } : {}),
});
const result = (source: ScrapeResult['source'], showtimes: Showtime[], hallHints?: ScrapeResult['hallHints']): ScrapeResult => ({
  source, fetchedAt: '2026-11-15T10:00:00Z', cinemas: [], films: [], showtimes, warnings: [], ...(hallHints ? { hallHints } : {}),
});

test("Premiere's halls reach elCinema's shows of the same movie and start", () => {
  const films = { 'elcinema:1': 'tmdb:9', 'premiere:5.1': 'tmdb:9', 'elcinema:2': 'tmdb:8', 'premiere:6.1': 'tmdb:8' };
  const elcinema = result('elcinema', [
    show('elcinema:1', '2026-11-15T18:45:00+02:00'),
    show('elcinema:1', '2026-11-15T21:30:00+02:00'), // no hint: stays unknown
    show('elcinema:2', '2026-11-15T18:45:00+02:00'), // other movie, same start
    show('elcinema:2', '2026-11-15T20:00:00+02:00', 'elcinema:77'), // has its own
  ]);
  const premiere = result('premiere', [], [
    { cinemaId: p90, filmId: 'premiere:5.1', start: '2026-11-15T18:45:00+02:00', hall: 'prm:4:12' },
    { cinemaId: p90, filmId: 'premiere:6.1', start: '2026-11-15T16:45:00Z', hall: 'prm:4:3' }, // same instant
    { cinemaId: p90, filmId: 'premiere:6.1', start: '2026-11-15T20:00:00+02:00', hall: 'prm:4:5' },
  ]);
  assert.equal(applyHallHints([elcinema, premiere], films), 2);
  assert.deepEqual(elcinema.showtimes.map((s) => s.hall), ['prm:4:12', undefined, 'prm:4:3', 'elcinema:77']);
});

test('hints that disagree on a start are dropped', () => {
  const films = { 'elcinema:1': 'tmdb:9', 'premiere:5.1': 'tmdb:9' };
  const elcinema = result('elcinema', [show('elcinema:1', '2026-11-15T19:00:00+02:00')]);
  const premiere = result('premiere', [], [
    { cinemaId: p90, filmId: 'premiere:5.1', start: '2026-11-15T19:00:00+02:00', hall: 'prm:4:1' },
    { cinemaId: p90, filmId: 'premiere:5.1', start: '2026-11-15T19:00:00+02:00', hall: 'prm:4:2' },
  ]);
  assert.equal(applyHallHints([elcinema, premiere], films), 0);
});
