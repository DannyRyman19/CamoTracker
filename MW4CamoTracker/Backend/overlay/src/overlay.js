// Camo Track's stream overlay: the checks and the clean-up of what the app
// sends, apart from the Worker plumbing so they can be tested with plain Node
// (`npm test`). The app's half is Sources/StreamOverlay.swift.
//
// An overlay is a public id (in the link pasted into OBS) and a write key
// that never leaves the app. Whoever has the link can read the figures; only
// the app that made it can change or delete them.
//
// It shows one of two views, for whichever game and mode the streamer picked
// (every game the app tracks works the same way):
//   overview  the mode's completion ring, its Completionist camo ladder
//             (Gold, Platinum... each "weapons done / weapons") and its
//             Mastery camos
//   weapon    one gun: its picture, its camos as a row of swatches (lit
//             once earned) and the challenge it's on now, with the count

export const OVERLAY = {
  // Largest body accepted, in bytes. A real one is about 3 KB.
  maxBodyBytes: 24 * 1024,
  // New overlays one connection may create in a day.
  maxCreatedPerIpPerDay: 20,
  maxSteps: 8,
  maxCamos: 48,
};

const ID = /^[A-Za-z0-9_-]{20,64}$/;
const HEX = /^#?[0-9A-Fa-f]{6}$/;
// Pictures only from Camo Track's own image host (and Activision's), so an
// overlay can't be made to load anything else.
const IMAGE = /^https:\/\/(camo-track\.app\/Images|imgs\.callofduty\.com)\/[\w./%+-]{1,300}(\?[\w=&.-]{0,40})?$/;

/** Whether `value` could be an overlay id or write key. */
export function isToken(value) {
  return typeof value === "string" && ID.test(value);
}

/** The write key from an `Authorization: Bearer <key>` header, or null. */
export function bearer(header) {
  const match = /^Bearer\s+(\S+)$/.exec(String(header ?? ""));
  return match && isToken(match[1]) ? match[1] : null;
}

const count = (n) => (Number.isFinite(n) ? Math.min(Math.max(0, Math.round(n)), 1_000_000) : 0);
const unit = (n) => (Number.isFinite(n) ? Math.min(Math.max(0, n), 1) : 0);
// Text is only ever shown with textContent, never as HTML; this just bounds
// the length and drops control characters.
const text = (s, max) =>
  typeof s === "string" ? s.replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, max) : "";
const color = (c, fallback) => (HEX.test(String(c ?? "")) ? "#" + String(c).replace("#", "").toUpperCase() : fallback);
const image = (u) => (typeof u === "string" && IMAGE.test(u) ? u : "");

const step = (s) => ({ name: text(s?.name, 30), done: count(s?.done), total: Math.max(1, count(s?.total)), color: color(s?.color, "#FFC81E") });

function cleanOverview(o) {
  if (!o || typeof o !== "object") return null;
  return {
    fraction: unit(o.fraction),
    weaponCount: count(o.weaponCount),
    steps: (Array.isArray(o.steps) ? o.steps : []).slice(0, OVERLAY.maxSteps).map(step).filter((s) => s.name),
    mastery: (Array.isArray(o.mastery) ? o.mastery : []).slice(0, OVERLAY.maxSteps).map(step).filter((s) => s.name),
  };
}

function cleanWeapon(w) {
  if (!w || typeof w !== "object" || !text(w.name, 40)) return null;
  const next = w.next && typeof w.next === "object" && text(w.next.name, 40)
    ? { name: text(w.next.name, 40), detail: text(w.next.detail, 140), done: count(w.next.done), total: Math.max(1, count(w.next.total)) }
    : null;
  return {
    name: text(w.name, 40),
    category: text(w.category, 40),
    image: image(w.image),
    camos: (Array.isArray(w.camos) ? w.camos : []).slice(0, OVERLAY.maxCamos)
      .map((c) => ({ name: text(c?.name, 40), image: image(c?.image), done: c?.done === true }))
      .filter((c) => c.name),
    done: count(w.done),
    total: count(w.total),
    next,
  };
}

/**
 * Checks a body from the app. Returns { ok: true, overlay, channel } with
 * only the fields the overlay page reads, or { ok: false, status, message }.
 */
export function cleanOverlay(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, status: 400, message: "That update couldn't be read." };
  }
  const view = body.view === "weapon" ? "weapon" : "overview";
  const overview = cleanOverview(body.overview);
  const weapon = cleanWeapon(body.weapon);
  if (view === "overview" && !overview) return { ok: false, status: 422, message: "That update is missing its figures." };
  if (view === "weapon" && !weapon) return { ok: false, status: 422, message: "That update is missing its weapon." };
  return {
    ok: true,
    // Kept apart from the figures: it labels the QR scan counts, never shown.
    channel: cleanChannel(body.channel),
    overlay: {
      v: 1,
      view,
      game: text(body.game, 12),
      mode: text(body.mode, 30),
      accent: color(body.accent, "#FFC81E"),
      overview: view === "overview" ? overview : null,
      weapon: view === "weapon" ? weapon : null,
    },
  };
}

/**
 * The streamer's channel name as they typed it, if they did: letters,
 * digits, underscores, dots and dashes, without a leading @. Only used to
 * label scan counts; empty when missing or unusable.
 */
export function cleanChannel(value) {
  if (typeof value !== "string") return "";
  const name = value.trim().replace(/^@+/, "");
  return /^[A-Za-z0-9_.-]{1,40}$/.test(name) ? name : "";
}

const SCAN_CODE = /^[0-9a-f]{12}$/;

/**
 * The short code in an overlay's QR link (/go/<code>). Derived from the id,
 * so it survives the overlay being switched off and on, but can't be turned
 * back into the id: a viewer who scans it can't open the streamer's feed.
 */
export async function scanCode(id) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`scan:${id}`));
  return [...new Uint8Array(digest)].slice(0, 6).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export const isScanCode = (value) => typeof value === "string" && SCAN_CODE.test(value);

/** The App Store link a scan lands on: Camo Track's stream-overlay campaign. */
export const APP_LINK = "https://apps.apple.com/app/id6775247927?pt=121683099&mt=8&ct=stream-overlay";

/**
 * A QR code for `url` as SVG markup, one square per dark module on a light
 * square with a two-module border. Error correction M: a code on a screen is
 * never scuffed, and fewer, bigger modules scan more easily off a stream.
 */
export function qrSvg(url, qrcode) {
  const qr = qrcode(0, "M");
  qr.addData(url);
  qr.make();
  const n = qr.getModuleCount();
  const size = n + 4;
  let path = "";
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) if (qr.isDark(y, x)) path += `M${x + 2} ${y + 2}h1v1h-1z`;
  }
  return `<svg class="qr" role="img" aria-label="QR code to Camo Track on the App Store" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${size} ${size}" shape-rendering="crispEdges"><path fill="#ffffff" d="M0 0h${size}v${size}h-${size}z"/><path fill="#0c0a07" d="${path}"/></svg>`;
}

/** SHA-256 of the IP plus a secret salt: enough to spot bulk creation, not an address. */
export async function hashIp(ip, salt) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${salt}:${ip}`));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** SHA-256 of the write key, as stored: the key itself is never kept. */
export async function hashKey(key) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(key));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
