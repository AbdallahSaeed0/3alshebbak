// Runs from Supabase Cron, independently of GitHub and its dispatch token.
const encoder = new TextEncoder();
const base64url = (value: string | Uint8Array) => btoa(typeof value === 'string' ? value : String.fromCharCode(...value)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

Deno.serve(async (request: Request) => {
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const url = Deno.env.get('SUPABASE_URL');
  if (!key || request.headers.get('Authorization') !== `Bearer ${key}`) return new Response('Unauthorized', { status: 401 });
  const rpc = async (name: string, args = {}) => {
    const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', 'Content-Profile': 'shebbak' },
      body: JSON.stringify(args), signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) throw new Error(`Watchdog database HTTP ${response.status}`);
    const text = await response.text();
    return text ? JSON.parse(text) : null;
  };
  try {
    const context = await rpc('pipeline_watchdog_context');
    if (context.signature === context.previous_signature) return Response.json({ status: 'unchanged' });
    if (!context.problems.length) {
      await rpc('ack_pipeline_watchdog', { p_signature: '' });
      return Response.json({ status: 'healthy' });
    }
    if (!context.device_token || !context.firebase) throw new Error('Watchdog recipient or Firebase credential missing');
    const account = JSON.parse(context.firebase);
    const now = Math.floor(Date.now() / 1000);
    const unsigned = `${base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${base64url(JSON.stringify({
      iss: account.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600,
    }))}`;
    const pem = account.private_key.replace(/-----[^-]+-----|\s/g, '');
    const signingKey = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(pem), c => c.charCodeAt(0)), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
    const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', signingKey, encoder.encode(unsigned));
    const auth = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${base64url(new Uint8Array(signature))}` }),
      signal: AbortSignal.timeout(15_000),
    });
    if (!auth.ok) throw new Error(`Watchdog Firebase auth HTTP ${auth.status}`);
    const { access_token } = await auth.json();
    const labels: Record<string, string> = { dispatch: 'تشغيل الفحص', vox: 'VOX', renaissance: 'رينيسانس', scene: 'Scene', elcinema: 'elCinema', premiere: 'بريمير', alerts: 'الإشعارات', token_expiry: 'صلاحية مفتاح GitHub' };
    const sent = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
      method: 'POST', headers: { Authorization: `Bearer ${access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: { token: context.device_token,
        notification: { title: 'عالشباك · محتاج مراجعة تحديث الداتا', body: `فيه تأخير أو مشكلة في: ${context.problems.map((p: string) => labels[p] ?? p).join('، ')}.` },
        data: { kind: 'pipeline_health' }, android: { priority: 'high' },
      } }), signal: AbortSignal.timeout(15_000),
    });
    if (!sent.ok) throw new Error(`Watchdog send HTTP ${sent.status}`);
    await rpc('ack_pipeline_watchdog', { p_signature: context.signature });
    return Response.json({ status: 'notified', problems: context.problems });
  } catch (error) {
    console.error(error instanceof Error ? error.message : 'Watchdog failed');
    return new Response('Watchdog failed; will retry next run', { status: 500 });
  }
});
