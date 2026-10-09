document.addEventListener("DOMContentLoaded", function () {
  var lazyEmbeds = [].slice.call(
    document.querySelectorAll(".lazy-loaded-embed, .lazy-social-embed"),
  );

  if ("IntersectionObserver" in window) {
    let lazyEmbedObserver = new IntersectionObserver(
      function (entries, observer) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            let lazyEmbed = entry.target;
            loadEmbed(lazyEmbed);
            observer.unobserve(lazyEmbed);
          }
        });
      },
      {
        root: null,
        rootMargin: "0px 0px 200px 0px", // Load embeds when they're 200px below the viewport
        threshold: 0,
      },
    );

    lazyEmbeds.forEach(function (lazyEmbed) {
      lazyEmbedObserver.observe(lazyEmbed);
    });
  } else {
    // Fallback for browsers that don't support IntersectionObserver
    window.addEventListener(
      "scroll",
      throttle(function () {
        lazyEmbeds.forEach(function (lazyEmbed) {
          if (isElementInViewport(lazyEmbed)) {
            loadEmbed(lazyEmbed);
            lazyEmbeds = lazyEmbeds.filter(function (embed) {
              return embed !== lazyEmbed;
            });
          }
        });
      }, 250),
    );
  }

  function loadEmbed(embed) {
    if (embed.tagName.toLowerCase() === "iframe") {
      embed.src = embed.dataset.src;
    } else if (embed.classList.contains("lazy-social-embed")) {
      let script = document.createElement("script");
      script.src = embed.dataset.src;
      script.async = true;
      embed.parentNode.insertBefore(script, embed.nextSibling);
      embed.remove();
    }
    embed.classList.remove("lazy-loaded-embed");
  }

  // Helper function to check if an element is in the viewport
  function isElementInViewport(el) {
    var rect = el.getBoundingClientRect();
    return (
      rect.top >= 0 &&
      rect.left >= 0 &&
      rect.bottom <=
        (window.innerHeight || document.documentElement.clientHeight) &&
      rect.right <= (window.innerWidth || document.documentElement.clientWidth)
    );
  }

  // Helper function to throttle scroll events
  function throttle(func, limit) {
    let inThrottle;
    return function () {
      const args = arguments;
      const context = this;
      if (!inThrottle) {
        func.apply(context, args);
        inThrottle = true;
        setTimeout(() => (inThrottle = false), limit);
      }
    };
  }
});
