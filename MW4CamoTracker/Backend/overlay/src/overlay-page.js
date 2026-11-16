// The page a streamer adds to OBS as a Browser source: GET /overlay/<id>.
// One self-contained document on a transparent background that polls the
// overlay's figures, with a QR code (`qr`, SVG markup made by index.js) to
// this overlay's /go/<code> link: the Worker counts the scan and sends the
// viewer on to the App Store. Everything from the feed goes in with
// textContent, and pictures only from camo-track.app (checked in overlay.js).
//
// Options, as query parameters:
//   ?layout=vertical  "card" (the default, wide), "vertical" (a tall column)
//                     or "minimal" (small, for a busy HUD)
//   ?style=glass      "camo" (the default: Camo Track's smoke and gold),
//                     "glass" (see-through, the game shows behind it) or
//                     "clean" (plain black and white)
//   ?qr=0             leave the QR code off (the "Tracked with Camo Track"
//                     line with the app icon is always there)
//   ?scale=1.5        bigger or smaller
//   ?align=right      line everything up on the right
//   ?celebrate=0      no banner and burst when a camo is earned
//
// /overlay/demo serves the same page with made-up figures that tick up, for
// trying a layout in OBS (?view=weapon for the weapon view).

export const DEMO = "demo";

export function overlayPage(id, qr) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Camo Track stream overlay</title>
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Saira+Condensed:wght@600;800&family=Inter:wght@500;600;700&display=swap">
<style>
:root{--panel:linear-gradient(135deg,rgba(23,19,13,.93),rgba(12,10,7,.93));--edge:rgba(255,200,30,.28);--radius:20px;--shadow:0 10px 30px rgba(0,0,0,.4);
  --ink:#F4EFE6;--muted:#B5AB98;--brand:#FFC81E;--track:rgba(255,255,255,.12);--glow:none;--dim:.28}
body.style-glass{--panel:rgba(12,12,16,.34);--edge:rgba(255,255,255,.34);--ink:#FFFFFF;--muted:rgba(255,255,255,.84);--brand:#FFFFFF;
  --track:rgba(255,255,255,.2);--shadow:none;--glow:0 1px 3px rgba(0,0,0,.75),0 0 12px rgba(0,0,0,.35)}
body.style-clean{--panel:#0F0F10;--edge:#2A2A2C;--radius:12px;--shadow:none;--ink:#FFFFFF;--muted:#9A9AA0;--brand:#FFFFFF;--track:#2E2E31}
*{box-sizing:border-box;margin:0;padding:0}
html,body{background:transparent;overflow:hidden;color:var(--ink);text-shadow:var(--glow);font-family:'Inter',-apple-system,'Segoe UI',sans-serif;-webkit-font-smoothing:antialiased}
body{padding:24px}
.stack{display:inline-flex;flex-direction:column;gap:12px;align-items:flex-start}
.panel{background:var(--panel);border:1px solid var(--edge);border-radius:var(--radius);box-shadow:var(--shadow)}
.display{font-family:'Saira Condensed','Arial Narrow',sans-serif;font-weight:800;text-transform:uppercase;line-height:.95;letter-spacing:.01em}
.main{display:flex;align-items:center;gap:18px;padding:16px 18px 14px 16px}
.body{min-width:0}
.head{font-size:13px;color:var(--muted)}
.head b{color:var(--accent);font-weight:700}
.title{font-size:26px;margin-top:3px}
.credit{display:flex;align-items:center;gap:7px;margin-top:9px;font-size:11px;letter-spacing:.06em;color:var(--brand);white-space:nowrap}
.credit img{width:20px;height:20px;border-radius:5px;flex:none}
.get{margin-left:6px;padding-left:20px;border-left:1px solid var(--edge);text-align:center;flex:none}
.qr{display:block;width:126px;height:126px;border-radius:10px;margin:0 auto;text-shadow:none}
.brand{margin-top:8px;font-size:12px;letter-spacing:.05em;color:var(--brand)}
.no-qr .get{display:none}
.hidden{display:none!important}
/* Overview: ring and ladder */
.ring{position:relative;width:104px;height:104px;flex:none}
.ring svg{width:100%;height:100%;transform:rotate(-90deg)}
.pct{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:28px}
.pct small{font-size:15px;margin-left:1px}
.ladder{display:flex;flex-wrap:wrap;gap:6px;margin-top:9px;max-width:400px}
.chip{display:flex;align-items:center;gap:6px;padding:4px 9px 4px 7px;border-radius:999px;background:rgba(255,255,255,.06);font-size:13px;font-weight:600;font-variant-numeric:tabular-nums}
.chip i{width:9px;height:9px;border-radius:50%;flex:none}
.chip span{color:var(--muted);font-weight:500}
.chip.done{background:rgba(255,255,255,.14)}
/* Weapon: picture, camo row, current challenge */
.gun{width:180px;height:92px;object-fit:contain;flex:none;filter:drop-shadow(0 4px 10px rgba(0,0,0,.5))}
.camos{display:flex;flex-wrap:wrap;gap:4px;margin-top:9px;max-width:400px}
.camos img,.camos b{width:26px;height:26px;border-radius:6px;object-fit:cover;opacity:var(--dim);filter:grayscale(.7);display:block;background:var(--track)}
.camos .on{opacity:1;filter:none;box-shadow:0 0 0 1.5px var(--accent)}
.next{margin-top:10px;max-width:400px}
.next .row{display:flex;justify-content:space-between;align-items:baseline;gap:12px;font-size:15px;font-weight:700}
.next .row span{color:var(--muted);font-weight:600;font-variant-numeric:tabular-nums}
.next p{font-size:13px;color:var(--muted);margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.bar{height:6px;border-radius:3px;background:var(--track);margin-top:6px;overflow:hidden}
.bar div{height:100%;background:var(--accent);border-radius:3px;transition:width .6s ease}
/* The line for a camo just earned */
.tick{display:flex;align-items:center;gap:11px;padding:10px 18px 10px 12px;font-size:18px;font-weight:700;opacity:0;transform:translateY(-12px);transition:opacity .5s ease,transform .5s ease;max-width:560px}
.tick.on{opacity:1;transform:none}
.tick img,.tick b{width:30px;height:30px;border-radius:7px;flex:none;background:var(--accent)}
.tick .what{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.pop{animation:pop .7s ease}
@keyframes pop{40%{transform:scale(1.08)}}
.burst{position:absolute;left:50%;top:50%;width:8px;height:8px;margin:-4px;border-radius:2px;pointer-events:none;animation:fly 1.5s cubic-bezier(.2,.7,.3,1) forwards}
@keyframes fly{to{transform:translate(var(--x),var(--y)) rotate(var(--r));opacity:0}}
.main{position:relative}
body.align-right{display:flex;justify-content:flex-end}
.align-right .stack{align-items:flex-end}
/* Tall column */
.layout-vertical .stack{align-items:center}
.layout-vertical .main{flex-direction:column;text-align:center;gap:12px;padding:20px 20px 18px;width:260px}
.layout-vertical .ring{width:132px;height:132px}
.layout-vertical .pct{font-size:36px}
.layout-vertical .ladder,.layout-vertical .camos{justify-content:center}
.layout-vertical .credit{justify-content:center}
.layout-vertical .next .row{justify-content:center;gap:8px}
.layout-vertical .gun{width:200px;height:100px}
.layout-vertical .get{margin:4px 0 0;padding:14px 0 0;border-left:0;border-top:1px solid var(--edge);width:100%}
.layout-vertical .tick{max-width:260px;font-size:15px}
/* Small */
.layout-minimal .main{gap:13px;padding:11px 16px 11px 12px;border-radius:16px}
.layout-minimal .ring{width:70px;height:70px}
.layout-minimal .pct{font-size:19px}
.layout-minimal .title{font-size:19px}
.layout-minimal .gun{width:110px;height:56px}
.layout-minimal .ladder .chip:not(.current),.layout-minimal .camos,.layout-minimal .next p{display:none}
.layout-minimal .next{margin-top:6px;width:220px}
.layout-minimal .qr{width:92px;height:92px}
.layout-minimal .brand{font-size:9px}
.layout-minimal .credit{margin-top:6px;font-size:9px;gap:5px}
.layout-minimal .credit img{width:15px;height:15px;border-radius:4px}
.layout-minimal .tick{font-size:14px;padding:8px 14px 8px 10px}
</style>
</head>
<body>
<div class="stack hidden">
  <div class="main panel">
    <div class="ring hidden"><svg viewBox="0 0 100 100"></svg><div class="pct display"></div></div>
    <img class="gun hidden" alt="">
    <div class="body">
      <div class="head"></div>
      <div class="title display"></div>
      <div class="ladder hidden"></div>
      <div class="camos hidden"></div>
      <div class="next hidden"><div class="row"><b></b><span></span></div><p></p><div class="bar"><div></div></div></div>
      <div class="credit display"><img src="https://camo-track.app/apple-touch-icon.png" alt="">Tracked with Camo Track</div>
    </div>
    <div class="get">
      ${qr}
      <div class="brand display">Scan to get it</div>
    </div>
  </div>
  <div class="tick panel"><b></b><div class="what"></div></div>
</div>
<script>
(function () {
  var ID = ${JSON.stringify(id)}, FEED = "/api/overlay/" + ID;
  var q = new URLSearchParams(location.search);
  var body = document.body;
  if (q.get("layout") === "vertical" || q.get("layout") === "minimal") body.classList.add("layout-" + q.get("layout"));
  if (q.get("style") === "glass" || q.get("style") === "clean") body.classList.add("style-" + q.get("style"));
  if (q.get("qr") === "0") body.classList.add("no-qr");
  if (q.get("align") === "right") body.classList.add("align-right");
  var scale = parseFloat(q.get("scale"));
  if (scale > 0.2 && scale < 6) body.style.zoom = scale;
  var celebrate = q.get("celebrate") !== "0";
  var $ = function (s) { return document.querySelector(s); };
  var NS = "http://www.w3.org/2000/svg", R = 42, LEN = 2 * Math.PI * R;
  var TRACK = getComputedStyle(body).getPropertyValue("--track").trim();

  function el(tag, cls, txt) { var e = document.createElement(tag); if (cls) e.className = cls; if (txt != null) e.textContent = txt; return e; }
  function swatch(src) {
    if (!src) return el("b");
    var img = el("img"); img.src = src; img.alt = ""; return img;
  }

  function ring(fraction, accent) {
    var svg = $(".ring svg");
    while (svg.firstChild) svg.removeChild(svg.firstChild);
    [[TRACK, LEN], [accent, LEN * Math.min(1, fraction)]].forEach(function (a) {
      if (a[1] <= 0) return;
      var c = document.createElementNS(NS, "circle");
      c.setAttribute("cx", 50); c.setAttribute("cy", 50); c.setAttribute("r", R);
      c.setAttribute("fill", "none"); c.setAttribute("stroke", a[0]); c.setAttribute("stroke-width", 10);
      c.setAttribute("stroke-linecap", "round");
      c.setAttribute("stroke-dasharray", a[1] + " " + (LEN - a[1]));
      svg.appendChild(c);
    });
    var pct = $(".pct"), whole = Math.floor(fraction * 100 + 1e-9);
    pct.textContent = whole;
    pct.appendChild(el("small", null, "%"));
  }

  // A camo just earned: its swatch and name for a few seconds, a pop and a burst.
  var tickTimer = null;
  function announce(text, src) {
    if (!celebrate) return;
    var t = $(".tick");
    t.replaceChild(swatch(src), t.firstChild);
    $(".what").textContent = text;
    t.classList.add("on");
    clearTimeout(tickTimer);
    tickTimer = setTimeout(function () { t.classList.remove("on"); }, 6500);
    var main = $(".main");
    main.classList.remove("pop"); void main.offsetWidth; main.classList.add("pop");
    var colors = ["#FFC81E", "#FF8A3D", "#FF4FA3", "#8B5CFF", "#26A0B5"];
    for (var i = 0; i < 24; i++) {
      var bit = el("i", "burst"), a = (i / 24) * Math.PI * 2, reach = 70 + Math.random() * 60;
      bit.style.background = colors[i % colors.length];
      bit.style.setProperty("--x", Math.cos(a) * reach + "px");
      bit.style.setProperty("--y", Math.sin(a) * reach + "px");
      bit.style.setProperty("--r", Math.round(Math.random() * 540 - 270) + "deg");
      main.appendChild(bit);
      setTimeout(function (b) { return function () { b.remove(); }; }(bit), 1600);
    }
  }

  var last = null;
  function render(d) {
    body.style.setProperty("--accent", d.accent || "#FFC81E");
    $(".head").textContent = "";
    $(".head").appendChild(el("b", null, d.game || ""));
    $(".head").appendChild(document.createTextNode(d.mode ? "  " + d.mode : ""));
    var isWeapon = d.view === "weapon" && d.weapon;
    $(".ring").classList.toggle("hidden", isWeapon);
    $(".ladder").classList.toggle("hidden", isWeapon);
    $(".gun").classList.toggle("hidden", !isWeapon || !d.weapon.image);
    $(".camos").classList.toggle("hidden", !isWeapon);
    $(".next").classList.toggle("hidden", !isWeapon || !d.weapon.next);

    if (isWeapon) {
      var w = d.weapon;
      if (w.image && $(".gun").getAttribute("src") !== w.image) $(".gun").src = w.image;
      $(".title").textContent = w.name;
      var row = $(".camos");
      row.textContent = "";
      w.camos.forEach(function (c) { var s = swatch(c.image); if (c.done) s.classList.add("on"); s.title = c.name; row.appendChild(s); });
      if (w.next) {
        $(".next b").textContent = w.next.name;
        $(".next span").textContent = w.next.total > 1 ? w.next.done + " / " + w.next.total : "";
        $(".next p").textContent = w.next.detail || "";
        $(".bar div").style.width = Math.min(100, (w.next.done / w.next.total) * 100) + "%";
      }
      // Newly earned camos on the same gun
      if (last && last.view === "weapon" && last.weapon && last.weapon.name === w.name) {
        w.camos.forEach(function (c, i) {
          var before = last.weapon.camos[i];
          if (c.done && before && !before.done) announce(c.name + " earned on the " + w.name, c.image);
        });
      }
    } else {
      var o = d.overview;
      ring(o.fraction, d.accent);
      $(".title").textContent = Math.floor(o.fraction * 100 + 1e-9) + "% complete";
      var ladder = $(".ladder");
      ladder.textContent = "";
      var current = o.steps.findIndex(function (s) { return s.done < s.total; });
      o.steps.concat(o.mastery || []).forEach(function (s, i) {
        var chip = el("div", "chip" + (s.done >= s.total ? " done" : "") + (i === current ? " current" : ""));
        var dot = el("i"); dot.style.background = s.color; chip.appendChild(dot);
        chip.appendChild(document.createTextNode(s.name + " "));
        chip.appendChild(el("span", null, s.done + "/" + s.total));
        ladder.appendChild(chip);
      });
      // A step that went up: one more weapon at that camo
      if (last && last.view !== "weapon" && last.overview && last.mode === d.mode) {
        o.steps.concat(o.mastery || []).forEach(function (s) {
          var before = last.overview.steps.concat(last.overview.mastery || []).filter(function (b) { return b.name === s.name; })[0];
          if (before && s.done > before.done) announce(s.name + "  " + s.done + "/" + s.total, "");
        });
      }
    }
    $(".stack").classList.remove("hidden");
    last = JSON.parse(JSON.stringify(d));
  }

  // Made-up figures for /overlay/demo: a camo earned every few seconds.
  var IMG = "https://camo-track.app/Images/";
  var demo = { n: 0 };
  function demoData() {
    var view = q.get("view") === "weapon" ? "weapon" : "overview";
    var names = ["Military 1", "Military 2", "Military 3", "Military 4", "Military 5", "Military 6", "Military 7", "Military 8", "Gold", "Platinum", "Harmonic Break", "Divergence"];
    var files = [1, 2, 3, 4, 5, 6, 7, 8].map(function (n) { return "Camos/MW4/military_" + n + ".png"; })
      .concat(["Camos/MW4/gold.png", "Camos/MW4/platinum.png", "Camos/MW4/harmonic_break.png", "Camos/MW4/divergence.png"]);
    var earned = 7 + (demo.n % 5);
    if (view === "weapon") return {
      view: view, game: "MW4", mode: "Warzone", accent: "#26A0B5",
      weapon: { name: "Kastov 762", category: "Assault Rifles", image: IMG + "Guns/MW4/KASTOV_762.png",
        camos: names.map(function (nm, i) { return { name: nm, image: IMG + files[i], done: i < earned }; }),
        done: earned, total: names.length,
        next: { name: names[earned] || "Done", detail: "Get 20 headshot kills", done: (demo.n * 3) % 20, total: 20 } },
    };
    var gold = 20 + (demo.n % 13);
    return {
      view: view, game: "MW4", mode: "Warzone", accent: "#26A0B5",
      overview: { fraction: 0.31 + demo.n * 0.004, weaponCount: 33,
        steps: [{ name: "Gold", done: gold, total: 33, color: "#E8B83A" }, { name: "Platinum", done: 9, total: 33, color: "#D9DEE6" },
                { name: "Harmonic Break", done: 2, total: 33, color: "#E0457B" }, { name: "Divergence", done: 0, total: 33, color: "#5AA9FF" }],
        mastery: [{ name: "Parallax", done: 0, total: 1, color: "#26A0B5" }] },
    };
  }

  function poll() {
    fetch(FEED, { cache: "no-store" })
      .then(function (r) {
        // Switched off in the app: clear the screen rather than freeze.
        if (r.status === 404) { $(".stack").classList.add("hidden"); return null; }
        return r.ok ? r.json() : null;
      })
      .then(function (d) { if (d) render(d); })
      .catch(function () { /* keep the last good figures */ });
  }
  if (ID === ${JSON.stringify(DEMO)}) {
    render(demoData());
    setInterval(function () { demo.n++; render(demoData()); }, 6000);
    return;
  }
  poll();
  setInterval(poll, 10000);
})();
</script>
</body>
</html>`;
}
