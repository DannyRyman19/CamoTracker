// Apple's push service (APNs), signed with the team's APNs auth key:
// APNS_KEY_P8 (secret), APNS_KEY_ID and APNS_TEAM_ID (vars). Development
// builds register as sandbox and are sent through Apple's sandbox server.

export const TOPIC = "com.DannyRyman.MW4CamoTracker";

const b64url = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
let cached = null; // { jwt, at }

/** A provider token: ES256, remade every 50 minutes (Apple wants it reused, for up to an hour). */
export async function providerToken(env, now = Date.now()) {
  if (cached && now - cached.at < 50 * 60 * 1000) return cached.jwt;
  const pem = env.APNS_KEY_P8.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const part = (o) => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const body = `${part({ alg: "ES256", kid: env.APNS_KEY_ID })}.${part({ iss: env.APNS_TEAM_ID, iat: Math.floor(now / 1000) })}`;
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(body));
  cached = { jwt: `${body}.${b64url(sig)}`, at: now };
  return cached.jwt;
}

/**
 * One push. Returns "sent", "gone" (Apple says the token is dead: drop it) or
 * "failed" (anything else: keep the token, try again next time).
 */
export async function push(jwt, { token, sandbox }, payload, collapseId, fetchImpl = fetch) {
  const host = sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const headers = {
    authorization: `bearer ${jwt}`, "apns-topic": TOPIC, "apns-push-type": "alert", "apns-priority": "10",
    "content-type": "application/json",
  };
  if (collapseId) headers["apns-collapse-id"] = String(collapseId).slice(0, 64);
  const r = await fetchImpl(`https://${host}/3/device/${token}`, { method: "POST", headers, body: JSON.stringify(payload) });
  if (r.ok) return "sent";
  const reason = (await r.text()).slice(0, 200);
  if (r.status === 410 || /BadDeviceToken|Unregistered|DeviceTokenNotForTopic/.test(reason)) return "gone";
  console.log(`apns ${r.status}: ${reason}`);
  return "failed";
}
