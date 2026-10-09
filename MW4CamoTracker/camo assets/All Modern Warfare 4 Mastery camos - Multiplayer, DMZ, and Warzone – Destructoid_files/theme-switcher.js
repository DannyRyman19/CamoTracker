class ThemeSwitcher {
	constructor() {
		this.init();
	}

	init() {
		this.loadTheme();
		this.bindEvents();
	}

	loadTheme() {
		const savedTheme = this.getThemeFromStorage();
		const theme = savedTheme || this.getSystemTheme();
		this.setTheme(theme);
	}

	getThemeFromStorage() {
		return localStorage.getItem('theme-preference');
	}

	getSystemTheme() {
		return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
	}

	setTheme(theme) {
		document.documentElement.setAttribute('data-theme', theme);
		document.body.classList.remove('theme-light', 'theme-dark');
		document.body.classList.add(`theme-${theme}`);
		localStorage.setItem('theme-preference', theme);

		// Set cookie for PHP to read
		document.cookie = `theme-preference=${theme}; path=/; max-age=${86400 * 30}; SameSite=Lax`;

		// Control CSS file loading
		this.toggleCSSFiles(theme);

		// Update toggle buttons
		this.updateToggleButtons(theme);

		// Update all icons for theme
		this.updateAllIcons();
	}

	updateToggleButtons(theme) {
		const toggles = [
			document.getElementById('theme-toggle'),
			document.getElementById('theme-toggle-homepage')
		];

		toggles.forEach(toggle => {
			if (toggle) {
				toggle.setAttribute('aria-label', `Switch to ${theme === 'light' ? 'dark' : 'light'} theme`);
			}
		});
	}

	toggleCSSFiles(theme) {
		const lightCSS = document.querySelector('link[href*="light.css"]');
		const darkCSS = document.querySelector('link[href*="dark.css"]');

		if (theme === 'dark') {
			if (lightCSS) lightCSS.disabled = true;
			if (darkCSS) darkCSS.disabled = false;
		} else {
			if (lightCSS) lightCSS.disabled = false;
			if (darkCSS) darkCSS.disabled = true;
		}
	}

	toggleTheme() {
		const currentTheme = document.documentElement.getAttribute('data-theme') || 'light';
		const newTheme = currentTheme === 'light' ? 'dark' : 'light';
		this.setTheme(newTheme);
	}

	bindEvents() {
		const toggles = [
			document.getElementById('theme-toggle'),
			document.getElementById('theme-toggle-homepage')
		];

		toggles.forEach(toggle => {
			if (toggle) {
				toggle.addEventListener('click', () => this.toggleTheme());
			}
		});

		// Listen for system theme changes
		window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
			if (!this.getThemeFromStorage()) {
				this.setTheme(e.matches ? 'dark' : 'light');
			}
		});

		// Initialize single post interactions
		this.initSinglePostInteractions();

		// Initialize Disqus observer
		this.initDisqusObserver();
	}

	getThemedIconPath(iconName, state) {
		const isLightTheme = document.body.classList.contains('theme-light');
		const themeSuffix = (state === 'off' && isLightTheme) ? '-light' : '';
		const templateUri = '/wp-content/themes/destructoid2025';
		return `${templateUri}/assets/img/icons/${iconName}-${state}${themeSuffix}.png`;
	}

	updateAllIcons() {
		// Update all icon elements at once
		const iconElements = document.querySelectorAll('img[src*="/icons/"]');
		
		iconElements.forEach(img => {
			const src = img.src;
			
			// Extract icon name and state from current src
			const match = src.match(/\/icons\/([a-z]+)-(on|off)(-light)?\.png/);
			if (match) {
				const iconName = match[1];
				let state = match[2];
				
				// Special handling for likes icon - preserve favorited state per post
				if (iconName === 'likes' && img.dataset.postId) {
					const postId = img.dataset.postId;
					// Find the favorites button for this specific post
					const favButton = document.querySelector(`.simplefavorite-button[data-postid="${postId}"]`);
					if (favButton) {
						state = favButton.classList.contains('active') ? 'on' : 'off';
					}
				}
				
				img.src = this.getThemedIconPath(iconName, state);
			}
		});
	}

	initSinglePostInteractions() {
		if (!document.body.classList.contains('single-post') && !document.body.classList.contains('single-eg_reviews')) {
			return;
		}
	}

	initDisqusObserver() {
		// Function to update comment and like icons
		const updateInteractionIcons = () => {
			// Update comment icons when count changes
			const commentElements = document.querySelectorAll('.disqus-comment-count');
			
			commentElements.forEach(element => {
				const count = parseInt(element.textContent) || 0;
				const commentCounter = element.closest('#comments-counter');
				
				if (commentCounter) {
					const icon = commentCounter.querySelector('img');
					if (icon) {
						const state = count > 0 ? 'on' : 'off';
						icon.src = this.getThemedIconPath('comments', state);
					}
				}
			});

			// Update sidebar comment icon
			const sidebarIcon = document.querySelector('.comments-icon-sidebar img');
			const commentElement = document.querySelector('#social-interactions .disqus-comment-count');
			if (sidebarIcon && commentElement) {
				const totalComments = parseInt(commentElement.textContent) || 0;
				const state = totalComments > 0 ? 'on' : 'off';
				sidebarIcon.src = this.getThemedIconPath('comments', state);
			}

			// Update all likes icons based on each post's total like count
			const likesIcons = document.querySelectorAll('img.likes-icon[data-post-id]');
			likesIcons.forEach(icon => {
				const countElement = icon.parentElement.querySelector('.number');
				const likeCount = countElement ? parseInt(countElement.textContent) || 0 : 0;
				const state = likeCount > 0 ? 'on' : 'off';
				icon.src = this.getThemedIconPath('likes', state);
			});
		};

		// Observer to watch for changes in comment and like count elements
		const observer = new MutationObserver(updateInteractionIcons);

		// Start observing after a short delay
		setTimeout(() => {
			// Observe comment count changes
			const commentElements = document.querySelectorAll('.disqus-comment-count');
			commentElements.forEach(element => {
				observer.observe(element, {
					childList: true,
					subtree: true,
					characterData: true
				});
			});

			// Observe likes count changes
			const likeElements = document.querySelectorAll('.simplefavorite-button-count, #likes-counter .number');
			likeElements.forEach(element => {
				observer.observe(element, {
					childList: true,
					subtree: true,
					characterData: true
				});
			});

			// Initial update
			updateInteractionIcons();
		}, 1000);
	}
}

new ThemeSwitcher();
