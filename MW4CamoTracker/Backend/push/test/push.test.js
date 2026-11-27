import { test } from "node:test";
import assert from "node:assert/strict";
import { parseRegistration, localized, payload, androidData, register, unregister, sendPage, PAGE } from "../src/push.js";
import { push as pushAndroid, serviceAccount } from "../src/fcm.js";
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
  assert.equal(parseRegistration({ token: tok(1), lang: "pt" }).meta.l, "pt");
  assert.equal(parseRegistration({ token: tok(1), lang: "xx" }).meta.l, "en");
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

// Android (Firebase)

const fcmTok = (n) => `fcm${n}:APA91b` + "Ab_-".repeat(35);

test("android registrations: Firebase's token kept as it is, marked as Android", () => {
  const r = parseRegistration({ platform: "android", token: fcmTok(1), lang: "fr", version: "1.0.1", sandbox: true });
  assert.equal(r.token, fcmTok(1));
  assert.deepEqual(r.meta, { s: 0, l: "fr", v: "1.0.1", p: "a" });
  assert.deepEqual(parseRegistration({ platform: "android", token: tok(1) }), { error: "Not a device token." });
  assert.deepEqual(parseRegistration({ platform: "android", token: fcmTok(1) + " x" }), { error: "Not a device token." });
  // An Apple token is still an Apple token
  assert.equal(parseRegistration({ token: tok(2) }).meta.p, undefined);
});

test("android data: the phone's language, strings only, the app's own links", () => {
  const a = { id: "mw4-1", title: { en: "Hi", de: "Hallo" }, body: { en: "New" }, link: "mw4camo://mode/current/event/1/102" };
  assert.deepEqual(androidData(a, "de"), { title: "Hallo", body: "New", announcement: "mw4-1", link: "mw4camo://mode/current/event/1/102" });
  assert.equal(androidData({ ...a, link: "https://example.com" }, "en").link, undefined);
});

test("a page with both kinds: each phone gets its own payload", async () => {
  const kv = fakeKV();
  await register(kv, { token: tok(1), lang: "de" });
  await register(kv, { platform: "android", token: fcmTok(1), lang: "fr" });
  const seen = [];
  const out = await sendPage(kv, { id: "x", title: { en: "T", fr: "Titre", de: "Titel" }, body: "B" }, null, async (device, p) => {
    seen.push([device.android, device.android ? p.title : p.aps.alert.title]);
    return "sent";
  });
  assert.equal(out.sent, 2);
  assert.deepEqual(seen.sort(), [[false, "Titel"], [true, "Titre"]]);
});

test("fcm: sent, a dead token is dropped, anything else keeps it, no key means failed", async () => {
  const auth = { token: "t", project: "camo-track" };
  const calls = [];
  const answer = (status, text = "{}") => async (url, init) => { calls.push([url, JSON.parse(init.body)]); return new Response(text, { status }); };
  assert.equal(await pushAndroid(auth, "abc", { title: "T" }, "id-1", answer(200)), "sent");
  assert.equal(calls[0][0], "https://fcm.googleapis.com/v1/projects/camo-track/messages:send");
  assert.deepEqual(calls[0][1], { message: { token: "abc", data: { title: "T" }, android: { priority: "high", collapse_key: "id-1" } } });
  assert.equal(await pushAndroid(auth, "abc", {}, null, answer(404, '{"error":{"details":[{"errorCode":"UNREGISTERED"}]}}')), "gone");
  assert.equal(await pushAndroid(auth, "abc", {}, null, answer(400, '{"error":{"status":"INVALID_ARGUMENT"}}')), "failed");
  assert.equal(await pushAndroid(auth, "abc", {}, null, answer(500)), "failed");
  assert.equal(await pushAndroid(null, "abc", {}, null, answer(200)), "failed");
});

test("fcm: the service account is read from the secret, or there is none", () => {
  assert.equal(serviceAccount({}), null);
  assert.equal(serviceAccount({ FCM_SERVICE_ACCOUNT: "not json" }), null);
  assert.equal(serviceAccount({ FCM_SERVICE_ACCOUNT: '{"client_email":"a@b"}' }), null);
  assert.equal(serviceAccount({ FCM_SERVICE_ACCOUNT: '{"client_email":"a@b","private_key":"k","project_id":"p"}' }).project_id, "p");
});
