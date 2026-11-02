import assert from 'node:assert/strict';
import { test } from 'node:test';
import { dayFromLabel } from './time.js';

test('a day label without a year is the next such date', () => {
  assert.equal(dayFromLabel('Wednesday 16 Dec', '2026-11-02'), '2026-12-16');
  assert.equal(dayFromLabel('Monday 4 Jan', '2026-12-20'), '2027-01-04');
  // Last night's show is still this year.
  assert.equal(dayFromLabel('Sunday 1 Nov', '2026-11-02'), '2026-11-01');
  assert.equal(dayFromLabel('Showtimes', '2026-11-02'), null);
});
