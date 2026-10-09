/**
 * Data-driven dynamic rail — desktop single articles, Destructoid.
 *
 * Port of the Pro Game Guides capped dynamic rail, adapted to destructoid2025's markup.
 * Destructoid's rail column (.col-4) is flex-stretched to article height and currently
 * holds ONE BC unit (#rail-scroll-parent -> destructoid_dt_rail-0). This adds up to 2 more
 * stacked .dto-rail-slot boxes so a tall article fills 2-3 rail units instead of 1.
 *
 * Count is calibrated to US-desktop scroll behaviour (mart_pageviews, 90d). Two populations:
 *   NON-CODES = 76% of pageviews. Deep readers: p90 reached 10,600px, 27% reach screen 3 ->
 *     a 3rd unit on long guides is justified. Tier by article body height:
 *       short (<3000px) -> 1   median (3000-5499px) -> 2   long (>=5500px) -> 3
 *   CODES = 24% (slug ends -codes). Shallow: p90 3500px, only 14.5% reach screen 3 -> CAP 2.
 * Cap is 3.
 *
 * #rail-scroll-parent keeps its id (BC fills -0); added boxes get class .dto-rail-slot for BC
 * to fill (-1, -2). CSS flex-distributes filled boxes and collapses any unfilled box to 0px.
 *
 * Requires BC ad-ops: add ".dto-rail-slot" to the destructoid_dt_rail selector so the added
 * boxes fill — without it only the seed fills and added boxes collapse (harmless). Vanilla, no deps.
 */
(function () {
	// One-shot guard. This file is printed multiple times per page (infinite scroll preloads
	// sibling articles, each re-enqueuing the footer script). First copy wins.
	if (window.__dtoRailFill) return;
	window.__dtoRailFill = true;

	function unitsForHeight(px) {
		if (px < 3000) return 1;
		if (px < 5500) return 2;
		return 3; // hard cap
	}

	function fill() {
		if (!window.matchMedia('(min-width:992px)').matches) return; // desktop only (Bootstrap lg)
		if (!document.body.classList.contains('single')) return;      // article pages only

		var col = document.querySelector('.dto-rail-column');
		// .post-content = the article body (scroll-depth proxy), like PGG's .entry-content.
		var article = document.querySelector('.post-content') || col;
		if (!col || !article) return;

		// Tag the seed (#rail-scroll-parent) with the shared .dto-rail-slot class so a SINGLE BC
		// class selector (css_selector_type: class) fills the seed AND the added boxes. BC's
		// config takes one selector + a type (no comma/multi-selector), so all rail boxes must
		// share one class.
		var seed = document.getElementById('rail-scroll-parent');
		if (seed) seed.classList.add('dto-rail-slot');

		var target = unitsForHeight(article.getBoundingClientRect().height);
		// Codes pages (slug ends -codes) scroll shallow (p90 3500px, 14.5% reach screen 3) -> cap 2.
		if (/codes/i.test(location.pathname)) target = Math.min(2, target);

		// Authoritative + idempotent: re-query each iteration so we can never exceed target.
		// All rail boxes (seed + added) carry .dto-rail-slot, so the count includes the seed as unit 1.
		while (col.querySelectorAll('.dto-rail-slot').length < target) {
			var slot = document.createElement('div');
			slot.className = 'gamurs-ad-container dto-rail-slot'; // BC ".dto-rail-slot" fills it; CSS collapses if unfilled
			col.appendChild(slot);
		}
	}

	// Measure at window.load: at DOMContentLoaded images/embeds haven't laid out, so article
	// height is undercounted and short pages pick too few units.
	if (document.readyState === 'complete') fill();
	else window.addEventListener('load', fill);
})();
