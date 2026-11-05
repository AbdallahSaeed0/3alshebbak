// Sends push notifications through Firebase Cloud Messaging (HTTP v1), signed
// with a service account — no Firebase SDK needed for this little.

import { createSign } from 'node:crypto';

type ServiceAccount = { project_id: string; client_email: string; private_key: string };

export type Push = { token: string; title: string; body: string; data?: Record<string, string> };

/** Thrown for a token FCM says is gone (app uninstalled, token rotated). */
export class StaleToken extends Error {}

export class Fcm {
  private constructor(private readonly account: ServiceAccount) {}

  private accessToken?: { value: string; expires: number };

  /** From FIREBASE_SERVICE_ACCOUNT (the key file's JSON); null when it isn't set. */
  static fromEnv(): Fcm | null {
    const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
    return raw ? new Fcm(JSON.parse(raw) as ServiceAccount) : null;
  }

  private async token(): Promise<string> {
    if (this.accessToken && this.accessToken.expires > Date.now() + 60_000) return this.accessToken.value;
    const now = Math.floor(Date.now() / 1000);
    const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');
    const unsigned = `${b64({ alg: 'RS256', typ: 'JWT' })}.${b64({
      iss: this.account.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    })}`;
    const signature = createSign('RSA-SHA256').update(unsigned).sign(this.account.private_key, 'base64url');
    const res = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: `${unsigned}.${signature}`,
      }),
    });
    if (!res.ok) throw new Error(`FCM auth: HTTP ${res.status} ${await res.text()}`);
    const { access_token, expires_in } = (await res.json()) as { access_token: string; expires_in: number };
    this.accessToken = { value: access_token, expires: Date.now() + expires_in * 1000 };
    return access_token;
  }

  async send(push: Push): Promise<void> {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${this.account.project_id}/messages:send`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${await this.token()}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: {
          token: push.token,
          notification: { title: push.title, body: push.body },
          data: push.data ?? {},
          // Kept by FCM for a phone that's offline (4 weeks, the most it
          // allows), and delivered when it's back, even with the app closed.
          android: { priority: 'high', ttl: '2419200s', notification: { notification_priority: 'PRIORITY_HIGH' } },
        },
      }),
    });
    if (res.ok) return;
    const text = await res.text();
    if (res.status === 404 || text.includes('UNREGISTERED')) throw new StaleToken(text);
    throw new Error(`FCM send: HTTP ${res.status} ${text}`);
  }
}
