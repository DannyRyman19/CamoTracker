// Google's push service (Firebase Cloud Messaging, HTTP v1) for the Android
// app, signed in as the Firebase project's service account:
// FCM_SERVICE_ACCOUNT (secret) is that account's key file, the whole JSON.
//
// Android gets a data message, not a "notification" one: the app builds the
// notification itself (services/Push.kt), so the text, the tap link and the
// data refresh behave the same whether it is open, in the background or shut.

const b64url = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
let cached = null; // { token, project, at }

/** The service account from the secret, or null when it isn't set or isn't a key file. */
export function serviceAccount(env) {
  try {
    const a = JSON.parse(env.FCM_SERVICE_ACCOUNT);
    return a?.client_email && a?.private_key && a?.project_id ? a : null;
  } catch { return null; }
}

/** The signed request Google swaps for an access token (RS256, good for an hour). */
export async function assertion(account, now = Date.now()) {
  const pem = account.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const part = (o) => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const iat = Math.floor(now / 1000);
  const body = `${part({ alg: "RS256", typ: "JWT" })}.${part({
    iss: account.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token", iat, exp: iat + 3600,
  })}`;
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(body));
  return `${body}.${b64url(sig)}`;
}

/**
 * { token, project } to send with, kept for 50 minutes, or null when the
 * secret isn't set or Google refuses it (Android phones then count as failed
 * and keep their tokens).
 */
export async function access(env, now = Date.now(), fetchImpl = fetch) {
  if (cached && now - cached.at < 50 * 60 * 1000) return cached;
  const account = serviceAccount(env);
  if (!account) return null;
  const r = await fetchImpl("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: await assertion(account, now) }),
  });
  if (!r.ok) { console.log(`fcm token ${r.status}: ${(await r.text()).slice(0, 200)}`); return null; }
  cached = { token: (await r.json()).access_token, project: account.project_id, at: now };
  return cached;
}

/**
 * One push. Returns "sent", "gone" (Google says the token is dead: drop it)
 * or "failed" (anything else: keep the token, try again next time). Only
 * Google's own "this token is finished" answers drop a token: a request it
 * rejects for another reason must not empty the list.
 */
export async function push(auth, token, data, collapseId, fetchImpl = fetch) {
  if (!auth) return "failed";
  const android = { priority: "high" };
  if (collapseId) android.collapse_key = String(collapseId).slice(0, 64);
  const r = await fetchImpl(`https://fcm.googleapis.com/v1/projects/${auth.project}/messages:send`, {
    method: "POST", headers: { authorization: `Bearer ${auth.token}`, "content-type": "application/json" },
    body: JSON.stringify({ message: { token, data, android } }),
  });
  if (r.ok) return "sent";
  const reason = (await r.text()).slice(0, 300);
  if (r.status === 404 || /"UNREGISTERED"|SENDER_ID_MISMATCH/.test(reason)) return "gone";
  console.log(`fcm ${r.status}: ${reason}`);
  return "failed";
}
