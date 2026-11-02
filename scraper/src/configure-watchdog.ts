// Keep operational alerts independent of GitHub's dispatch credential.
import { supabaseFromEnv } from './supabase.js';
const db = supabaseFromEnv();
const firebase = process.env.FIREBASE_SERVICE_ACCOUNT;
if (!db || !firebase) {
  console.warn('Watchdog provisioning skipped: credentials missing; existing Vault credentials remain active');
} else {
  const { error } = await db.rpc('configure_pipeline_watchdog', {
    p_firebase: firebase, p_service_key: process.env.SUPABASE_SERVICE_ROLE_KEY,
  });
  if (error) console.warn(`Watchdog provisioning failed: ${error.message}; continuing source updates`);
  else console.log('Watchdog credentials configured in Vault');
}
