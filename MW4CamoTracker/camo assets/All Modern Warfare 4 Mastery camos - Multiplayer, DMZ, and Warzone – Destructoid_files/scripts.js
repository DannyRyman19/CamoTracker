(function ($) {

	// Top Bar Nav
	if (!$('body').hasClass('home') || ($('body').hasClass('home') && $(window).width() <= 991)) {
		$('#top-bar-nav').addClass('active');
		// Mobile scroll direction detection for top bar nav
		// let lastScrollTop = 0;
		// $(window).on('scroll', function () {
		// 	if ($(window).width() <= 991) {
		// 		const scrollTop = $(window).scrollTop();
		// 		if (scrollTop > lastScrollTop && scrollTop > 60) {
		// 			$('#top-bar-nav').removeClass('active');
		// 		} else if (scrollTop < lastScrollTop) {
		// 			$('#top-bar-nav').addClass('active');
		// 		}
		// 		lastScrollTop = scrollTop;
		// 	}
		// });
	} else {
		$(window).on('scroll', function () {
			// Top Bar Nav + Homepage Nav + Big logo + Desktop
			const featuredPosts = $('#home-featured-posts');
			if (featuredPosts.length) {
				const featuredPostsTop = featuredPosts.offset().top;
				const scrollTop = $(window).scrollTop();
				if (scrollTop >= featuredPostsTop - 60) {
					$('#top-bar-nav').addClass('active');
				} else {
					$('#top-bar-nav').removeClass('active');
				}
			}
		});
	}

	// Off Canvas Nav
	function closeOffCanvasNav() {
		const offCanvasNav = $('#off-canvas-nav');
		const offCanvasNavContainer = $('.off-canvas-nav-container');
		const allButtons = $('#off-canvas-nav-button, #off-canvas-nav-button-homepage');

		offCanvasNav.removeClass('active');
		$('body').removeClass('overflow-hidden');
		offCanvasNavContainer.css('pointer-events', 'none');
		allButtons.html(`
			<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
				<rect x="2" y="7" width="20" height="1.83673" />
				<rect x="2" y="15.1632" width="20" height="1.83673" />
			</svg>
        `);
	}

	$('#off-canvas-nav-button, #off-canvas-nav-button-homepage').on('click', function (e) {
		e.preventDefault();
		e.stopPropagation(); // Prevent event bubbling

		const offCanvasNav = $('#off-canvas-nav');
		const offCanvasNavContainer = $('.off-canvas-nav-container');
		const allButtons = $('#off-canvas-nav-button, #off-canvas-nav-button-homepage');

		offCanvasNav.toggleClass('active');

		if (offCanvasNav.hasClass('active')) {
			$('body').addClass('overflow-hidden');
			offCanvasNavContainer.css('pointer-events', 'all');
			allButtons.html(`
                <svg width="24" height="18" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M18.36 19.78L12 13.42L5.64 19.78L4.22 18.36L10.58 12L4.22 5.64L5.64 4.22L12 10.58L18.36 4.22L19.78 5.64L13.42 12L19.78 18.36L18.36 19.78Z" />
                </svg>
                `);
		} else {
			closeOffCanvasNav();
		}
	});

	// Close off-canvas nav when clicking outside
	$(document).on('click', function (e) {
		const offCanvasNav = $('#off-canvas-nav');

		// Only proceed if off-canvas nav is active
		if (!offCanvasNav.hasClass('active')) {
			return;
		}

		const target = $(e.target);

		// Check if click is inside elements that should NOT close the nav
		const isInsideOffCanvasNav = target.closest('#off-canvas-nav').length > 0;
		const isInsideTopBarNav = target.closest('#top-bar-nav').length > 0;
		const isInsideHomepageNav = target.closest('#homepage-nav').length > 0;
		const isOffCanvasButton = target.closest('#off-canvas-nav-button, #off-canvas-nav-button-homepage').length > 0;

		// If click is outside all protected areas, close the nav
		if (!isInsideOffCanvasNav && !isInsideTopBarNav && !isInsideHomepageNav && !isOffCanvasButton) {
			closeOffCanvasNav();
		}
	});

	// Main Search
	$('#main-search-button, #main-search-button-homepage').on('click', function () {
		$('#main-search-container').addClass('active');
		closeOffCanvasNav();
	});
	$('#main-search-button-close').on('click', function () {
		$('#main-search-container').removeClass('active');
	});
	function preventShortSearch() {
		const searchForm = document.querySelector('form[method="get"]');
		const searchInput = document.querySelector('input[name="s"]');

		if (searchForm && searchInput) {
			searchForm.addEventListener('submit', function (e) {
				const searchValue = searchInput.value.trim();

				if (searchValue.length < 3) {
					e.preventDefault();
					alert('Please enter at least 3 characters to search.');
					searchInput.focus();
					return false;
				}
			});
		}
	}
	document.addEventListener('DOMContentLoaded', preventShortSearch);

	// Scroll adjustments on mobile if top ad is present
	function scrollOnSingleWithAds() {
		const adInHeader = document.querySelector('body > header .gamurs-ad-container');
		if (!adInHeader) {
			return;
		}
		const topBarNav = document.getElementById('top-bar-nav');
		if (!topBarNav) {
			return;
		}
		const offCanvasNavContainer = document.getElementsByClassName('off-canvas-nav-container')[0];
		function updateNavPosition() {
			if (window.innerWidth <= 991) {
				const scrollY = window.scrollY || window.pageYOffset;
				if (scrollY > 50) {
					topBarNav.style.top = '0px';
					offCanvasNavContainer.style.top = '50px';
					offCanvasNavContainer.style.height = 'calc(100vh - 50px)';
				} else {
					topBarNav.style.top = '50px';
					offCanvasNavContainer.style.top = '100px';
					offCanvasNavContainer.style.height = 'calc(100vh - 100px)';
				}
			} else {
				topBarNav.style.top = '';
			}
		}
		updateNavPosition();
		window.addEventListener('scroll', updateNavPosition);
		window.addEventListener('resize', updateNavPosition);
	}
	document.addEventListener('DOMContentLoaded', scrollOnSingleWithAds);

})(jQuery);