'use strict';

function _createForOfIteratorHelper(o, allowArrayLike) { var it = typeof Symbol !== "undefined" && o[Symbol.iterator] || o["@@iterator"]; if (!it) { if (Array.isArray(o) || (it = _unsupportedIterableToArray(o)) || allowArrayLike && o && typeof o.length === "number") { if (it) o = it; var i = 0; var F = function F() {}; return { s: F, n: function n() { if (i >= o.length) return { done: true }; return { done: false, value: o[i++] }; }, e: function e(_e) { throw _e; }, f: F }; } throw new TypeError("Invalid attempt to iterate non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method."); } var normalCompletion = true, didErr = false, err; return { s: function s() { it = it.call(o); }, n: function n() { var step = it.next(); normalCompletion = step.done; return step; }, e: function e(_e2) { didErr = true; err = _e2; }, f: function f() { try { if (!normalCompletion && it["return"] != null) it["return"](); } finally { if (didErr) throw err; } } }; }

function _unsupportedIterableToArray(o, minLen) { if (!o) return; if (typeof o === "string") return _arrayLikeToArray(o, minLen); var n = Object.prototype.toString.call(o).slice(8, -1); if (n === "Object" && o.constructor) n = o.constructor.name; if (n === "Map" || n === "Set") return Array.from(o); if (n === "Arguments" || /^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(n)) return _arrayLikeToArray(o, minLen); }

function _arrayLikeToArray(arr, len) { if (len == null || len > arr.length) len = arr.length; for (var i = 0, arr2 = new Array(len); i < len; i++) { arr2[i] = arr[i]; } return arr2; }

function _classCallCheck(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } }

function _defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } }

function _createClass(Constructor, protoProps, staticProps) { if (protoProps) _defineProperties(Constructor.prototype, protoProps); if (staticProps) _defineProperties(Constructor, staticProps); Object.defineProperty(Constructor, "prototype", { writable: false }); return Constructor; }

var HurrytimerAction = /*#__PURE__*/function () {
  function HurrytimerAction(elementRef, config) {
    _classCallCheck(this, HurrytimerAction);

    this.elementRef = elementRef;
    this.config = config;
  }

  _createClass(HurrytimerAction, [{
    key: "changeStockStatus",
    value: function changeStockStatus(campaignId, status) {
      if (!jQuery.post) return;
      jQuery.post(hurrytimer_ajax_object.ajax_url, {
        nonce: hurrytimer_ajax_object.ajax_nonce,
        action: 'change_stock_status',
        status: status,
        campaign_id: campaignId
      });
    }
  }, {
    key: "hasMessageAction",
    value: function hasMessageAction() {
      var _iterator = _createForOfIteratorHelper(this.config.actions),
          _step;

      try {
        for (_iterator.s(); !(_step = _iterator.n()).done;) {
          var action = _step.value;

          if (action['id'] == hurrytimer_ajax_object.actionsOptions.displayMessage) {
            return true;
          }
        }
      } catch (err) {
        _iterator.e(err);
      } finally {
        _iterator.f();
      }

      return false;
    }
    /**
     * Hide campaign.
     */

  }, {
    key: "hide",
    value: function hide() {
      // We don't hide campaign if there is a message to display.
      if (this.hasMessageAction()) {
        return;
      }

      var stickyBar = this.elementRef.closest('.hurrytimer-sticky');

      if (stickyBar.length) {
        stickyBar.addClass('hurryt-loading');
      } else {
        this.elementRef.addClass('hurryt-loading');
      }
    }
    /**
     * Redirect to the given url.
     * @param url
     */

  }, {
    key: "hideAddToCartButton",
    value:
    /**
     * Hide "Add to cart" button.
     * @return void
     */
    function hideAddToCartButton() {
      var $addToCartForm = jQuery('.single_add_to_cart_button').closest('form.cart');

      if ($addToCartForm.length) {
        $addToCartForm.remove();
      }
    }
    /**
     * Display message by replacing campaign content with the given message.
     * @param message
     */

  }, {
    key: "displayMessage",
    value: function displayMessage(message) {
      var messageHtml = "<div class=\"hurrytimer-campaign-message\" data-id=\"".concat(this.config.id, "\">").concat(message, "</div>");
      this.elementRef.find('.hurrytimer-campaign-message').remove();
      var stickyBar = this.elementRef.closest('.hurrytimer-sticky');

      if (stickyBar.length) {
        this.elementRef.addClass('hurryt-loading');
        stickyBar.find('.hurrytimer-sticky-inner').append(messageHtml);
      } else {
        this.elementRef.addClass('hurryt-loading');
        this.elementRef.after(messageHtml);
      }
    }
  }, {
    key: "expireCoupon",
    value: function expireCoupon(code, message) {
      // Remove coupon if applied but expired and the checkout form has not been placed yet.
      jQuery('form.checkout').on('checkout_place_order', function (event) {
        validate_expired_coupon_checkout(event);
      });
      document.addEventListener("DOMContentLoaded", function () {
        validate_expired_coupon_checkout();
      });

      function validate_expired_coupon_checkout(event) {
        // Get applied coupons
        var appliedCoupons = jQuery('.woocommerce-checkout-review-order-table').find('.cart-discount');
        var isCouponExpired = false;
        appliedCoupons.each(function () {
          var couponCode = jQuery(this).find('.woocommerce-remove-coupon').data('coupon');

          if (couponCode.toLowerCase() === code.toLowerCase()) {
            isCouponExpired = true;
            return false;
          }
        });

        if (isCouponExpired) {
          var errorHtml = '<ul class="woocommerce-error" role="alert"><li>' + hurrytimer_ajax_object.invalid_checkout_coupon_message.replace('""', code) + '</li></ul>';
          var noticeGroup = jQuery('.woocommerce-NoticeGroup-checkout');

          if (noticeGroup.length) {
            noticeGroup.html(errorHtml);
          } else {
            var noticeGroupHtml = "<div class=\"woocommerce-NoticeGroup woocommerce-NoticeGroup-checkout\">".concat(errorHtml, "</div>");
            jQuery('form.checkout').before(noticeGroupHtml);
            jQuery('html, body').animate({
              scrollTop: jQuery('.woocommerce-NoticeGroup-checkout').offset().top - 100
            });
          }

          var container = jQuery('.woocommerce-checkout-review-order');
          container.addClass('processing').block({
            message: null,
            overlayCSS: {
              background: '#fff',
              opacity: 0.6
            }
          });
          jQuery.ajax({
            type: 'POST',
            url: wc_checkout_params.wc_ajax_url.toString().replace('%%endpoint%%', 'remove_coupon'),
            data: {
              security: wc_checkout_params.remove_coupon_nonce,
              coupon: code
            },
            success: function success(response) {
              container.removeClass('processing').unblock();

              if (response) {
                jQuery(document.body).trigger('removed_coupon_in_checkout', [code]);
                jQuery(document.body).trigger('update_checkout', {
                  update_shipping_method: false
                });
              }
            },
            error: function error(jqXHR) {
              if (wc_checkout_params.debug_mode) {
                console.log(jqXHR.responseText);
              }
            }
          });

          if (event) {
            event.preventDefault();
          }

          return false;
        }
      } // WC 7.5.x


      var originalFetch = window.fetch;

      window.fetch = function (url, options) {
        if (url.indexOf('wc-ajax=apply_coupon') !== -1) {
          var body = options.body;
          var searchParams = new URLSearchParams(body);
          var couponCode = searchParams.get('coupon_code');

          if (typeof couponCode === 'string' && couponCode.toLowerCase() === code.toLowerCase()) {
            jQuery('.woocommerce-error').remove();
            var $target = jQuery('.woocommerce-notices-wrapper:first') || jQuery('.cart-empty').closest('.woocommerce') || jQuery('.woocommerce-cart-form');
            $target.prepend("<ul class=\"woocommerce-error\" role=\"alert\"><li>".concat(message, "</li></ul>"));
            jQuery('.checkout_coupon').removeClass('processing').unblock();
            jQuery('.woocommerce-cart-form').removeClass('processing').unblock();
            return Promise.reject(new Error(message));
          }
        } else if (url.indexOf('/wc/store/v1/batch') !== -1) {
          var body = options.body;
          var requests = JSON.parse(body).requests || [];
          var abortController = new AbortController();
          options.signal = abortController.signal;
          requests.forEach(function (req) {
            if (req.path === '/wc/store/v1/cart/apply-coupon') {
              var couponCode = req.body.code;

              if (typeof couponCode === 'string' && couponCode.toLowerCase() === code.toLowerCase()) {
                abortController.abort();
                throw new Error(message);
              }
            }
          });
        }

        return originalFetch.apply(this, [url, options]);
      }; // WC 7.4.x


      jQuery.ajaxPrefilter(function (opts, originOpts, jqXHR) {
        if (opts.url.indexOf('wc-ajax=apply_coupon') === -1) return;
        if (typeof originOpts.data.coupon_code !== 'string' || typeof code !== 'string' || originOpts.data.coupon_code.toLowerCase() !== code.toLowerCase()) return;
        jqXHR.abort();
        jQuery('.woocommerce-error').remove();
        var $target = jQuery('.woocommerce-notices-wrapper:first') || jQuery('.cart-empty').closest('.woocommerce') || jQuery('.woocommerce-cart-form');
        $target.prepend("<ul class=\"woocommerce-error\" role=\"alert\"><li>".concat(message, "</li></ul>"));
        jQuery('.checkout_coupon').removeClass('processing').unblock();
        jQuery('.woocommerce-cart-form').removeClass('processing').unblock();
      });
    }
  }], [{
    key: "redirect",
    value: function redirect(url) {
      document.body.style.opacity = '0';
      document.body.style.display = 'none';

      if (url.trim().length === 0) {
        return;
      }

      if (hurrytimer_ajax_object.redirect_no_back) {
        window.location.replace(url);
      } else {
        window.location.href = url;
      }
    }
  }]);

  return HurrytimerAction;
}();
"use strict";

function _createForOfIteratorHelper(o, allowArrayLike) { var it = typeof Symbol !== "undefined" && o[Symbol.iterator] || o["@@iterator"]; if (!it) { if (Array.isArray(o) || (it = _unsupportedIterableToArray(o)) || allowArrayLike && o && typeof o.length === "number") { if (it) o = it; var i = 0; var F = function F() {}; return { s: F, n: function n() { if (i >= o.length) return { done: true }; return { done: false, value: o[i++] }; }, e: function e(_e) { throw _e; }, f: F }; } throw new TypeError("Invalid attempt to iterate non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method."); } var normalCompletion = true, didErr = false, err; return { s: function s() { it = it.call(o); }, n: function n() { var step = it.next(); normalCompletion = step.done; return step; }, e: function e(_e2) { didErr = true; err = _e2; }, f: function f() { try { if (!normalCompletion && it["return"] != null) it["return"](); } finally { if (didErr) throw err; } } }; }

function _unsupportedIterableToArray(o, minLen) { if (!o) return; if (typeof o === "string") return _arrayLikeToArray(o, minLen); var n = Object.prototype.toString.call(o).slice(8, -1); if (n === "Object" && o.constructor) n = o.constructor.name; if (n === "Map" || n === "Set") return Array.from(o); if (n === "Arguments" || /^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(n)) return _arrayLikeToArray(o, minLen); }

function _arrayLikeToArray(arr, len) { if (len == null || len > arr.length) len = arr.length; for (var i = 0, arr2 = new Array(len); i < len; i++) { arr2[i] = arr[i]; } return arr2; }

function _typeof(obj) { "@babel/helpers - typeof"; return _typeof = "function" == typeof Symbol && "symbol" == typeof Symbol.iterator ? function (obj) { return typeof obj; } : function (obj) { return obj && "function" == typeof Symbol && obj.constructor === Symbol && obj !== Symbol.prototype ? "symbol" : typeof obj; }, _typeof(obj); }

function _classCallCheck(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } }

function _defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } }

function _createClass(Constructor, protoProps, staticProps) { if (protoProps) _defineProperties(Constructor.prototype, protoProps); if (staticProps) _defineProperties(Constructor, staticProps); Object.defineProperty(Constructor, "prototype", { writable: false }); return Constructor; }

/*
 * global hurrytimer_ajax_object
 */
var HurrytimerCampaign = /*#__PURE__*/function () {
  function HurrytimerCampaign(elementRef, config, state) {
    _classCallCheck(this, HurrytimerCampaign);

    this.config = config;
    this.elementRef = elementRef;
    this.actionsOptions = hurrytimer_ajax_object.actionsOptions;
    this.restartOptions = hurrytimer_ajax_object.restartOptions;
    this.recurTimeoutId = -1;
    this.recurIntervalId = -1;
    this.retryCount = 0;
    this.startEventDispatched = false;
    this.state = state;
    this.restartIntervalId = -1;
    this.currentEndDate = null;
  }
  /**
   * @param endDateInMS
   * @return void
   */


  _createClass(HurrytimerCampaign, [{
    key: "setCookie",
    value: function setCookie(endDateInMS) {
      var options = {
        expires: 365
      };

      if (hurrytimer_ajax_object.COOKIEPATH) {
        options.path = hurrytimer_ajax_object.COOKIEPATH;
      }

      if (hurrytimer_ajax_object.COOKIE_DOMAIN) {
        options.domain = hurrytimer_ajax_object.COOKIE_DOMAIN;
      }

      Cookies.set(this.config.cookieName, endDateInMS, options);

      if (this.config.reset_token) {
        Cookies.set("".concat(this.config.cookieName, "_reset_token"), this.config.reset_token, {
          expires: 365
        });
      }
    }
    /**
     * Returns end date for the given duration.
     * @return {Date}
     */

  }, {
    key: "getEndDate",
    value: function getEndDate() {
      // Evergreen or recurring
      if (this.config.isRegular) {
        return new Date(this.config.endDate);
      }

      var date = new Date(parseInt(this.config.endDate));

      if (!this.isValidDate(date) || !this.config.endDate || this.should_reset() || this.allowRestart() || this.config.reload_reset) {
        if (_typeof(date) === 'object' && date.setTime != undefined) {
          this.unDismissStickyBar();
          date.setTime(this.calculateDate().getTime());
        }
      }

      this.setCookie(date.getTime());
      this.updateTimestamp(date.getTime());
      this.currentEndDate = date;
      return date;
    }
    /**
     * Check if the given date is valid.
     * @param {*} d
     */

  }, {
    key: "isValidDate",
    value: function isValidDate(d) {
      return Object.prototype.toString.call(d) === '[object Date]' && !isNaN(d.getTime());
    }
    /**
     * This is useful to force timestamp update when the page is cached.
     */

  }, {
    key: "updateTimestamp",
    value: function updateTimestamp(endDateTimeTS) {
      if (jQuery.ajax === undefined) return;
      var args = {
        url: hurrytimer_ajax_object.ajax_url,
        async: true,
        type: 'POST',
        data: {
          nonce: hurrytimer_ajax_object.ajax_nonce,
          timestamp: endDateTimeTS,
          cid: this.config.id,
          action: 'hurryt/update_timestamp'
        }
      };
      jQuery.ajax(args);
    }
    /**
     * Returns true if the campaign should reset.
     *
     * @return {number}
     */

  }, {
    key: "should_reset",
    value: function should_reset() {
      return this.config.should_reset;
    }
    /**
     * Remove sticky bar dismiss if available for current given campaign.
     */

  }, {
    key: "unDismissStickyBar",
    value: function unDismissStickyBar() {
      Cookies.remove("_ht_CDT-".concat(this.config.id, "_dismissed"));
    }
    /**
     * Returns true if the campaign will restart.
     * @return {boolean}
     */

  }, {
    key: "allowRestart",
    value: function allowRestart() {
      if (this.config.isRegular) return false;
      return this.isExpired() && (this.allowRestartImmediately() || this.allowRestartAfterReload() || this.durationSinceExpiryIsOver());
    }
    /**
     * Campaign expired.
     */

  }, {
    key: "isExpired",
    value: function isExpired() {
      var today = new Date();
      return this.config.endDate < today;
    }
  }, {
    key: "duratinSinceExpiration",
    value: function duratinSinceExpiration() {
      var endDate = this.currentEndDate || this.config.endDate;

      if (!endDate) {
        return 0;
      }

      var now = new Date();
      var diff = now.getTime() - endDate;
      return diff / 1000;
    }
  }, {
    key: "durationSinceExpiryIsOver",
    value: function durationSinceExpiryIsOver() {
      return this.shouldRestartAfterDuration() && this.duratinSinceExpiration() >= this.config.restart_duration;
    }
    /**
     * Restart on refresh.
     *
     * @returns {boolean}
     */

  }, {
    key: "allowRestartAfterReload",
    value: function allowRestartAfterReload() {
      return parseInt(this.config.restart) === parseInt(this.restartOptions.afterReload);
    }
    /**
     * Restart immediatly.
     *
     * @returns {boolean}
     */

  }, {
    key: "allowRestartImmediately",
    value: function allowRestartImmediately() {
      return parseInt(this.config.restart) === parseInt(this.restartOptions.immediately);
    }
  }, {
    key: "shouldRestartAfterDuration",
    value: function shouldRestartAfterDuration() {
      return this.config.restart == this.restartOptions.after_duration;
    }
    /**
     * Returns true if the campaign has an action.
     */

  }, {
    key: "hasAction",
    value: function hasAction() {
      return this.config.actions.length;
    }
    /**
     * Calculate date based on the given duration.
     * @return {Date}
     */

  }, {
    key: "calculateDate",
    value: function calculateDate() {
      var date = new Date();
      date.setSeconds(date.getSeconds() + this.config.duration);
      return date;
    }
    /**
     * Run registered actions.
     */

  }, {
    key: "executeActions",
    value: function executeActions() {
      if (parseInt(hurrytimer_ajax_object.disable_actions) === 1) {
        return false;
      } // No action, abort.


      if (this.hasAction()) {
        var _iterator = _createForOfIteratorHelper(this.config.actions),
            _step;

        try {
          for (_iterator.s(); !(_step = _iterator.n()).done;) {
            var action = _step.value;
            var actionManager = new HurrytimerAction(this.elementRef, this.config);

            if (this.config.run_in_background) {
              if (action['id'] == this.actionsOptions.expire_coupon) {
                actionManager.expireCoupon(action['coupon'], hurrytimer_ajax_object.expire_coupon_message);
              }
            } else {
              switch (action['id']) {
                case this.actionsOptions.redirect:
                  HurrytimerAction.redirect(action['redirectUrl']);
                  break;

                case this.actionsOptions.displayMessage:
                  actionManager.displayMessage(action['message']);
                  break;

                case this.actionsOptions.hideAddToCartButton:
                  actionManager.hideAddToCartButton();
                  break;

                case this.actionsOptions.stockStatus:
                  if (this.config.isRegular) {
                    actionManager.changeStockStatus(this.config.id, action['wcStockStatus']);
                  }

                  break;

                case this.actionsOptions.hide:
                  actionManager.hide();
                  break;
              }
            }
          }
        } catch (err) {
          _iterator.e(err);
        } finally {
          _iterator.f();
        }
      }
    }
  }, {
    key: "maybeShowCampaign",
    value: function maybeShowCampaign() {
      if (this.elementRef.length && !this.config.run_in_background) {
        // Remove message tag if present.
        var $message = this.elementRef.parent().find(".hurrytimer-campaign-message[data-id=\"".concat(this.config.id, "\"]"));

        if ($message.length) {
          $message.remove();
        }

        this.elementRef.removeClass('hurryt-loading');
      }

      var stickyBar = this.elementRef.closest('.hurrytimer-sticky');

      if (stickyBar.length) {
        // Remove message tag if present.
        var _$message = this.elementRef.find('.hurrytimer-campaign-message');

        if (_$message.length) {
          _$message.remove();
        }

        stickyBar.removeClass('hurryt-loading');
      }
    }
    /**
     * Maybe run countdown timer.
     */

  }, {
    key: "waitThenRun",
    value: function waitThenRun() {
      var _this = this;

      this.restartIntervalId = setInterval(function () {
        if (_this.durationSinceExpiryIsOver()) {
          clearInterval(_this.restartIntervalId);

          _this.run();
        }
      }, 1000);
    }
  }, {
    key: "run",
    value: function run() {
      var _this2 = this;

      this.triggerInitEvent();
      this.elementRef.countdown(this.getEndDate(), function (e) {
        return _this2.onCountdownUpdate(e);
      });
      var stickyBar = this.elementRef.closest('.hurrytimer-sticky');
      this.handleStickyBar(stickyBar);
    }
    /**
     * Handle sticky bar visibility.
     * @param {*} stickyBar
     */

  }, {
    key: "handleStickyBar",
    value: function handleStickyBar(stickyBar) {
      var _this3 = this;

      if (stickyBar.length === 0) return;
      var dismissCookie = Cookies.get("_ht_CDT-".concat(this.config.id, "_dismissed")); // Stick bar hasn't been dismissed.

      if (dismissCookie == undefined) {
        stickyBar.on('click', '.hurrytimer-sticky-close', function () {
          return _this3.onStickyBarDismiss(stickyBar);
        });
      } else {
        this.hideStickyBar(stickyBar);
      }
    }
    /**
     * Hide Sticky Bar
     * @param {*} stickyBar
     */

  }, {
    key: "hideStickyBar",
    value: function hideStickyBar(stickyBar) {
      if (stickyBar.length === 0) return;
      var isTopPinned = stickyBar.css('top') === '0px';
      stickyBar.remove();

      if (isTopPinned) {
        jQuery('body').css('margin-top', 0);
      } else {
        jQuery('body').css('margin-bottom', 0);
      }
    }
    /**
     * Handle sticky bar dismiss.
     */

  }, {
    key: "onStickyBarDismiss",
    value: function onStickyBarDismiss(stickyBar) {
      this.hideStickyBar(stickyBar);
      Cookies.set("_ht_CDT-".concat(this.config.id, "_dismissed"), '1', {
        expires: +this.config.sticky_bar_hide_timeout
      });
    }
    /**
     * Countdown timer start callback.
     * @param event
     */

  }, {
    key: "onCountdownUpdate",
    value: function onCountdownUpdate(event) {
      this.render(event);
      this.maybeShowCampaign();

      if (event.elapsed && event.type === 'finish') {
        this.executeActions();
        this.triggerFinishEvent();
        this.maybeRecur();

        if (this.allowRestartImmediately()) {
          this.run();
        }

        if (this.shouldRestartAfterDuration()) {
          this.waitThenRun();
        }
      }
    }
  }, {
    key: "triggerFinishEvent",
    value: function triggerFinishEvent() {
      var params = {
        id: this.config.id,
        mode: this.config.mode,
        endAt: this.config.endDate
      };
      this.elementRef.trigger('hurryt:finished', params);
    }
  }, {
    key: "triggerInitEvent",
    value: function triggerInitEvent() {
      var params = {
        id: this.config.id,
        mode: this.config.mode,
        endAt: this.config.endDate
      };
      jQuery('.hurrytimer-campaign').trigger('hurryt:init', params);
    }
  }, {
    key: "triggerStartEvent",
    value: function triggerStartEvent() {
      if (!this.startEventDispatched) {
        var params = {
          id: this.config.id,
          mode: this.config.mode,
          endAt: this.config.endDate
        };
        this.elementRef.trigger('hurryt:started', params);
        this.startEventDispatched = true;
      }
    }
    /**
     * Render countdown timer.
     * @param event
     */

  }, {
    key: "render",
    value: function render(event) {
      if (hurrytimer_ajax_object.run_in_background) {
        this.elementRef.html('');
      } else {
        this.elementRef.find('.hurrytimer-timer').html(event.strftime(this.config.template));
      }

      this.triggerStartEvent();
    }
    /**
     * Calculate the remaining time until the next recurrence.
     * 
     * @return int
     */

  }, {
    key: "willRecurNow",
    value: function willRecurNow() {
      var now = new Date();
      var prev_recurrence_time = this.getEndDate().getTime() + this.config.timeToNextRecurrence * 1000;
      return now.getTime() >= prev_recurrence_time;
    }
    /**
     * Run the next recurrence if available.
     */

  }, {
    key: "maybeRecur",
    value: function maybeRecur() {
      var _this4 = this;

      // Not a recurring campaign.
      if (!this.config.recurr) return; // the jQuery ajax function is required to fetch the next recurrence.

      if (jQuery.ajax === undefined) return;
      clearTimeout(this.recurTimeoutId);
      clearInterval(this.recurIntervalId);
      this.recurIntervalId = setInterval(function () {
        if (!_this4.willRecurNow()) {
          return;
        }

        clearInterval(_this4.recurIntervalId);
        jQuery.ajax({
          url: hurrytimer_ajax_object.ajax_url,
          data: {
            action: 'next_recurrence',
            nonce: hurrytimer_ajax_object.ajax_nonce,
            id: _this4.config.id
          },
          error: function error() {
            if (_this4.retryCount === 10) return;
            _this4.retryCount++;
            setTimeout(function () {
              _this4.maybeRecur();
            }, 1000);
          },
          success: function success(_ref) {
            var data = _ref.data;
            _this4.retryCount = 0;
            if (!data) return;

            if (isNaN(data.endTimestamp)) {
              return;
            }

            _this4.config.endDate = data.endTimestamp; // TODO: Handle lateness:
            // retry for one minute if the received end date is still expired.

            _this4.run();
          }
        });
      }, 1000);
    }
  }]);

  return HurrytimerCampaign;
}();
'use strict';

function _typeof(obj) { "@babel/helpers - typeof"; return _typeof = "function" == typeof Symbol && "symbol" == typeof Symbol.iterator ? function (obj) { return typeof obj; } : function (obj) { return obj && "function" == typeof Symbol && obj.constructor === Symbol && obj !== Symbol.prototype ? "symbol" : typeof obj; }, _typeof(obj); }

(function ($) {
  // TODO: delete `state`.
  var state = {
    reseting: []
  };
  var $body = $('body');

  function onElementInserted(containerSelector, elementSelector, callback) {
    var onMutationsObserved = function onMutationsObserved(mutations) {
      mutations.forEach(function (mutation) {
        if (mutation.addedNodes.length) {
          var elements = $(mutation.addedNodes).find(elementSelector);

          for (var i = 0, len = elements.length; i < len; i++) {
            callback(elements[i]);
          }
        }
      });
    };

    var target = $(containerSelector)[0];
    var config = {
      childList: true,
      subtree: true
    };
    var MutationObserver = window.MutationObserver || window.WebKitMutationObserver;
    var observer = new MutationObserver(onMutationsObserved);
    observer.observe(target, config);
  }

  document.addEventListener('DOMContentLoaded', function () {
    var initialElements = document.querySelectorAll('.hurrytimer-campaign');
    initialElements.forEach(initCallback);
    onElementInserted('body', '.hurrytimer-campaign', initCallback);
  });

  function initCallback(e) {
    if ($(e).parents('div[data-elementor-type=popup]').length === 0) {
      runCampaign($(e));
    }
  }

  $(document).on('elementor/popup/show', function (event, id) {
    // Run only campaigns within a Elementor popup.
    $(".elementor-".concat(id, " .hurrytimer-campaign")).each(function () {
      runCampaign($(this));
    });
  });
  /**
   *
   * @param $campaign jQuery
   */

  function runCampaign($campaign) {
    // TODO: Inject config object in the <head> tag or inline.
    var config = $campaign.data('config');
    if (config === undefined) return; // Check if the config object is corrupt.

    if (_typeof(config) !== 'object') {
      config = JSON.parse(config.replace(/\s+/g, " "));
    }

    $campaign.removeAttr('data-config');
    $campaign.trigger('hurryt:pre-init', {
      id: config.id,
      mode: config.mode,
      endAt: config.endAt
    });
    var $sticky = $campaign.closest('.hurrytimer-sticky'); // Display sticky bar if present.

    if ($sticky.length) {
      $body.append($sticky);
      $(window).resize(function () {
        if ($sticky.css('top') === '0px') {
          // Pin at the top.
          $body.css('margin-top', $sticky.outerHeight());
        } else {
          // Pin at the bottom.
          $body.css('margin-bottom', $sticky.outerHeight());
        }
      });
      setTimeout(function () {
        $(window).trigger('resize');
      });
    }

    new HurrytimerCampaign($campaign, config, state).run();
  }
})(jQuery);