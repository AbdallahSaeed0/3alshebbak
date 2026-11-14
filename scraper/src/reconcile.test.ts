import assert from 'node:assert/strict';
import { test } from 'node:test';
import { reconcileDrops, type Row } from './supabase.js';

// The same rules run in the database (20261114150000_reconcile_in_database.sql);
// these cases were checked against it with the same rows and clock.
const now = Date.parse('2026-11-14T12:00:00Z');
const at = (hours: number) => new Date(now + hours * 3600e3).toISOString();
function rows(...list: [string, string, string, string, string, number][]): Row[] {
  return list.map(([id, source, movie_id, cinema_id, business_date, h]) => ({
    id, source, movie_id, cinema_id, business_date, starts_at: at(h),
  }));
}

test('the booking page takes the days it covers, for films it sells there', () => {
  const drop = reconcileDrops(
    rows(
      ['b1', 'elcinema-presales', 'A', 'elcinema:c1', '2026-11-15', 24],
      ['e1', 'elcinema', 'A', 'elcinema:c1', '2026-11-15', 26], // goes
      ['e2', 'elcinema', 'A', 'elcinema:c1', '2026-11-16', 50], // day not covered
      ['e3', 'elcinema', 'B', 'elcinema:c1', '2026-11-15', 27], // film not sold online
    ),
    now,
  );
  assert.deepEqual(drop, ['e1']);
});

test('a film sold earlier in the fortnight still counts; a past booking day does not', () => {
  const drop = reconcileDrops(
    rows(
      ['b1', 'elcinema-presales', 'C', 'elcinema:c2', '2026-11-10', -96],
      ['b2', 'elcinema-presales', 'Z', 'elcinema:c2', '2026-11-15', 25],
      ['e1', 'elcinema', 'C', 'elcinema:c2', '2026-11-15', 28], // goes
      ['b3', 'elcinema-presales', 'D', 'elcinema:c3', '2026-11-13', -20],
      ['e2', 'elcinema', 'D', 'elcinema:c3', '2026-11-13', 1],
    ),
    now,
  );
  assert.deepEqual(drop, ['e1']);
});

test("VOX's own page takes the film's day; Premiere keeps a show the booking page also lists", () => {
  const drop = reconcileDrops(
    rows(
      ['v1', 'vox', 'E', 'elcinema:c4', '2026-11-15', 30],
      ['e1', 'elcinema', 'E', 'elcinema:c4', '2026-11-15', 31], // goes
      ['e2', 'elcinema', 'E', 'elcinema:c4', '2026-11-17', 75],
      ['v2', 'vox', 'F', 'elcinema:c4', '2026-11-14', -2], // already started
      ['e3', 'elcinema', 'F', 'elcinema:c4', '2026-11-14', 3],
      ['p1', 'premiere', 'G', 'elcinema:c5', '2026-11-15', 33],
      ['b1', 'elcinema-presales', 'G', 'elcinema:c5', '2026-11-15', 33], // goes
      ['b2', 'elcinema-presales', 'G', 'elcinema:c5', '2026-11-15', 34],
      ['v3', 'vox', 'H', 'elcinema:c6', '2026-11-14', -5],
      ['e4', 'elcinema', 'H', 'elcinema:c6', '2026-11-14', -4], // past: left alone
    ),
    now,
  );
  assert.deepEqual(drop.sort(), ['b1', 'e1']);
});
