import { test } from 'node:test';
import assert from 'node:assert/strict';
import { bookingPairs } from './elcinema-presales.js';

test('booking inventory discovers presales separately for Americana and Arkan halls', () => {
  const html = ['3101133', '3101401', '3101402'].map(id => `<ul><li><h3><a href="/en/work/2097036/">Avengers: Doomsday</a></h3></li><li><a href="/en/booking/2097036/${id}/">tickets</a><a href="/en/booking/2097036/${id}/">tickets</a></li></ul>`).join('');
  const pairs = bookingPairs(html);
  assert.equal(pairs.length, 3);
  assert.deepEqual(pairs.map(p => p.theater), ['3101133', '3101401', '3101402']);
  assert.ok(pairs.every(p => p.title === 'Avengers: Doomsday' && p.work === '2097036'));
});
