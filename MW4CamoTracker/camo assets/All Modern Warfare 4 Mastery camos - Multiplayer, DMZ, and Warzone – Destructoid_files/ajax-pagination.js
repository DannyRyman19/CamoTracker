document.addEventListener('DOMContentLoaded', function() {
    // Handle pagination clicks
    document.addEventListener('click', function(e) {
        // Check if clicked element is inside an AJAX pagination container
        const paginationContainer = e.target.closest('[data-ajax-pagination="true"] .pagination-wrapper');
        
        if (!paginationContainer) return;

        const link = e.target.closest('a');
        if (!link || link.classList.contains('current')) {
            return;
        }

        e.preventDefault();

        const postsContainer = e.target.closest('[data-ajax-pagination="true"]');
        const ajaxId = postsContainer.id;
        
        // Extract page number from URL
        const url = new URL(link.href);
        const pathParts = url.pathname.split('/').filter(part => part !== '');
        let paged = 1;
        
        // Look for page number in path - handles both /page/2/ and /post-slug/page/2/
        const pageIndex = pathParts.indexOf('page');
        if (pageIndex !== -1 && pathParts[pageIndex + 1]) {
            paged = parseInt(pathParts[pageIndex + 1]);
        } else if (url.searchParams.has('paged')) {
            paged = parseInt(url.searchParams.get('paged'));
        }
        


        // Get template args from link data attributes or URL params
        let templateArgs = {};
        if (url.searchParams.has('template_args')) {
            try {
                let encodedArgs = url.searchParams.get('template_args');
                
                // Decode URL encoding first if needed
                try {
                    encodedArgs = decodeURIComponent(encodedArgs);
                } catch (urlError) {
                    // No URL decoding needed
                }
                
                // Validate that the string is properly base64 encoded before attempting to decode
                if (encodedArgs && typeof encodedArgs === 'string') {
                    // Check if string contains only valid base64 characters
                    const base64Regex = /^[A-Za-z0-9+/]*={0,2}$/;
                    if (base64Regex.test(encodedArgs)) {
                        templateArgs = JSON.parse(atob(encodedArgs));
                    } else {
                        console.warn('Template args string is not valid base64, using fallback');
                        templateArgs = { pagination: true, ajax_id: ajaxId };
                    }
                } else {
                    console.warn('Template args string is empty or invalid, using fallback');
                    templateArgs = { pagination: true, ajax_id: ajaxId };
                }
            } catch (error) {
                console.error('Error parsing template args:', error);
                templateArgs = { pagination: true, ajax_id: ajaxId };
            }
        }
        
        
        // If no template args in URL, use basic fallback
        if (Object.keys(templateArgs).length === 0) {
            templateArgs = { pagination: true, ajax_id: ajaxId };
        }

        // Add loading state
        postsContainer.style.opacity = '0.6';
        postsContainer.style.pointerEvents = 'none';

        // Perform AJAX request
        fetch(ajax_object.ajax_url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: new URLSearchParams({
                action: 'ajax_pagination',
                paged: paged,
                template_args: btoa(JSON.stringify(templateArgs)),
                nonce: ajax_object.nonce
            })
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                // Replace container content
                postsContainer.outerHTML = data.data.html;
                
                // Re-initialize dynamic elements after AJAX load with a small delay
                // to ensure DOM is fully updated
                setTimeout(function() {
                    initializeDynamicElements();
                }, 100);
                
                // Scroll to the top of the section with fixed topbar offset
                const newContainer = document.getElementById(ajaxId);
                if (newContainer) {
                    const rect = newContainer.getBoundingClientRect();
                    const currentScrollTop = window.pageYOffset || document.documentElement.scrollTop;
                    
                    // Calculate offset based on screen size (60px desktop, 50px mobile)
                    const isMobile = window.innerWidth < 992; // Bootstrap lg breakpoint
                    const offset = isMobile ? 50 : 60;
                    
                    const targetScrollTop = currentScrollTop + rect.top - offset;
                    
                    window.scrollTo({
                        top: targetScrollTop,
                        behavior: 'smooth'
                    });
                }
            }
        })
        .catch(error => {
            // Fallback to normal page load
            window.location.href = link.href;
        })
        .finally(() => {
            // Remove loading state
            const currentContainer = document.getElementById(ajaxId);
            if (currentContainer) {
                currentContainer.style.opacity = '1';
                currentContainer.style.pointerEvents = 'auto';
            }
        });
    });
    
    // Function to re-initialize dynamic elements after AJAX content load
    function initializeDynamicElements() {
        // Re-initialize Disqus comment counts
        if (typeof window.DISQUSWIDGETS !== 'undefined') {
            try {
                // Reset all comment counts to "0" first to ensure they show something
                document.querySelectorAll('.disqus-comment-count').forEach(function(element) {
                    if (!element.textContent.trim()) {
                        element.textContent = '0';
                    }
                });
                
                // Force reset and reload Disqus counts
                DISQUSWIDGETS.getCount({reset: true});
                
                // Additional fallback - manually trigger count update after a brief delay
                setTimeout(function() {
                    if (typeof DISQUSWIDGETS !== 'undefined') {
                        DISQUSWIDGETS.getCount({reset: true});
                        // Ensure any empty counts show "0" after Disqus has had time to update
                        setTimeout(function() {
                            document.querySelectorAll('.disqus-comment-count').forEach(function(element) {
                                if (!element.textContent.trim()) {
                                    element.textContent = '0';
                                }
                            });
                            // Update comments icon states after Disqus has updated
                            updateCommentsIconStates();
                        }, 1000);
                    }
                }, 500);
            } catch (e) {
                // Silently handle Disqus errors
            }
        }
        
        // Re-initialize Favorites plugin (likes) if available
        if (typeof window.jQuery !== 'undefined' && typeof window.Favorites !== 'undefined') {
            try {
                // Trigger the favorites update event to refresh all buttons
                jQuery(document).trigger('favorites-update-all-buttons');
            } catch (e) {
                // Silently handle Favorites errors
            }
        }

        // Update comments icon states after AJAX load
        updateCommentsIconStates();
        
        // Re-initialize any other dynamic elements that might need it
        // Trigger a custom event that other scripts can listen to
        document.dispatchEvent(new CustomEvent('destructoidAjaxContentLoaded', {
            detail: { type: 'pagination' }
        }));
    }
    
    // Function to update comments icon states based on comment counts
    function updateCommentsIconStates() {
        // Find all comments icons
        const commentsIcons = document.querySelectorAll('.comments-icon[data-post-id]');
        
        commentsIcons.forEach(function(icon) {
            const postId = icon.getAttribute('data-post-id');
            
            // Find the corresponding comment count element
            const commentCountElement = icon.parentElement.querySelector('.disqus-comment-count');
            
            if (commentCountElement) {
                // Get the comment count - need to wait a bit for Disqus to update
                setTimeout(function() {
                    const commentCount = parseInt(commentCountElement.textContent) || 0;
                    const currentTheme = document.cookie.match(/theme-preference=([^;]+)/)?.[1] || 'light';
                    
                    let newIconState, newIconPath;
                    
                    if (commentCount > 0) {
                        newIconState = 'on';
                        newIconPath = `/wp-content/themes/destructoid2025/assets/img/icons/comments-on.png`;
                    } else {
                        newIconState = 'off';
                        if (currentTheme === 'light') {
                            newIconPath = `/wp-content/themes/destructoid2025/assets/img/icons/comments-off-light.png`;
                        } else {
                            newIconPath = `/wp-content/themes/destructoid2025/assets/img/icons/comments-off.png`;
                        }
                    }
                    
                    // Update the icon if it's different
                    if (icon.src !== window.location.origin + newIconPath) {
                        icon.src = newIconPath;
                    }
                }, 1500); // Wait for Disqus to potentially update the count
            }
        });
    }
    
});