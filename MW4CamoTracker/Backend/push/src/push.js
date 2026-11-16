// Camo Track's content announcements as real pushes. The app registers its
// APNs token with its language; publish_data.py's announcement is then sent
// to every phone in its own language, a page at a time (the Workers free plan
// allows 50 outbound requests per request, so a page is 40 and the sender
// asks for the next page with the cursor until there's none).

export const LANGS = ["en", "fr", "es", "de", "it", "nl"];
export const PAGE = 40;
const PREFIX = "tok:";

const clean = (v, max) => (typeof v === "string" ? v.trim().slice(0, max) : "");

/** A registration from the app, or an error message. */
export function parseRegistration(body) {
  const token = clean(body?.token, 200).toLowerCase();
  if (!/^[0-9a-f]{64,200}$/.test(token)) return { error: "Not a device token." };
  const lang = LANGS.includes(body?.lang) ? body.lang : "en";
  return { token, meta: { s: body?.sandbox === true ? 1 : 0, l: lang, v: clean(body?.version, 16) } };
}

/** An announcement's text in `lang`, else English, else any language it has. */
export function localized(text, lang) {
  if (typeof text === "string") return text;
  if (!text || typeof text !== "object") return "";
  return text[lang] || text.en || Object.values(text).find((v) => typeof v === "string") || "";
}

/** What a phone in `lang` is sent for announcement `a` ({ id, title, body }). */
export function payload(a, lang) {
  return {
    aps: { alert: { title: localized(a.title, lang), body: localized(a.body, lang) }, sound: "default", "content-available": 1 },
    announcement: String(a.id ?? ""),
  };
}

export async function register(kv, body) {
  const r = parseRegistration(body);
  if (r.error) return r;
  await kv.put(PREFIX + r.token, "", { metadata: { ...r.meta, at: Date.now() } });
  return { ok: true };
}

export async function unregister(kv, body) {
  const r = parseRegistration(body);
  if (r.error) return r;
  await kv.delete(PREFIX + r.token);
  return { ok: true };
}

/**
 * Sends announcement `a` to one page of phones. Returns counts and the cursor
 * for the next page (null when every phone has had it). Dead tokens go.
 */
export async function sendPage(kv, a, cursor, send) {
  const list = await kv.list({ prefix: PREFIX, limit: PAGE, cursor: cursor || undefined });
  const out = { sent: 0, failed: 0, removed: 0, cursor: list.list_complete ? null : list.cursor };
  await Promise.all(list.keys.map(async ({ name, metadata }) => {
    const token = name.slice(PREFIX.length);
    const result = await send({ token, sandbox: metadata?.s === 1 }, payload(a, metadata?.l || "en"), a.id);
    if (result === "sent") out.sent += 1;
    else if (result === "gone") { out.removed += 1; await kv.delete(name); }
    else out.failed += 1;
  }));
  return out;
}
