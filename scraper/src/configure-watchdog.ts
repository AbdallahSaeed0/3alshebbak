// Keep operational alerts independent of GitHub's dispatch credential.
import { supabaseFromEnv } from './supabase.js';
const db = supabaseFromEnv();
const firebase = process.env.FIREBASE_SERVICE_ACCOUNT;
if (!db || !firebase) throw new Error('Watchdog provisioning needs Supabase and Firebase credentials');
const { error } = await db.rpc('configure_pipeline_watchdog', {
  p_firebase: firebase, p_service_key: process.env.SUPABASE_SERVICE_ROLE_KEY,
});
if (error) throw new Error(`Watchdog provisioning: ${error.message}`);
console.log('Watchdog credentials configured in Vault');
