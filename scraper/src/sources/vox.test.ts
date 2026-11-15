import assert from 'node:assert/strict';
import { test } from 'node:test';
import { hallName } from '../http.js';
import { splitTitle } from './vox.js';

test('an Infinity Vision listing is the same film in another format', () => {
  assert.deepEqual(splitTitle('Avengers: Doomsday (Infinity Vision)'), {
    title: 'Avengers: Doomsday',
    experience: 'Infinity Vision',
  });
  assert.deepEqual(splitTitle('Avengers: Doomsday'), { title: 'Avengers: Doomsday' });
});

test('hall names read like elCinema writes them', () => {
  assert.equal(hallName('GOLD'), 'Gold');
  assert.equal(hallName('PREMIUM'), 'Premium');
  assert.equal(hallName('IMAX'), 'IMAX');
  assert.equal(hallName('MAX VIP'), 'MAX VIP');
  assert.equal(hallName('MX4D'), 'MX4D');
  assert.equal(hallName(''), 'Standard');
});

test('Premiere formats read like elCinema writes them', async () => {
  const { premiereFormat } = await import('./premiere.js');
  assert.equal(premiereFormat('2D · PREMIUM'), 'Standard');
  assert.equal(premiereFormat('2D · MX4D'), 'MX4D');
  assert.equal(premiereFormat('2D · LUXE'), 'Luxe');
  assert.equal(premiereFormat('3D · IMAX'), '3D · IMAX');
});

test('a refusal is told apart from a passing fault', async () => {
  const { refused } = await import('./vox.js');
  assert.ok(refused('https://egy.voxcinemas.com/showtimes?c=x&d=1: HTTP 403'));
  assert.ok(refused('…: HTTP 429'));
  assert.ok(!refused('…: HTTP 500'));
  assert.ok(!refused('…: The operation was aborted due to timeout'));
});
