// camo-track.app/api/push/*: Camo Track's content announcements as pushes.
//
//   POST /api/push/register    { token, sandbox, lang, version }   from the app
//        (the Android app adds platform: "android"; its token is Firebase's)
//   POST /api/push/unregister  { token }                           from the app
//   POST /api/push/send        { id, title, body, cursor }         from publish
//        (Authorization: Bearer PUSH_ADMIN_TOKEN): one page of phones, with
//        the cursor for the next; repeat until cursor is null
//   GET  /api/push/count       how many phones are registered (admin)
//
// Tokens live in KV (TOKENS) under "tok:<token>", with the phone's language
// and whether it's a development build. Nothing else about the phone or the
// player is kept.

import { register, unregister, sendPage } from "./push.js";
import { providerToken, push } from "./apns.js";
import { access, push as pushAndroid } from "./fcm.js";

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

async function body(request) {
  try { return await request.json(); } catch { return null; }
}

const admin = (request, env) => {
  const token = /^Bearer (.+)$/.exec(request.headers.get("authorization") ?? "")?.[1];
  return !!env.PUSH_ADMIN_TOKEN && token === env.PUSH_ADMIN_TOKEN;
};

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    const route = pathname.replace(/^\/api\/push/, "");
    if (request.method === "POST" && (route === "/register" || route === "/unregister")) {
      const b = await body(request);
      const r = route === "/register" ? await register(env.TOKENS, b) : await unregister(env.TOKENS, b);
      return r.error ? json(r, 400) : json(r);
    }
    if (route === "/send" && request.method === "POST") {
      if (!admin(request, env)) return json({ error: "Not allowed." }, 401);
      const b = await body(request);
      if (!b?.id || !b?.title || !b?.body) return json({ error: "Needs id, title and body." }, 400);
      const jwt = await providerToken(env);
      // Asked for once per page, and only when the page has an Android phone
      let google;
      return json(await sendPage(env.TOKENS, b, b.cursor, (device, payload, id) => device.android
        ? (google ??= access(env)).then((auth) => pushAndroid(auth, device.token, payload, id))
        : push(jwt, device, payload, id)));
    }
    if (route === "/count" && request.method === "GET") {
      if (!admin(request, env)) return json({ error: "Not allowed." }, 401);
      let n = 0, sandbox = 0, android = 0, cursor;
      do {
        const page = await env.TOKENS.list({ prefix: "tok:", cursor });
        n += page.keys.length; sandbox += page.keys.filter((k) => k.metadata?.s === 1).length;
        android += page.keys.filter((k) => k.metadata?.p === "a").length;
        cursor = page.list_complete ? null : page.cursor;
      } while (cursor);
      return json({ phones: n, sandbox, android });
    }
    return json({ error: "Not found." }, 404);
  },
};
