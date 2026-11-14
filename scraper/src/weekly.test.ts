import assert from 'node:assert/strict';
import { test } from 'node:test';
import { ALL_CINEMAS } from './notify.js';
import { cairoClock, newFor, roundup, roundupTime } from './weekly.js';

test('Wednesday evening in Cairo, not before', () => {
  // 2026-11-18 is a Wednesday; Cairo is UTC+2 in November.
  assert.deepEqual(cairoClock(new Date('2026-11-18T15:30:00Z')), { weekday: 3, hour: 17 });
  assert.equal(roundupTime(new Date('2026-11-18T15:30:00Z')), true);
  assert.equal(roundupTime(new Date('2026-11-18T14:59:00Z')), false);
  assert.equal(roundupTime(new Date('2026-11-18T22:30:00Z')), false); // already Thursday in Cairo
  assert.equal(roundupTime(new Date('2026-11-19T16:00:00Z')), false);
});

test("a phone hears about its own cinemas' new films, the most shown first", () => {
  const shows = [
    { movie_id: 'a', cinema_id: 'scene:cfc' },
    { movie_id: 'b', cinema_id: 'scene:cfc' },
    { movie_id: 'b', cinema_id: 'scene:cfc' },
    { movie_id: 'c', cinema_id: 'vox:moe' },
  ];
  assert.deepEqual(newFor({ token: 't', following: [], cinemas: ['scene:cfc'] }, shows), ['b', 'a']);
  assert.deepEqual(newFor({ token: 't', following: [ALL_CINEMAS], cinemas: ['scene:cfc'] }, shows), ['b', 'a', 'c']);
  assert.deepEqual(newFor({ token: 't', following: [], cinemas: [] }, shows).length, 3);
  assert.deepEqual(newFor({ token: 't', following: [], cinemas: ['renaissance:downtown'] }, shows), []);
});

test('the roundup reads naturally', () => {
  assert.deepEqual(roundup(['Clayface']), {
    title: '🍿 فيلم جديد في السينمات الأسبوع ده',
    body: '«Clayface» في سينماتك',
  });
  assert.deepEqual(roundup(['A', 'B', 'C', 'D']), {
    title: '🍿 4 أفلام جداد في السينمات الأسبوع ده',
    body: '«A» و«B» وفيلمين كمان في سينماتك',
  });
});
