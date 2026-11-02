import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { Fcm } from './fcm.js';
import { notifyDrops } from './notify.js';

test('a failed device retries after Cairo midnight without replaying successful devices', async (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: new Date('2026-11-02T21:50:00Z') });
  const reserved = new Set<string>();
  let checkpoints = 0;
  let attempts = 0;
  const progress = new Map<string, unknown>();
  const row = { movie_id: 'film', cinema_id: 'cinema', business_date: '2099-01-01', starts_at: '2099-01-01T19:00:00Z', first_seen_at: '2026-11-02T21:40:00Z' };
  const db = {
    from(table: string) {
      let operation = 'select';
      let previous = false;
      let fresh = false;
      let upsertRow: any;
      let insertRow: any;
      const filters: Record<string, string> = {};
      const result = () => {
        if (table === 'notification_progress') {
          if (upsertRow) progress.set(upsertRow.token, upsertRow);
          return { data: [...progress.values()], error: null };
        }
        if (table === 'notifications_sent') {
          const value = insertRow ?? filters;
          const key = `${value.token}|${value.sent_on}`;
          if (operation === 'delete') { reserved.delete(key); return { error: null }; }
          if (reserved.has(key)) return { error: { code: '23505' } };
          reserved.add(key);
          return { error: null };
        }
        if (table === 'scrape_runs') {
          if (operation === 'insert') checkpoints++;
          return { data: [], error: null };
        }
        if (table === 'showtimes_seen') return { data: previous ? [] : [row], error: null };
        if (table === 'devices') return { data: ['healthy', 'test'].map(token => ({ token, following: ['film'], cinemas: ['cinema'] })), error: null };
        return { data: [], error: null };
      };
      const query: any = {
        select: () => query, eq: (key: string, value: string) => { filters[key] = value; return query; }, order: () => query,
        gte: () => { fresh = true; return query; }, gt: () => query, in: () => query, overlaps: () => query,
        lt: (column: string) => { if (column === 'first_seen_at' && !fresh) previous = true; return query; },
        insert: (row: unknown) => { operation = 'insert'; insertRow = row; return query; },
        upsert: (row: unknown) => { upsertRow = row; return query; },
        delete: () => { operation = 'delete'; return query; },
        range: async () => result(), limit: async () => result(),
        then: (resolve: (value: unknown) => unknown, reject: (error: unknown) => unknown) => Promise.resolve(result()).then(resolve, reject),
      };
      return query;
    },
  } as unknown as SupabaseClient;
  const original = Fcm.fromEnv;
  const delivered: string[] = [];
  Fcm.fromEnv = () => ({ send: async ({token}: {token: string}) => {
    attempts++;
    if (token === 'test' && attempts === 2) throw new Error('temporary outage');
    delivered.push(token);
  } }) as unknown as Fcm;
  try {
    await assert.rejects(notifyDrops(db, '2026-11-02T00:00:00Z'), /checkpoint retained/);
    assert.equal(reserved.has('test|2026-11-02'), false);
    assert.equal(checkpoints, 0);
    assert.deepEqual(delivered, ['healthy']);
    t.mock.timers.setTime(new Date('2026-11-02T22:10:00Z').getTime());
    await notifyDrops(db, '2026-11-02T00:00:00Z');
    assert.equal(attempts, 3);
    assert.deepEqual(delivered, ['healthy', 'test']);
    assert.equal(checkpoints, 1);
    await notifyDrops(db, '2026-11-02T00:00:00Z');
    assert.equal(attempts, 3);
  } finally {
    Fcm.fromEnv = original;
  }
});
