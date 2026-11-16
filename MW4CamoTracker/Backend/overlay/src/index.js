// Camo Track's stream overlay: a Cloudflare Worker in front of a D1
// database. The app's half is Sources/StreamOverlay.swift.
//
//   PUT    /api/overlay/<id>   the app publishes a player's progress
//   DELETE /api/overlay/<id>   ...or takes it down
//   GET    /api/overlay/<id>   the figures, read by the overlay page
//   GET    /overlay/<id>       the page a streamer adds to OBS
//   GET    /go/<code>          the overlay's QR code: counts the scan, then
//                              sends the viewer to the App Store
//

import qrcode from "qrcode-generator";
import { OVERLAY, isToken, bearer, cleanOverlay, hashKey, hashIp, scanCode, isScanCode, qrSvg, APP_LINK } from "./overlay.js";
import { overlayPage, DEMO } from "./overlay-page.js";

const json = (status, body) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

// The overlay's figures are public to anyone with the link, so any origin may GET.
const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, OPTIONS",
  "cache-control": "no-store",
};

async function overlay(request, env, id) {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

  if (request.method === "GET") {
    const row = await env.DB.prepare("SELECT body, updated_at FROM overlays WHERE id = ?").bind(id).first();
    if (!row) return new Response(JSON.stringify({ message: "Not found." }), {
      status: 404, headers: { "content-type": "application/json", ...CORS },
    });
    const body = { ...JSON.parse(row.body), updatedAt: row.updated_at };
    return new Response(JSON.stringify(body), {
      headers: { "content-type": "application/json", ...CORS },
    });
  }

  if (request.method !== "PUT" && request.method !== "DELETE") return json(405, { message: "Not allowed." });
  const key = bearer(request.headers.get("authorization"));
  if (!key) return json(401, { message: "Missing key." });
  const keyHash = await hashKey(key);
  const existing = await env.DB.prepare("SELECT key_hash FROM overlays WHERE id = ?").bind(id).first();
  if (existing && existing.key_hash !== keyHash) return json(403, { message: "Wrong key." });

  if (request.method === "DELETE") {
    if (existing) await env.DB.prepare("DELETE FROM overlays WHERE id = ?").bind(id).run();
    return json(200, { message: "Removed." });
  }

  const raw = await request.text();
  if (raw.length > OVERLAY.maxBodyBytes) return json(413, { message: "That update is too large." });
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return json(400, { message: "That update couldn't be read." });
  }
  const result = cleanOverlay(parsed);
  if (!result.ok) return json(result.status, { message: result.message });
  const body = JSON.stringify(result.overlay);
  const now = new Date().toISOString();
  await rememberScanCode(env, id, result.channel, now);

  if (existing) {
    await env.DB.prepare("UPDATE overlays SET body = ?, updated_at = ? WHERE id = ?").bind(body, now, id).run();
    return json(200, { message: "Updated." });
  }
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  const ipHash = await hashIp(ip, env.IP_SALT ?? "");
  const dayAgo = new Date(Date.now() - 86_400_000).toISOString();
  const recent = await env.DB.prepare(
    "SELECT COUNT(*) AS n FROM overlays WHERE ip_hash = ? AND created_at > ?",
  ).bind(ipHash, dayAgo).first();
  if ((recent?.n ?? 0) >= OVERLAY.maxCreatedPerIpPerDay) {
    return json(429, { message: "Too many overlays from this connection. Try again later." });
  }
  await env.DB.prepare(
    "INSERT INTO overlays (id, key_hash, body, ip_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
  ).bind(id, keyHash, body, ipHash, now, now).run();
  return json(201, { message: "Created." });
}

// Labels this overlay's scan counts with the channel the streamer typed in
// the app (blank if they didn't). Kept when the overlay is switched off, so
// the counts stay attributed.
async function rememberScanCode(env, id, channel, now) {
  const code = await scanCode(id);
  await env.DB.prepare(
    "INSERT INTO scan_codes (code, channel, first_seen, last_seen) VALUES (?, ?, ?, ?) " +
    "ON CONFLICT(code) DO UPDATE SET channel = excluded.channel, last_seen = excluded.last_seen",
  ).bind(code, channel, now, now).run();
}

// A viewer scanned an overlay's QR code: one more for today, then on to the
// App Store. The demo's code isn't counted.
async function go(env, code) {
  if (code !== DEMO) {
    const day = new Date().toISOString().slice(0, 10);
    await env.DB.prepare(
      "INSERT INTO scans (code, day, n) VALUES (?, ?, 1) ON CONFLICT(code, day) DO UPDATE SET n = n + 1",
    ).bind(code, day).run();
  }
  return new Response(null, { status: 302, headers: { location: APP_LINK, "cache-control": "no-store" } });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    const feed = /^\/api\/overlay\/([^/]+)$/.exec(url.pathname);
    if (feed && isToken(feed[1])) return overlay(request, env, feed[1]);

    const scan = /^\/go\/([^/]+)$/.exec(url.pathname);
    if (scan && (isScanCode(scan[1]) || scan[1] === DEMO) && request.method === "GET") return go(env, scan[1]);

    const page = /^\/overlay\/([^/]+)$/.exec(url.pathname);
    if (page && (isToken(page[1]) || page[1] === DEMO) && request.method === "GET") {
      const code = page[1] === DEMO ? DEMO : await scanCode(page[1]);
      const qr = qrSvg(`${env.PUBLIC_ORIGIN || url.origin}/go/${code}`, qrcode);
      return new Response(overlayPage(page[1], qr), {
        headers: {
          "content-type": "text/html; charset=utf-8",
          "cache-control": "no-store",
          "x-content-type-options": "nosniff",
          "referrer-policy": "no-referrer",
        },
      });
    }
    return json(404, { message: "Not found." });
  },
};
