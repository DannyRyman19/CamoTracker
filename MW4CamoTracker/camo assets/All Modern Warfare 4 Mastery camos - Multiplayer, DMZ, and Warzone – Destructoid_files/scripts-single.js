(function ($) {

	// Once Disqus has fully loaded into #disqus_thread, rename the ID so that any
	// subsequent embed.js injection (e.g. from a Cloudflare-cached sponsored article)
	// cannot find the element and re-initialize, overwriting the first article's thread.
	(function () {
		var el = document.getElementById('disqus_thread');
		if (!el) return;
		var observer = new MutationObserver(function () {
			if (el.children.length > 0) {
				el.removeAttribute('id');
				observer.disconnect();
			}
		});
		observer.observe(el, { childList: true });
	})();

	// Single posts, reviews and game hubs
	if (document.body.classList.contains('single-post') || document.body.classList.contains('single-eg_reviews') || document.body.classList.contains('single-game_hub')) {

		// Desktop only
		if (window.innerWidth >= 992) {
			let isScrollingFromClick = false;

			// Table of Contents - Highlight current title based on scroll position.
			function updateCurrentTitle() {
				// Don't update if we're scrolling from a click
				if (isScrollingFromClick) {
					return;
				}

				const tocLinks = document.querySelectorAll('article.single-post .post-content .wp-block-yoast-seo-table-of-contents ul li a, .wp-block-yoast-seo-table-of-contents ul li a');
				if (tocLinks.length === 0) {
					return;
				}

				// Get all headings with IDs that match the TOC links
				const headings = [];
				tocLinks.forEach(link => {
					const href = link.getAttribute('href');
					const id = href.substring(1);
					const heading = document.getElementById(id);

					if (heading) {
						headings.push({
							element: heading,
							link: link,
							id: id,
							offsetTop: heading.getBoundingClientRect().top + window.scrollY
						});
					} else {
						console.log(`Heading not found for ID: ${id}`);
					}
				});
				if (headings.length === 0) {
					return;
				}

				// Sort headings by their position on page
				headings.sort((a, b) => a.offsetTop - b.offsetTop);

				// Offset = 60px header height + 20px buffer
				const scrollOffset = window.scrollY + 80;

				// Find the current heading
				let currentHeading = null;
				for (let i = headings.length - 1; i >= 0; i--) {
					if (headings[i].offsetTop <= scrollOffset) {
						currentHeading = headings[i];
						break;
					}
				}

				// If no heading is above scroll position, use the first one
				if (!currentHeading && headings.length > 0) {
					currentHeading = headings[0];
				}

				// Remove current-title class from all links
				tocLinks.forEach(link => link.classList.remove('current-title'));

				// Add current-title class to current link
				if (currentHeading) {
					currentHeading.link.classList.add('current-title');
				}
			}

			// Throttle function to improve performance
			function throttle(func, limit) {
				let inThrottle;
				return function () {
					const args = arguments;
					const context = this;
					if (!inThrottle) {
						func.apply(context, args);
						inThrottle = true;
						setTimeout(() => inThrottle = false, limit);
					}
				}
			}

			// Initialize
			document.addEventListener('DOMContentLoaded', function () {
				// Initial call
				setTimeout(updateCurrentTitle, 100);

				// Add throttled scroll listener
				window.addEventListener('scroll', throttle(updateCurrentTitle, 100));

				// Also update on resize
				window.addEventListener('resize', throttle(updateCurrentTitle, 250));
			});

			// Smooth scroll with 80px offset for TOC links
			const tocLinks = document.querySelectorAll('article.single-post .post-content .wp-block-yoast-seo-table-of-contents ul li a, .wp-block-yoast-seo-table-of-contents ul li a');
			tocLinks.forEach(link => {
				link.addEventListener('click', function (e) {
					const href = link.getAttribute('href');
					if (href && href.startsWith('#')) {
						const target = document.getElementById(href.substring(1));
						if (target) {
							e.preventDefault();

							// Set flag to prevent updateCurrentTitle from running
							isScrollingFromClick = true;

							// Manually set the active class
							document.querySelectorAll('article.single-post .post-content .wp-block-yoast-seo-table-of-contents ul li a, .wp-block-yoast-seo-table-of-contents ul li a').forEach(
								l => l.classList.remove('current-title')
							);
							link.classList.add('current-title');

							const y = target.getBoundingClientRect().top + window.scrollY - 80;
							window.scrollTo({ top: y, behavior: 'smooth' });
							history.pushState(null, '', href);

							// Re-enable updateCurrentTitle after scroll completes (estimate 1 second for smooth scroll)
							setTimeout(() => {
								isScrollingFromClick = false;
							}, 1000);
						}
					}
				});
			});
		}
	}
	
})(jQuery);