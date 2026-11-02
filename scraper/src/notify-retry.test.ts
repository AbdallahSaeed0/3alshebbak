import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { Fcm } from './fcm.js';
import { notifyDrops } from './notify.js';

test('a failed push is retried next run, while a delivered push is deduplicated', async () => {
  let reserved = false;
  let checkpoints = 0;
  let attempts = 0;
  const row = { movie_id: 'film', cinema_id: 'cinema', business_date: '2099-01-01', starts_at: '2099-01-01T19:00:00Z' };
  const db = {
    from(table: string) {
      let operation = 'select';
      let previous = false;
      let fresh = false;
      const result = () => {
        if (table === 'notifications_sent') {
          if (operation === 'delete') { reserved = false; return { error: null }; }
          if (reserved) return { error: { code: '23505' } };
          reserved = true;
          return { error: null };
        }
        if (table === 'scrape_runs') {
          if (operation === 'insert') checkpoints++;
          return { data: [], error: null };
        }
        if (table === 'showtimes_seen') return { data: previous ? [] : [row], error: null };
        if (table === 'devices') return { data: [{ token: 'test', following: ['film'], cinemas: ['cinema'] }], error: null };
        return { data: [], error: null };
      };
      const query: any = {
        select: () => query, eq: () => query, order: () => query,
        gte: () => { fresh = true; return query; }, gt: () => query, in: () => query, overlaps: () => query,
        lt: (column: string) => { if (column === 'first_seen_at' && !fresh) previous = true; return query; },
        insert: () => { operation = 'insert'; return query; },
        delete: () => { operation = 'delete'; return query; },
        range: async () => result(), limit: async () => result(),
        then: (resolve: (value: unknown) => unknown, reject: (error: unknown) => unknown) => Promise.resolve(result()).then(resolve, reject),
      };
      return query;
    },
  } as unknown as SupabaseClient;
  const original = Fcm.fromEnv;
  Fcm.fromEnv = () => ({ send: async () => { if (++attempts === 1) throw new Error('temporary outage'); } }) as unknown as Fcm;
  try {
    await assert.rejects(notifyDrops(db, '2026-11-02T00:00:00Z'), /checkpoint retained/);
    assert.equal(reserved, false);
    assert.equal(checkpoints, 0);
    await notifyDrops(db, '2026-11-02T00:00:00Z');
    assert.equal(attempts, 2);
    assert.equal(checkpoints, 1);
    await notifyDrops(db, '2026-11-02T00:00:00Z');
    assert.equal(attempts, 2);
  } finally {
    Fcm.fromEnv = original;
  }
});
