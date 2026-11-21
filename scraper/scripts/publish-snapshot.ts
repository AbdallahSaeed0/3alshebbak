// `npx tsx scripts/publish-snapshot.ts` — rebuild the app's catalog file now,
// e.g. after a change sync's snapshotDue doesn't count (a show's booking link
// or format changed, with no show added or removed).

import { publishSnapshot, recordSnapshot } from '../src/snapshot.js';
import { supabaseFromEnv } from '../src/supabase.js';

try { process.loadEnvFile(); } catch { /* CI may supply the environment. */ }
const db = supabaseFromEnv();
if (!db) throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set');
const startedAt = new Date().toISOString();
const bytes = await publishSnapshot(db);
await recordSnapshot(db, startedAt, bytes);
console.log(`✓ snapshot: ${(bytes / 1e6).toFixed(1)} MB`);
