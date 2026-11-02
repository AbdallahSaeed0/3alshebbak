// Reads the ignored local token file; never prints the credential.
import { readFile } from 'node:fs/promises';
import { supabaseFromEnv } from './supabase.js';
try { process.loadEnvFile(); } catch { /* CI may supply the environment. */ }
const token = (await readFile('.env.scheduler-token', 'utf8')).trim();
if (!token.startsWith('github_pat_') || /\s/.test(token)) throw new Error('Expected a fine-grained GitHub token only');
const endpoint = 'https://api.github.com/repos/AbdallahSaeed0/3alshebbak/actions/workflows/pipeline.yml';
const headers = { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' };
const workflow = await fetch(endpoint, { headers, signal: AbortSignal.timeout(15_000) });
if (!workflow.ok) throw new Error(`Token validation HTTP ${workflow.status}`);
const rawExpiry = workflow.headers.get('github-authentication-token-expiration');
const expiry = rawExpiry ? new Date(rawExpiry) : new Date(Date.now() + 90 * 86400_000);
if (!Number.isFinite(expiry.getTime())) throw new Error('Could not read token expiry');
const dispatch = await fetch(`${endpoint}/dispatches`, {
  method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' },
  body: JSON.stringify({ ref: 'main', inputs: { sources: 'vox' } }), signal: AbortSignal.timeout(15_000),
});
if (dispatch.status !== 204) throw new Error(`Token lacks working dispatch permission: HTTP ${dispatch.status}`);
const db = supabaseFromEnv();
if (!db) throw new Error('Missing Supabase credentials');
const { error } = await db.rpc('replace_scheduler_token', { p_token: token, p_expires_at: expiry.toISOString() });
if (error) throw new Error(`Token installation: ${error.message}`);
console.log(`Independent scheduler token validated and saved in Vault; expiry ${expiry.toISOString()}`);
