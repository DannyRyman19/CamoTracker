import { test } from "node:test";
import assert from "node:assert/strict";
import qrcode from "qrcode-generator";
import { cleanOverlay, cleanChannel, isToken, bearer, scanCode, isScanCode, qrSvg, OVERLAY } from "../src/overlay.js";
import { overlayPage } from "../src/overlay-page.js";

const overview = {
  view: "overview", game: "MW4", mode: "Warzone", accent: "#26a0b5", channel: "@Streamer_1",
  overview: { fraction: 0.42, weaponCount: 33, steps: [{ name: "Gold", done: 28, total: 33, color: "E8B83A" }], mastery: [{ name: "Parallax", done: 0, total: 1 }] },
};
const weapon = {
  view: "weapon", game: "BO6", mode: "Zombies", accent: "#8CC63F",
  weapon: {
    name: "XM4", category: "Assault Rifles", image: "https://camo-track.app/Images/BO6/xm4.png",
    camos: [{ name: "Gold", image: "https://camo-track.app/Images/Camos/BO6/gold.png", done: true }, { name: "Diamond", image: "https://evil.example/x.png", done: false }],
    done: 1, total: 2, next: { name: "Diamond", detail: "Get 3 Gold", done: 1, total: 3 },
  },
};

test("an overview is kept, in its own fields only", () => {
  const r = cleanOverlay({ ...overview, extra: "dropped" });
  assert.equal(r.ok, true);
  assert.equal(r.channel, "Streamer_1");
  assert.equal(r.overlay.accent, "#26A0B5");
  assert.equal(r.overlay.weapon, null);
  assert.deepEqual(r.overlay.overview.steps[0], { name: "Gold", done: 28, total: 33, color: "#E8B83A" });
  assert.equal(r.overlay.overview.mastery[0].color, "#FFC81E");
  assert.equal("extra" in r.overlay, false);
});

test("a weapon keeps its camos; pictures only from camo-track.app", () => {
  const r = cleanOverlay(weapon);
  assert.equal(r.ok, true);
  assert.equal(r.overlay.view, "weapon");
  assert.equal(r.overlay.overview, null);
  assert.equal(r.overlay.weapon.image, "https://camo-track.app/Images/BO6/xm4.png");
  assert.equal(r.overlay.weapon.camos[0].done, true);
  assert.equal(r.overlay.weapon.camos[1].image, "");
  assert.equal(r.overlay.weapon.next.total, 3);
});

test("broken or empty updates are turned away; sizes are bounded", () => {
  assert.equal(cleanOverlay(null).status, 400);
  assert.equal(cleanOverlay({ view: "weapon" }).status, 422);
  assert.equal(cleanOverlay({ view: "overview" }).status, 422);
  const many = { ...weapon, weapon: { ...weapon.weapon, name: "x".repeat(200), camos: Array.from({ length: 200 }, (_, i) => ({ name: `C${i}` })) } };
  const r = cleanOverlay(many);
  assert.equal(r.overlay.weapon.name.length, 40);
  assert.equal(r.overlay.weapon.camos.length, OVERLAY.maxCamos);
});

test("ids, keys, channels and scan codes", async () => {
  assert.equal(isToken("short"), false);
  assert.equal(isToken("a".repeat(24)), true);
  assert.equal(bearer("Bearer " + "k".repeat(30)), "k".repeat(30));
  assert.equal(bearer("Basic xyz"), null);
  assert.equal(cleanChannel("bad name!"), "");
  const code = await scanCode("a".repeat(24));
  assert.equal(isScanCode(code), true);
  assert.equal(code, await scanCode("a".repeat(24)));
});

test("the page: QR, credit, layouts, styles and options", () => {
  const page = overlayPage("a".repeat(24), qrSvg("https://camo-track.app/go/0123456789ab", qrcode));
  for (const s of ['class="qr"', "Tracked with Camo Track", "Scan to get it", 'q.get("qr") === "0"', "layout-vertical", "layout-minimal", "style-glass", "style-clean", "celebrate"]) {
    assert.ok(page.includes(s), s);
  }
  // Feed text goes in with textContent, never innerHTML
  assert.ok(!page.includes("innerHTML"));
});
