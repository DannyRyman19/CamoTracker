import { test } from "node:test";
import assert from "node:assert/strict";
import { parseRegistration, localized, payload, register, unregister, sendPage, PAGE } from "../src/push.js";
import { push } from "../src/apns.js";

// A Map-backed stand-in for a KV namespace: put with metadata, list by prefix with a cursor.
function fakeKV() {
  const m = new Map();
  return {
    m,
    async put(k, v, o = {}) { m.set(k, o.metadata); },
    async delete(k) { m.delete(k); },
    async list({ prefix, limit = 1000, cursor }) {
      const keys = [...m.keys()].filter((k) => k.startsWith(prefix)).sort();
      // Like KV's cursor: carry on after the last key returned, so deletes don't shift it.
      const after = cursor ? keys.filter((k) => k > cursor) : keys;
      const page = after.slice(0, limit);
      const done = page.length >= after.length;
      return { keys: page.map((name) => ({ name, metadata: m.get(name) })), list_complete: done, cursor: done ? undefined : page.at(-1) };
    },
  };
}
const tok = (n) => n.toString(16).padStart(64, "0");

test("registrations: a real token, a known language or English, and nothing else kept", () => {
  assert.deepEqual(parseRegistration({ token: "XYZ" }), { error: "Not a device token." });
  const r = parseRegistration({ token: tok(1).toUpperCase(), sandbox: true, lang: "de", version: "1.0.4", name: "Danny" });
  assert.equal(r.token, tok(1));
  assert.deepEqual(r.meta, { s: 1, l: "de", v: "1.0.4" });
  assert.equal(parseRegistration({ token: tok(1), lang: "pt" }).meta.l, "en");
});

test("text in the phone's language, else English", () => {
  const t = { en: "Hi", de: "Hallo" };
  assert.equal(localized(t, "de"), "Hallo");
  assert.equal(localized(t, "fr"), "Hi");
  assert.equal(localized("Plain", "fr"), "Plain");
  const p = payload({ id: "nc-1", title: t, body: { en: "Body" } }, "de");
  assert.deepEqual(p.aps.alert, { title: "Hallo", body: "Body" });
  assert.equal(p.aps["content-available"], 1);
  assert.equal(p.announcement, "nc-1");
  assert.equal(p.link, undefined);
  assert.equal(payload({ id: "x", title: "t", body: "b", link: "mw4camo://mode/current/event/1/102" }, "en").link, "mw4camo://mode/current/event/1/102");
  assert.equal(payload({ id: "x", title: "t", body: "b", link: "https://evil.example" }, "en").link, undefined);
});

test("register and unregister", async () => {
  const kv = fakeKV();
  await register(kv, { token: tok(1), lang: "fr" });
  assert.equal(kv.m.get(`tok:${tok(1)}`).l, "fr");
  await unregister(kv, { token: tok(1) });
  assert.equal(kv.m.size, 0);
});

test("sending goes a page at a time, in each phone's language, and drops dead tokens", async () => {
  const kv = fakeKV();
  for (let i = 0; i < PAGE + 5; i++) await register(kv, { token: tok(i), lang: i % 2 ? "de" : "en", sandbox: i === 0 });
  const seen = [];
  const send = async (device, p) => { seen.push([device, p.aps.alert.title]); return device.token === tok(3) ? "gone" : "sent"; };
  const a = { id: "a1", title: { en: "Live", de: "Live DE" }, body: "x" };
  const first = await sendPage(kv, a, null, send);
  assert.equal(first.sent + first.removed, PAGE);
  assert.ok(first.cursor);
  const rest = await sendPage(kv, a, first.cursor, send);
  assert.equal(rest.cursor, null);
  assert.equal(seen.length, PAGE + 5);
  assert.equal(first.removed + rest.removed, 1);
  assert.equal(kv.m.has(`tok:${tok(3)}`), false);
  assert.ok(seen.some(([d, t]) => d.token === tok(1) && t === "Live DE"));
  assert.ok(seen.some(([d]) => d.token === tok(0) && d.sandbox === true));
});

test("APNs: the right server and topic, and Apple's answers read", async () => {
  const calls = [];
  const fake = (status, text = "") => async (url, init) => { calls.push([url, init.headers]); return new Response(text, { status }); };
  assert.equal(await push("jwt", { token: tok(1), sandbox: true }, {}, "id", fake(200)), "sent");
  assert.match(calls[0][0], /^https:\/\/api\.sandbox\.push\.apple\.com\/3\/device\//);
  assert.equal(calls[0][1]["apns-topic"], "com.DannyRyman.MW4CamoTracker");
  assert.equal(await push("jwt", { token: tok(1), sandbox: false }, {}, null, fake(410)), "gone");
  assert.match(calls[1][0], /^https:\/\/api\.push\.apple\.com/);
  assert.equal(await push("jwt", { token: tok(1) }, {}, null, fake(400, '{"reason":"BadDeviceToken"}')), "gone");
  assert.equal(await push("jwt", { token: tok(1) }, {}, null, fake(500, "oops")), "failed");
});
