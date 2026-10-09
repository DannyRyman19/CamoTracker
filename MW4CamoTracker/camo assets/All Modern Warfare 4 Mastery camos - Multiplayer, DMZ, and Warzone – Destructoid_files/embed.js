(function () {
  "use strict";
  var ORIGIN = document.currentScript
    ? new URL(document.currentScript.src).origin
    : "https://census.gamurs.group";

  /**
   * Default styling, injected once.
   *
   * Every colour reads a GAMURS theme token first and falls back to a neutral
   * of its own: --text1, --bg2, --border1 and friends are the network's
   * semantic variables, redefined per theme by the site's own light.css /
   * dark.css. So on a network property the poll simply is the site's colours,
   * in whichever theme the reader picked, with no per-site CSS to maintain.
   *
   * Everything is wrapped in :where() so it carries zero specificity — a
   * property overrides any of it with a single plain selector, which is the
   * point: this is a floor, not a design system.
   */
  var CSS = [
    // Scoped to --ready, which render() adds. A property may declare more slots
    // than get filled — a rail slot and an in-content slot, one of them empty —
    // and styling .census-poll alone would draw a bordered empty card wherever
    // a campaign did not match.
    '.census-poll--ready{',
    '  --census-bg: var(--bg2, #f6f7f9);',
    '  --census-fg: var(--text1, #16181d);',
    '  --census-muted: var(--text3, #5d6470);',
    // NOT var(--border1): destructoid's light theme defines --border1 and --bg2
    // as the same token, so borrowing it draws background-on-background and the
    // answer outlines disappear. Deriving from the foreground is contrasty on
    // any palette, in either theme, without knowing the site's tokens.
    '  --census-line: color-mix(in srgb, var(--census-fg) 16%, transparent);',
    '  --census-accent: var(--text-link, #2f6feb);',
    '  --census-fill: color-mix(in srgb, var(--census-accent) 18%, transparent);',
    '  background: var(--census-bg); color: var(--census-fg);',
    '  border: 1px solid var(--census-line); border-radius: 12px;',
    '  padding: 1.1rem 1.15rem 0.9rem; margin: 1.75rem 0;',
    '  font-family: inherit; font-size: 1rem; line-height: 1.45;',
    '}',
    // Dark fallback for sites that expose no tokens. Applied from a measurement
    // of the page's actual background (see darkSurface), NOT from
    // prefers-color-scheme: a light-only site read by someone whose OS is set
    // to dark would otherwise get a dark card sitting on a white page.
    '.census-poll--ready.census-poll--dark{',
    '  --census-bg: var(--bg2, #1b1d22);',
    '  --census-fg: var(--text1, #f2f4f7);',
    '  --census-muted: var(--text3, #9aa3b2);',
    '  --census-accent: var(--text-link, #6ea8ff);',
    '}',
    // Header strip. The card was reading as an unexplained grey box between an
    // article and an ad; a titled band with a rule under it makes it a module.
    '.census-poll--ready .census-poll__eyebrow{',
    '  display: flex; align-items: center; gap: .4rem;',
    '  margin: 0 0 .7rem; padding: 0 0 .6rem;',
    '  border-bottom: 1px solid var(--census-line);',
    '  font-size: .7rem; font-weight: 800; letter-spacing: .1em;',
    '  text-transform: uppercase; color: var(--census-accent);',
    '}',
    // A three-bar chart glyph, drawn rather than fetched — no request, no
    // layout shift, and it inherits the accent colour for free.
    '.census-poll--ready .census-poll__glyph{',
    '  display: inline-flex; align-items: flex-end; gap: 2px; height: .72rem;',
    '}',
    '.census-poll--ready .census-poll__glyph i{',
    '  display: block; width: 3px; background: currentColor; border-radius: 1px;',
    '}',
    '.census-poll--ready .census-poll__glyph i:nth-child(1){ height: 45%; }',
    '.census-poll--ready .census-poll__glyph i:nth-child(2){ height: 100%; }',
    '.census-poll--ready .census-poll__glyph i:nth-child(3){ height: 70%; }',
    '.census-poll--ready .census-poll__question{',
    '  margin: 0 0 .8rem; font-weight: 700; font-size: 1.06rem;',
    '  line-height: 1.28; letter-spacing: -.01em;',
    '}',
    // Full specificity, not :where(). A zero-specificity reset loses to the
    // host theme's own list rules — on destructoid that meant the answers
    // rendered indented by the theme's ul padding.
    '.census-poll--ready .census-poll__answers{',
    '  list-style: none; margin: 0; padding: 0;',
    '}',
    // :not(.census-poll__result) matters: this rule is more specific than the
    // result-row rule below, so a blanket padding: 0 here silently strips the
    // result rows' own padding and the text ends up flush against the pill.
    '.census-poll--ready .census-poll__answers li:not(.census-poll__result){',
    '  margin: 0 0 .35rem; padding: 0;',
    '}',
    '.census-poll--ready .census-poll__answers li::marker{ content: none; }',
    // A radio dot, so the row reads as a choice rather than a disabled input.
    // This is what makes it look like a poll at a glance.
    '.census-poll--ready .census-poll__answer{',
    '  display: flex; align-items: center; gap: .55rem;',
    '  width: 100%; text-align: left; cursor: pointer;',
    '  font: inherit; line-height: 1.3; color: inherit; background: transparent;',
    '  border: 1px solid var(--census-line); border-radius: 999px;',
    '  padding: .5rem .85rem .5rem .6rem;',
    '  transition: border-color .12s, background-color .12s, color .12s;',
    '}',
    '.census-poll--ready .census-poll__answer::before{',
    '  content: ""; flex: 0 0 auto; width: 14px; height: 14px; border-radius: 50%;',
    '  border: 1.5px solid var(--census-line); transition: border-color .12s, box-shadow .12s;',
    '}',
    '.census-poll--ready .census-poll__answer:hover{',
    '  border-color: var(--census-accent);',
    '  background: color-mix(in srgb, var(--census-accent) 8%, transparent);',
    '}',
    '.census-poll--ready .census-poll__answer:hover::before{',
    '  border-color: var(--census-accent);',
    '  box-shadow: inset 0 0 0 3px var(--census-accent);',
    '}',
    '.census-poll--ready .census-poll__answer:focus-visible{',
    '  outline: 2px solid var(--census-accent); outline-offset: 2px;',
    '}',
    '.census-poll--voting .census-poll__answer{ opacity: .5; cursor: default; }',
    // A disabled answer must not still look pressable — that is what makes a
    // reader click and get nothing back.
    '.census-poll--ready .census-poll__answer:disabled{',
    '  opacity: .45; cursor: default;',
    '}',
    '.census-poll--ready .census-poll__answer:disabled:hover{',
    '  border-color: var(--census-line); background: transparent;',
    '}',
    '.census-poll--ready .census-poll__answer:disabled:hover::before{',
    '  border-color: var(--census-line); box-shadow: none;',
    '}',
    // The bar is a background layer, not a sibling that reflows the text.
    // Rounded on both ends: a square-edged fill inside a pill row was the
    // cheapest-looking part of the first pass.
    '.census-poll--ready .census-poll__result{',
    '  position: relative; overflow: hidden; margin: 0 0 .3rem; list-style: none;',
    '  border-radius: 999px; background: color-mix(in srgb, var(--census-fg) 5%, transparent);',
    '  padding: .42rem .8rem; display: flex; align-items: center; gap: .6rem;',
    '  line-height: 1.35; font-size: .95rem;',
    '}',
    '.census-poll--ready .census-poll__bar{',
    '  position: absolute; inset: 0 auto 0 0; border-radius: 999px;',
    '  background: color-mix(in srgb, var(--census-accent) 26%, transparent);',
    '  transition: width .45s cubic-bezier(.2,.7,.3,1);',
    '}',
    '.census-poll--ready .census-poll__label{ position: relative; flex: 1; min-width: 0; }',
    '.census-poll--ready .census-poll__pct{',
    '  position: relative; font-variant-numeric: tabular-nums; font-weight: 600;',
    '  font-size: .9rem; color: var(--census-muted);',
    '}',
    // The reader's own answer is marked with a tick and a solid accent bar
    // rather than an outline ring around the whole row — the ring competed with
    // the bar it was drawn over.
    '.census-poll--ready .census-poll__result--chosen{ font-weight: 650; }',
    '.census-poll--ready .census-poll__result--chosen .census-poll__bar{',
    '  background: color-mix(in srgb, var(--census-accent) 42%, transparent);',
    '}',
    '.census-poll--ready .census-poll__result--chosen .census-poll__pct{ color: var(--census-fg); }',
    '.census-poll--ready .census-poll__result--chosen .census-poll__label::before{',
    '  content: "✓ "; color: var(--census-accent); font-weight: 800;',
    '}',
    '.census-poll--ready .census-poll__foot{',
    '  display: flex; align-items: center; justify-content: space-between; gap: .5rem;',
    '  margin: .75rem 0 0; padding: .6rem 0 0;',
    '  border-top: 1px solid var(--census-line);',
    '  font-size: .74rem; color: var(--census-muted);',
    '}',
    // Quiet attribution: readers do not know what Census is, so it stays a
    // small mark rather than a badge competing with the question.
    '.census-poll--ready .census-poll__mark{',
    '  font-size: .66rem; letter-spacing: .08em; text-transform: uppercase;',
    '  opacity: .6; white-space: nowrap;',
    '}',
    '.census-poll--ready .census-poll__error{',
    '  margin: .6rem 0 0; font-size: .85rem; color: #d23b3b;',
    '}',
    '@media (prefers-reduced-motion: reduce){',
    '  .census-poll--ready .census-poll__bar,',
    '  .census-poll--ready .census-poll__answer{ transition: none; }',
    '}'
  ].join("");

  /**
   * Is the surface behind this slot dark?
   *
   * Walks up for the first ancestor with an opaque background and compares its
   * luminance. Sites exposing the GAMURS tokens never need this — their own
   * light.css/dark.css already answers the question — but a site without them
   * would otherwise be guessed at from the reader's OS preference, which says
   * nothing about the page they are actually looking at.
   */
  function darkSurface(el) {
    var node = el;
    while (node && node !== document.documentElement) {
      var bg = getComputedStyle(node).backgroundColor;
      var m = bg && bg.match(/rgba?\(([^)]+)\)/);
      if (m) {
        var parts = m[1].split(",").map(parseFloat);
        var alpha = parts.length > 3 ? parts[3] : 1;
        if (alpha > 0.5) {
          // Rec. 709 luma is close enough for a light/dark decision.
          var luma = (0.2126 * parts[0] + 0.7152 * parts[1] + 0.0722 * parts[2]) / 255;
          return luma < 0.45;
        }
      }
      node = node.parentElement;
    }
    return false;
  }

  function injectStyles() {
    if (document.getElementById("census-poll-css")) return;
    var style = document.createElement("style");
    style.id = "census-poll-css";
    style.textContent = CSS;
    document.head.appendChild(style);
  }

  // Census's own ids, not Snowplow's. A property may have no page tracker at
  // all, and these have to exist for a vote to join to its serve either way.
  // The page-view id deliberately does not persist: a reload is a new view.
  function uid() {
    try {
      var v = localStorage.getItem("census_uid");
      if (!v) {
        v = crypto.randomUUID();
        localStorage.setItem("census_uid", v);
      }
      return v;
    } catch (e) {
      return ""; // private mode, or storage disabled
    }
  }
  var UID = uid();
  var PVID = crypto.randomUUID();

  // The article a slot belongs to, read when that slot is filled and kept for
  // its vote.
  //
  // NOT read at load, and NOT read again when the vote fires. Infinite scroll
  // pushes a new path into the address bar as the reader passes each article,
  // so location at load names the first article for every slot on the page,
  // and location at vote time names whichever article the reader has since
  // scrolled to. Either one silently misattributes every poll below the first.
  //
  // Origin and path only: the query string is the reader's own session, not the
  // article, and the Worker drops it anyway.
  function pageUrl() {
    return location.origin + location.pathname;
  }

  // Returns the answer id this reader picked, or "" if they have not voted.
  // Storing the id rather than a flag is what lets a return visit tick their
  // own answer in the results.
  function voted(campaignId) {
    try {
      return localStorage.getItem("census_voted_" + campaignId) || "";
    } catch (e) {
      return "";
    }
  }
  function remember(campaignId, answerId) {
    try {
      localStorage.setItem("census_voted_" + campaignId, String(answerId));
    } catch (e) {}
  }

  // Straight to the collector rather than through a page tracker, which may not
  // exist. Only viewability is sent from here; served and vote are server-side.
  //
  // The page is the url captured when the slot was FILLED, the same value served
  // and vote carry. Not location.href read here: viewability fires when the
  // reader scrolls to the slot, by which time infinite scroll has pushed a
  // later article into the address bar — and the query string would split one
  // article across rows, so a served -> viewable join on page_url would miss on
  // both counts. That join is the placement measurement.
  function trackViewable(poll, property, page) {
    var payload = {
      schema: "iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4",
      data: [
        {
          e: "ue",
          p: "web",
          tv: "census-embed-0.1",
          aid: poll.appId,
          eid: crypto.randomUUID(),
          dtm: String(Date.now()),
          url: page,
          ue_pr: JSON.stringify({
            schema: "iglu:com.snowplowanalytics.snowplow/unstruct_event/jsonschema/1-0-0",
            data: {
              schema: "iglu:group.gamurs/census_poll_viewable/jsonschema/1-0-0",
              data: {
                propertySlug: property,
                pollId: poll.pollId,
                campaignId: poll.campaignId,
                slot: poll.slot
              }
            }
          })
        }
      ]
    };
    // Absent rather than empty, matching what the Worker sends on served. An
    // empty duid is not "unknown" to the warehouse — it is one shared id, and
    // every private-mode reader would collapse into it, poisoning the
    // served → viewable join on the side this event owns.
    if (UID) payload.data[0].duid = UID;
    try {
      navigator.sendBeacon(
        poll.collector + "/com.snowplowanalytics.snowplow/tp2",
        new Blob([JSON.stringify(payload)], { type: "application/json" })
      );
    } catch (e) {}
  }

  // MRC-style: at least half the pixels for at least one continuous second.
  function onceViewable(el, fn) {
    if (!window.IntersectionObserver) return;
    var timer = null;
    var seen = false;
    var io = new IntersectionObserver(
      function (entries) {
        var visible = entries[0].intersectionRatio >= 0.5;
        if (visible && !seen && timer === null) {
          timer = setTimeout(function () {
            seen = true;
            io.disconnect();
            fn();
          }, 1000);
        } else if (!visible && timer !== null) {
          clearTimeout(timer);
          timer = null;
        }
      },
      { threshold: [0, 0.5, 1] }
    );
    io.observe(el);
  }

  // Attribution mark. Text rather than an image: a remote logo is a second
  // request, a layout shift and a broken-image risk on every poll, and the
  // parent-company brand is not something readers of a property recognise.
  function mark() {
    var m = document.createElement("span");
    m.className = "census-poll__mark";
    m.textContent = "GAMURS Census";
    return m;
  }

  function results(el, answers, chosenId) {
    var total = answers.reduce(function (sum, a) {
      return sum + a.total;
    }, 0);
    var list = el.querySelector(".census-poll__answers");
    list.innerHTML = "";

    // Highest first: a results list in submission order makes the reader do
    // the ranking themselves.
    answers
      .slice()
      .sort(function (a, b) {
        return b.total - a.total;
      })
      .forEach(function (a) {
        var pct = total ? Math.round((a.total / total) * 100) : 0;
        var row = document.createElement("li");
        row.className =
          "census-poll__result" +
          (String(a.id) === String(chosenId) ? " census-poll__result--chosen" : "");
        row.innerHTML =
          '<span class="census-poll__bar"></span>' +
          '<span class="census-poll__label"></span>' +
          '<span class="census-poll__pct"></span>';
        // textContent, not innerHTML — answer text is authored copy, but it
        // reaches here through two systems and is not worth trusting as markup.
        row.querySelector(".census-poll__label").textContent = a.text;
        row.querySelector(".census-poll__pct").textContent = pct + "%";
        row.querySelector(".census-poll__bar").style.width = pct + "%";
        list.appendChild(row);
      });

    var foot = el.querySelector(".census-poll__foot");
    if (!foot) {
      foot = document.createElement("p");
      foot.className = "census-poll__foot";
      el.appendChild(foot);
    }
    foot.textContent = "";
    var count = document.createElement("span");
    count.textContent =
      total === 1 ? "1 vote so far" : total.toLocaleString() + " votes so far";
    foot.appendChild(count);
    foot.appendChild(mark());

    el.classList.remove("census-poll--voting");
    el.classList.add("census-poll--voted");
  }

  function render(el, poll, property, page) {
    injectStyles();
    el.classList.add("census-poll--ready");
    if (darkSurface(el)) el.classList.add("census-poll--dark");
    // A poll is a form-like region that appears mid-article; without a role and
    // a label a screen reader announces four unexplained buttons.
    el.setAttribute("role", "group");

    // Overridable per slot with data-label, so a property or a one-off campaign
    // can say something else without a deploy.
    var eyebrow = document.createElement("p");
    eyebrow.className = "census-poll__eyebrow";
    eyebrow.innerHTML = '<span class="census-poll__glyph"><i></i><i></i><i></i></span>';
    var label = document.createElement("span");
    label.textContent = el.getAttribute("data-label") || "Opinion Polls";
    eyebrow.appendChild(label);

    var q = document.createElement("p");
    q.className = "census-poll__question";
    q.textContent = poll.question;
    q.id = "census-q-" + poll.campaignId;
    el.setAttribute("aria-labelledby", q.id);

    var list = document.createElement("ul");
    list.className = "census-poll__answers";
    // Results replace the buttons in place, so the swap has to be announced.
    list.setAttribute("aria-live", "polite");

    poll.answers.forEach(function (a) {
      var li = document.createElement("li");
      var btn = document.createElement("button");
      btn.type = "button";
      btn.className = "census-poll__answer";
      btn.textContent = a.text;
      btn.addEventListener("click", function () {
        if (el.classList.contains("census-poll--voting")) return;
        el.classList.add("census-poll--voting");
        fetch(ORIGIN + "/vote", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            campaignId: poll.campaignId,
            property: property,
            answerIds: [String(a.id)],
            spUid: UID,
            spPvid: PVID,
            pageUrl: page
          })
        })
          .then(function (r) {
            return r.ok ? r.json() : Promise.reject(r.status);
          })
          .then(function (data) {
            remember(poll.campaignId, a.id);
            results(el, data.results, a.id);
          })
          .catch(function () {
            el.classList.remove("census-poll--voting");
            el.classList.add("census-poll--error");
            // Never claim a vote landed. A failure here means Crowdsignal did
            // not record it, and saying otherwise is the one lie this system
            // must not tell.
            var msg = el.querySelector(".census-poll__error");
            if (!msg) {
              msg = document.createElement("p");
              msg.className = "census-poll__error";
              el.appendChild(msg);
            }
            msg.textContent = "Sorry — your vote could not be recorded.";
          });
      });
      li.appendChild(btn);
      list.appendChild(li);
    });

    el.appendChild(eyebrow);
    el.appendChild(q);
    el.appendChild(list);

    var foot = document.createElement("p");
    foot.className = "census-poll__foot";
    var hint = document.createElement("span");
    hint.textContent = "Pick one";
    foot.appendChild(hint);
    foot.appendChild(mark());
    el.appendChild(foot);

    var alreadyVoted = voted(poll.campaignId);
    if (alreadyVoted) {
      // Show live results, not dead buttons. Disabled buttons that still look
      // like buttons read as "you can vote" and then ignore the click, and a
      // reader returning to a poll wants the numbers anyway.
      //
      // localStorage stops an accidental second vote, not a determined one:
      // clearing it defeats this, which is understood and accepted.
      el.classList.add("census-poll--voted");
      var buttons = list.querySelectorAll("button");
      for (var i = 0; i < buttons.length; i++) buttons[i].disabled = true;
      hint.textContent = "Thanks — you have already voted";

      fetch(ORIGIN + "/results?campaignId=" + encodeURIComponent(poll.campaignId))
        .then(function (r) {
          return r.ok ? r.json() : Promise.reject(r.status);
        })
        // results() rebuilds the footer with the vote count, so the thanks
        // line is replaced rather than updated here.
        .then(function (data) {
          results(el, data.results, alreadyVoted);
        })
        // Totals unavailable: leave the disabled buttons and the thanks line
        // rather than inventing numbers.
        .catch(function () {});
    }

    onceViewable(el, function () {
      trackViewable(poll, property, page);
    });
  }

  function fill(el) {
    var property = el.getAttribute("data-property");
    if (!property) return;
    var slot = el.getAttribute("data-slot") || "global";
    // Captured here rather than at vote time, and handed to render() so the
    // serve and the vote name the same article. See pageUrl below.
    var page = pageUrl();
    var url =
      ORIGIN +
      "/poll?property=" + encodeURIComponent(property) +
      "&slot=" + encodeURIComponent(slot) +
      "&url=" + encodeURIComponent(page);
    var tags = el.getAttribute("data-tags");
    if (tags) url += "&tags=" + encodeURIComponent(tags);
    var cats = el.getAttribute("data-categories");
    if (cats) url += "&categories=" + encodeURIComponent(cats);
    // The same id the vote sends as spUid and the viewable event sends as duid.
    // It is what lets served be counted per reader rather than per request.
    // Empty in private mode, where the served event simply has no duid.
    if (UID) url += "&uid=" + encodeURIComponent(UID);
    // Whether a human could have seen this page at all. A prerendered document
    // runs scripts and fetches this poll, and a hidden one is a background tab;
    // neither can ever produce a viewable event, so both depress the
    // served → viewable rate without any reader behaving differently. The
    // Worker logs only the not-visible cases, as a standing alarm for a
    // property turning on prerendering. Reported rather than acted on:
    // suppressing the fetch here would change what serving means, and would
    // collapse served into viewable — the gap is the placement measurement.
    url += "&vis=" + (document.prerendering ? "prerender" : document.visibilityState);

    fetch(url)
      .then(function (r) {
        // 404 is the ordinary answer for an unfilled slot, not an error. The
        // container stays empty and collapses.
        return r.ok ? r.json() : null;
      })
      .then(function (poll) {
        if (poll) render(el, poll, property, page);
      })
      .catch(function () {});
  }

  function init() {
    var nodes = document.querySelectorAll(".census-poll:not([data-census-init])");
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].setAttribute("data-census-init", "1");
      fill(nodes[i]);
    }
  }

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", init);
  else init();

  /**
   * Infinite scroll appends whole articles after load, so a single pass fills
   * only the first one. Watching the DOM rather than requiring each property to
   * call census.scan() is deliberate: the network's infinite scroll dispatches
   * no event to hook, and every site would otherwise need its own wiring to
   * find and maintain. The init attribute makes rescanning idempotent.
   */
  if (window.MutationObserver) {
    var pending = false;
    new MutationObserver(function () {
      if (pending) return;
      pending = true;
      // Coalesced: appending an article fires many mutations, and each would
      // otherwise walk the whole document.
      setTimeout(function () {
        pending = false;
        init();
      }, 200);
    }).observe(document.body, { childList: true, subtree: true });
  }

  // Still exposed for anything that would rather call it directly.
  window.census = { scan: init };
})();
