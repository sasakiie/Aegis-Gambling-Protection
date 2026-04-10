// ===================================================================
// AEGIS Ad Blocker v2.0 — General Advertisement Removal
// ===================================================================
// หน้าที่: ลบโฆษณาทั่วไป (Google Ads, video ads, native ads, popups)
//         ออกจากหน้าเว็บเพื่อให้อ่านเนื้อหาได้สะดวก
//
// แยกจาก sanitizer.js (ที่ทำเฉพาะ gambling detection)
//
// วิธีบล็อก 4 ระดับ:
//   1. CSS Injection     → ซ่อน ad containers ทันทีก่อน render
//   2. DOM Removal       → ลบ elements โฆษณาออกจาก DOM
//   3. Parent Climb      → ลบ parent container ที่ห่อ ad ไว้
//   4. MutationObserver  → จับโฆษณาที่โหลดทีหลัง (lazy-loaded)
//
// ทดสอบกับ: thairath.co.th, sanook.com, kapook.com, pantip.com
//
// สื่อสารกับ Flutter:
//   AegisAdBlock.postMessage('...') → ส่ง log ไป Dashboard
// ===================================================================

(function () {
    'use strict';

    // ป้องกัน inject ซ้ำ
    if (window._aegisAdBlockLoaded) return;
    window._aegisAdBlockLoaded = true;

    var removedCount = 0;

    // ════════ Logger ════════

    function log(msg) {
        if (window.AegisAdBlock) window.AegisAdBlock.postMessage(msg);
        console.log('[AEGIS-AD] ' + msg);
    }

    function isCoexistMode() {
        try {
            return !!(window._aegisConfig && window._aegisConfig.gamblingProtectionEnabled);
        } catch (e) {
            return false;
        }
    }

    function shouldPreserveContentContainer(el) {
        if (!el || !el.tagName) return true;
        if (el === document.body || el === document.documentElement) return true;

        try {
            var tag = el.tagName.toUpperCase();
            if (tag === 'BODY' || tag === 'HTML' || tag === 'MAIN' ||
                tag === 'ARTICLE' || tag === 'SECTION' || tag === 'HEADER' ||
                tag === 'FOOTER' || tag === 'NAV') {
                return true;
            }

            var text = (el.textContent || '').trim();
            var childCount = el.querySelectorAll ? el.querySelectorAll('*').length : 0;
            if (text.length > 500 || childCount > 30) return true;

            var rect = el.getBoundingClientRect ? el.getBoundingClientRect() : null;
            if (rect) {
                var vpArea = Math.max(window.innerWidth * window.innerHeight, 1);
                var coverage = (rect.width * rect.height) / vpArea;
                if (coverage > 0.60 && (text.length > 120 || childCount > 12)) {
                    return true;
                }
            }
        } catch (e) { }

        return false;
    }

    // ════════ Layer 1: CSS Injection ════════
    // ซ่อน ad containers ทันทีด้วย CSS → ไม่ต้องรอ DOM scan
    // ───────────────────────────────────────────────────────────

    function injectAdBlockCSS() {
        if (document.getElementById('aegis-adblock-css')) return;

        var style = document.createElement('style');
        var coexistMode = isCoexistMode();
        var cssRules = [
            // ─── Google Ads / DFP / GPT ───
            'ins.adsbygoogle { display: none !important; }',
            '[id^="google_ads_"] { display: none !important; }',
            '[id^="div-gpt-ad"] { display: none !important; }',
            'iframe[src*="doubleclick.net"] { display: none !important; }',
            'iframe[src*="googlesyndication.com"] { display: none !important; }',
            'iframe[src*="googleadservices.com"] { display: none !important; }',
            'iframe[src*="googleads.g.doubleclick.net"] { display: none !important; }',
            'iframe[id^="google_ads"] { display: none !important; }',
            '[data-ad-slot] { display: none !important; }',
            '[data-ad-client] { display: none !important; }',
            '[data-google-query-id] { display: none !important; }',
            '.cbb, #cbb { display: none !important; }',       // Google Ads close button
            '.abgl, #abgl { display: none !important; }',     // AdChoices icon

            // ─── Taboola / Outbrain / Mgid (Native Ads) ───
            '[id^="taboola-"] { display: none !important; }',
            '.taboola-widget { display: none !important; }',
            'div[class^="trc_"] { display: none !important; }',      // Taboola trc_ containers
            'div[class*=" trc_"] { display: none !important; }',     // Taboola trc_ with space
            'span[class^="trc_"] { display: none !important; }',
            '.trc_related_container { display: none !important; }',
            '.trc_rbox { display: none !important; }',
            '.trc_elastic { display: none !important; }',
            '[data-widget-id*="taboola"] { display: none !important; }',
            'a[href*="popup.taboola.com"] { display: none !important; }',
            '[aria-label*="Taboola"] { display: none !important; }',
            '.branding-inner { display: none !important; }',
            '.trc_desktop_disclosure_link { display: none !important; }',
            '[id^="outbrain_"] { display: none !important; }',
            '.OUTBRAIN { display: none !important; }',
            '[id^="mgid-"] { display: none !important; }',

            // ─── Native / Sponsored Ads ───
            '[class*="sponsored-content"] { display: none !important; }',
            '[class*="promoted-content"] { display: none !important; }',
            '[class*="native-ad"] { display: none !important; }',
            '[data-type="ad"] { display: none !important; }',
            'article[data-ad] { display: none !important; }',

            // ─── Popup / Overlay / Notification Ads ───
            '[class*="ad-overlay"] { display: none !important; }',
            '[class*="ad-modal"] { display: none !important; }',
            '[class*="ad-popup"] { display: none !important; }',
            '[class*="interstitial-ad"] { display: none !important; }',
            '#onesignal-slidedown-dialog-container { display: none !important; }',
            '#onesignal-slidedown-container { display: none !important; }',
            '.onesignal-slidedown-dialog { display: none !important; }',

            // ─── Cookie Consent Banners ───
            '.closecookie { display: none !important; }',
            '[id*="cookie-consent"] { display: none !important; }',
            '[id*="cookie-banner"] { display: none !important; }',
        ];

        if (!coexistMode) {
            cssRules = cssRules.concat([
                '.ad-banner { display: none !important; }',
                '.ad-container { display: none !important; }',
                '.ad-wrapper { display: none !important; }',
                '.ad-slot { display: none !important; }',
                '.ad-unit { display: none !important; }',
                '.ad-block { display: none !important; }',
                '.ad-placement { display: none !important; }',
                '.advertisement { display: none !important; }',
                '.ad-box { display: none !important; }',
                '#ad-container { display: none !important; }',
                '#ad-banner { display: none !important; }',
                '#ad-wrapper { display: none !important; }',
                '[class*="ad-leaderboard"] { display: none !important; }',
                '[class*="ad-sidebar"] { display: none !important; }',
                '[class*="ad-footer"] { display: none !important; }',
                '[class*="ad-header"] { display: none !important; }',
                '[class*="video-ad"] { display: none !important; }',
                '[id*="player-ads"] { display: none !important; }',
                '[class*="preroll"] { display: none !important; }',
                '[class*="midroll"] { display: none !important; }',
                '[class*="cookie-banner"] { display: none !important; }',
                '[class*="cookie-consent"] { display: none !important; }',
                '[class*="gdpr-banner"] { display: none !important; }',
                '[class*="discover-more"] { display: none !important; }',
                '[class*="recommended-ads"] { display: none !important; }',
                '[class*="content-recommendation"] { display: none !important; }',
                '[class*="sticky-ad"] { display: none !important; }',
                '[class*="fixed-ad"] { display: none !important; }',
                '[class*="bottom-ad"] { display: none !important; }',
                '[class*="top-ad"] { display: none !important; }',
            ]);
        }

        style.id = 'aegis-adblock-css';
        style.textContent = cssRules.join('\n');

        // insert ที่ <head> ทันที
        if (document.head) {
            document.head.appendChild(style);
        } else if (document.documentElement) {
            document.documentElement.appendChild(style);
        }
        log('\uD83D\uDEE1\uFE0F CSS ad-block rules injected (' + style.textContent.split('\n').length + ' rules' + (coexistMode ? ', coexist-safe mode' : '') + ')');
    }

    // ════════ Layer 2: DOM Removal ════════
    // ลบ elements โฆษณาออกจาก DOM หลัง page load
    // ─────────────────────────────────────────

    // Ad network domains ที่ต้องบล็อก (ใช้เช็ค iframe src)
    var AD_NETWORK_DOMAINS = [
        'doubleclick.net',
        'googlesyndication.com',
        'googleadservices.com',
        'googleads.g.doubleclick.net',
        'adnxs.com',
        'adsrvr.org',
        'adservice.google',
        'pagead2.googlesyndication.com',
        'tpc.googlesyndication.com',
        'amazon-adsystem.com',
        'facebook.com/tr',
        'connect.facebook.net',
        'ads.pubmatic.com',
        'rubiconproject.com',
        'casalemedia.com',
        'criteo.com',
        'taboola.com',
        'cdn.taboola.com',
        'trc.taboola.com',
        'outbrain.com',
        'mgid.com',
        'revcontent.com',
        'ad.doubleclick.net',
        'onesignal.com',
        'cdn.onesignal.com',
    ];

    // CSS selectors สำหรับ ad containers ที่ต้องลบ
    var AD_SELECTORS = [
        // Google Ads
        'ins.adsbygoogle',
        '[id^="google_ads_"]',
        '[id^="div-gpt-ad"]',
        '[data-ad-slot]',
        '[data-ad-client]',
        '[data-google-query-id]',
        '.cbb', '#cbb',
        '.abgl', '#abgl',

        // Taboola
        '[id^="taboola-"]',
        '.taboola-widget',
        'div[class^="trc_"]',
        'div[class*=" trc_"]',
        'span[class^="trc_"]',
        '.trc_related_container',
        '.trc_rbox',
        '.trc_elastic',
        '[data-widget-id*="taboola"]',
        'a[href*="popup.taboola.com"]',
        '[aria-label*="Taboola"]',
        '.branding-inner',
        '.trc_desktop_disclosure_link',

        // Outbrain / Mgid
        '[id^="outbrain_"]',
        '.OUTBRAIN',
        '[id^="mgid-"]',

        // AMP ads
        'amp-ad',
        'amp-embed',

        // Notification/Cookie popups
        '#onesignal-slidedown-dialog-container',
        '#onesignal-slidedown-container',
        '.onesignal-slidedown-dialog',
        '.closecookie',
        '[id*="cookie-consent"]',
        '[id*="cookie-banner"]',
    ];

    var COEXIST_SAFE_SELECTORS = [
        'ins.adsbygoogle',
        '[id^="google_ads_"]',
        '[id^="div-gpt-ad"]',
        '[data-ad-slot]',
        '[data-ad-client]',
        '[data-google-query-id]',
        '.cbb', '#cbb',
        '.abgl', '#abgl',
        '[id^="taboola-"]',
        '.taboola-widget',
        'div[class^="trc_"]',
        'div[class*=" trc_"]',
        'span[class^="trc_"]',
        '.trc_related_container',
        '.trc_rbox',
        '.trc_elastic',
        '[data-widget-id*="taboola"]',
        'a[href*="popup.taboola.com"]',
        '[aria-label*="Taboola"]',
        '.branding-inner',
        '.trc_desktop_disclosure_link',
        '[id^="outbrain_"]',
        '.OUTBRAIN',
        '[id^="mgid-"]',
        '#onesignal-slidedown-dialog-container',
        '#onesignal-slidedown-container',
        '.onesignal-slidedown-dialog',
        '.closecookie',
        '[id*="cookie-consent"]',
        '[id*="cookie-banner"]',
    ];

    // Class/ID patterns ที่บ่งบอกว่าเป็น ad container
    var AD_CLASS_PATTERNS = [
        'ad-banner', 'ad-container', 'ad-wrapper', 'ad-slot',
        'ad-unit', 'ad-block', 'ad-placement', 'ad-leaderboard',
        'ad-sidebar', 'ad-footer', 'ad-header', 'ad-box',
        'advertisement', 'ad-overlay', 'ad-modal', 'ad-popup',
        'sponsored-content', 'promoted-content', 'native-ad',
        'video-ad', 'preroll', 'midroll', 'interstitial',
        'sticky-ad', 'fixed-ad', 'bottom-ad', 'top-ad',
        'discover-more', 'recommended-ads',
    ];

    /**
     * isAdElement — เช็คว่า element เป็น ad จาก class/id patterns
     */
    function isAdElement(el) {
        var className = '';
        var id = '';
        try {
            className = (el.className || '').toString().toLowerCase();
            id = (el.id || '').toLowerCase();
        } catch (e) { return false; }

        // เช็ค class/id patterns
        for (var i = 0; i < AD_CLASS_PATTERNS.length; i++) {
            if (className.indexOf(AD_CLASS_PATTERNS[i]) !== -1) return true;
            if (id.indexOf(AD_CLASS_PATTERNS[i]) !== -1) return true;
        }

        // เช็ค Taboola trc_ prefix ใน className
        if (className.indexOf('trc_') !== -1) return true;

        // เช็ค Google Ads wrapper patterns
        if (/^aw\d+$/.test(className.trim())) return true;  // aw0, aw1, etc.

        return false;
    }

    /**
     * isAdIframe — เช็คว่า iframe เป็น ad network
     */
    function isAdIframe(iframe) {
        var src = '';
        try { src = (iframe.getAttribute('src') || '').toLowerCase(); } catch (e) { return false; }
        if (!src) return false;

        for (var i = 0; i < AD_NETWORK_DOMAINS.length; i++) {
            if (src.indexOf(AD_NETWORK_DOMAINS[i]) !== -1) return true;
        }
        return false;
    }

    /**
     * removeAd — ลบ ad element จาก DOM
     */
    function removeAd(el, reason) {
        if (!el || !el.parentNode) return false;
        if (isCoexistMode() && shouldPreserveContentContainer(el)) {
            try { el.setAttribute('data-aegis-ad', '1'); } catch (e) { }
            log('\u26A0\uFE0F Preserved content container \u2014 ' + reason);
            return false;
        }
        var tag = el.tagName ? el.tagName.toLowerCase() : '?';
        var id = '';
        try { id = el.id ? '#' + el.id : ''; } catch (e) { }
        var cls = '';
        try { cls = el.className ? '.' + el.className.toString().split(' ')[0] : ''; } catch (e) { }
        var identifier = id || cls || tag;

        // Mark as processed
        try { el.setAttribute('data-aegis-ad', '1'); } catch (e) { }
        el.remove();
        removedCount++;
        log('\uD83D\uDEAB Removed ad: <' + tag + '> ' + identifier.substring(0, 50) + ' \u2014 ' + reason);
        return true;
    }

    /**
     * isProcessed — เช็คว่า element ถูกประมวลผลแล้ว
     */
    function isProcessed(el) {
        try {
            return el && el.getAttribute && el.getAttribute('data-aegis-ad') === '1';
        } catch (e) { return false; }
    }

    // ════════ Layer 3: Parent Climb (Safe Version) ════════
    // ลบ parent container ที่ห่อโฆษณาไว้
    // !! ปรับแก้: ปีนแค่ 2 ระดับ + ป้องกันลบ content sections !!
    // ─────────────────────────────────────────

    // Tags ที่เป็น content sections → ห้ามลบ
    var PROTECTED_TAGS = [
        'BODY', 'MAIN', 'ARTICLE', 'SECTION', 'HEADER', 'FOOTER',
        'NAV', 'FORM', 'TABLE', 'UL', 'OL',
    ];

    /**
     * climbAndRemoveAdParent — ปีนขึ้นไปหา parent ที่ห่อ ad
     * Logic (Safe):
     *   1. จาก ad element → ปีนสูงสุด 2 ระดับ (ลดจาก 3)
     *   2. ถ้า parent มี children > 2 → หยุด
     *   3. ถ้า parent เป็น content tag → หยุด
     *   4. ถ้า parent มี text content > 100 chars → หยุด (มีเนื้อหาจริง)
     */
    function climbAndRemoveAdParent(el, reason) {
        var current = el;
        var toRemove = el;

        for (var level = 0; level < 2; level++) {
            var parent = current.parentElement;
            if (!parent) break;

            // ห้ามลบ content sections
            var parentTag = parent.tagName.toUpperCase();
            if (PROTECTED_TAGS.indexOf(parentTag) !== -1) break;

            // ข้ามถ้า parent มี children เยอะ (> 2 = มีเนื้อหาอื่น)
            var siblingCount = parent.children.length;
            if (siblingCount > 2) break;

            // ข้ามถ้า parent มี text content จริง (> 100 chars)
            try {
                var parentText = parent.textContent || '';
                if (parentText.trim().length > 100) break;
            } catch (e) { break; }

            toRemove = parent;
            current = parent;
        }

        if (isCoexistMode() && shouldPreserveContentContainer(toRemove)) {
            try { toRemove.setAttribute('data-aegis-ad', '1'); } catch (e) { }
            log('\u26A0\uFE0F Parent climb stopped to preserve content \u2014 ' + reason);
            return false;
        }

        return removeAd(toRemove, reason);
    }

    /**
     * scanForAds — สแกน DOM หา ad elements
     */
    function scanForAds() {
        var removed = 0;
        var coexistMode = isCoexistMode();
        var selectorsToScan = coexistMode ? COEXIST_SAFE_SELECTORS : AD_SELECTORS;

        // Phase 1: ลบ iframes จาก ad networks (ลบแค่ iframe เอง ไม่ปีน parent)
        var iframes = document.querySelectorAll('iframe');
        for (var i = 0; i < iframes.length; i++) {
            if (isProcessed(iframes[i])) continue;
            if (isAdIframe(iframes[i])) {
                if (removeAd(iframes[i], 'ad network iframe')) removed++;
            }
        }

        // Phase 2: ลบ ad containers ตาม CSS selectors
        for (var s = 0; s < selectorsToScan.length; s++) {
            try {
                var els = document.querySelectorAll(selectorsToScan[s]);
                for (var j = 0; j < els.length; j++) {
                    if (isProcessed(els[j])) continue;
                    if (climbAndRemoveAdParent(els[j], 'ad selector: ' + selectorsToScan[s])) removed++;
                }
            } catch (e) { }
        }

        // Phase 3: ลบ elements ที่มี ad class/id patterns
        if (!coexistMode) {
            var containers = document.querySelectorAll('div, section, aside, ins, article, span');
            for (var k = 0; k < containers.length; k++) {
                if (isProcessed(containers[k])) continue;
                if (isAdElement(containers[k])) {
                    if (removeAd(containers[k], 'ad class/id pattern')) removed++;
                }
            }
        }

        // Phase 4: ลบ iframes ที่เป็น tracking pixels (1x1 หรือ 0x0)
        var allIframes = document.querySelectorAll('iframe');
        for (var m = 0; m < allIframes.length; m++) {
            if (isProcessed(allIframes[m])) continue;
            var rect;
            try { rect = allIframes[m].getBoundingClientRect(); } catch (e) { continue; }
            if (rect.width <= 1 && rect.height <= 1) {
                try { allIframes[m].setAttribute('data-aegis-ad', '1'); } catch (e) { }
                allIframes[m].remove();
                removed++;
            }
        }

        // เมื่อเปิดร่วมกับ Gambling Protection ให้หยุดแค่ explicit ad rules
        // เพื่อลดโอกาสลบ container ใหญ่หรือเนื้อหาหลักของหน้าเว็บ
        if (coexistMode) {
            return removed;
        }

        // Phase 5: ลบ container ที่มี "Advertisement" label
        var allDivs = document.querySelectorAll('div, aside, section');
        for (var n = 0; n < allDivs.length; n++) {
            if (isProcessed(allDivs[n])) continue;
            var el = allDivs[n];
            try {
                var text = (el.textContent || '').trim();
                var childCount = el.querySelectorAll('*').length;

                // Small container ที่มีข้อความ "Advertisement"
                if (text.length < 80 && childCount < 10) {
                    if (/^(Advertisement|Sponsored|Promoted|Ad|โฆษณา)\s*:?\s*$/i.test(text)) {
                        var r = el.getBoundingClientRect();
                        if (r.height > 20) {
                            if (removeAd(el, 'labeled ad container')) removed++;
                        }
                    }
                }

                // "Advertisement: X:XX" video ad labels
                if (/Advertisement:\s*\d+:\d+/i.test(text) && childCount < 20) {
                    if (climbAndRemoveAdParent(el, 'video ad label')) removed++;
                }
            } catch (e) { }
        }

        // Phase 6: ลบ fixed/sticky elements ที่เป็นโฆษณา
        var fixedEls = document.querySelectorAll('div, aside, section, nav');
        for (var p = 0; p < fixedEls.length; p++) {
            if (isProcessed(fixedEls[p])) continue;
            try {
                var style = window.getComputedStyle(fixedEls[p]);
                var pos = style.getPropertyValue('position');
                if (pos !== 'fixed' && pos !== 'sticky') continue;

                var zIdx = parseInt(style.getPropertyValue('z-index') || '0', 10);
                if (isNaN(zIdx)) zIdx = 0;
                var fRect = fixedEls[p].getBoundingClientRect();

                // Sticky bottom bar ads (กว้าง > 60% viewport, สูง < 250px, อยู่ล่าง)
                if (fRect.width > window.innerWidth * 0.6 &&
                    fRect.height < 250 && fRect.height > 10 &&
                    fRect.bottom > window.innerHeight - 20) {
                    // เช็คว่ามี ad iframe หรือ ad class ข้างใน
                    var hasAdContent = fixedEls[p].querySelector('iframe, ins.adsbygoogle, [id^="div-gpt-ad"], [data-ad-slot]');
                    var hasAdClass = isAdElement(fixedEls[p]);
                    if (hasAdContent || hasAdClass) {
                        if (removeAd(fixedEls[p], 'sticky bottom ad bar')) removed++;
                    }
                }

                // Large floating overlays (z-index สูง + ครอบคลุม > 30%)
                if (zIdx >= 100) {
                    var vpArea = window.innerWidth * window.innerHeight;
                    var elArea = fRect.width * fRect.height;
                    if (vpArea > 0 && (elArea / vpArea) > 0.3) {
                        var hasAds = fixedEls[p].querySelector('iframe, ins.adsbygoogle, [id^="div-gpt-ad"], [class^="trc_"]');
                        if (hasAds) {
                            if (removeAd(fixedEls[p], 'floating ad overlay')) removed++;
                        }
                    }
                }
            } catch (e) { }
        }

        return removed;
    }

    // ════════ Layer 4: MutationObserver ════════
    // จับโฆษณาที่ inject เข้ามาทีหลัง
    // ──────────────────────────────────────────

    function startAdBlockObserver() {
        if (!document.body) {
            setTimeout(startAdBlockObserver, 500);
            return;
        }

        try {
            var observer = new MutationObserver(function (mutations) {
                for (var i = 0; i < mutations.length; i++) {
                    var added = mutations[i].addedNodes;
                    for (var j = 0; j < added.length; j++) {
                        var node = added[j];
                        if (node.nodeType !== Node.ELEMENT_NODE) continue;
                        if (isProcessed(node)) continue;

                        // เช็ค node เอง
                        if (node.tagName === 'IFRAME' && isAdIframe(node)) {
                            climbAndRemoveAdParent(node, 'dynamic ad iframe');
                            continue;
                        }
                        if (isAdElement(node)) {
                            removeAd(node, 'dynamic ad element');
                            continue;
                        }
                        if (node.tagName === 'INS' && node.className &&
                            node.className.toString().indexOf('adsbygoogle') !== -1) {
                            climbAndRemoveAdParent(node, 'dynamic Google AdSense');
                            continue;
                        }

                        // เช็ค Taboola trc_ dynamically added
                        try {
                            var cls = (node.className || '').toString();
                            if (cls.indexOf('trc_') !== -1) {
                                removeAd(node, 'dynamic Taboola widget');
                                continue;
                            }
                        } catch (e) { }

                        // เช็ค children ของ node ใหม่
                        try {
                            var adIframes = node.querySelectorAll('iframe');
                            for (var k = 0; k < adIframes.length; k++) {
                                if (!isProcessed(adIframes[k]) && isAdIframe(adIframes[k])) {
                                    climbAndRemoveAdParent(adIframes[k], 'dynamic nested ad iframe');
                                }
                            }
                            var adContainers = node.querySelectorAll(
                                'ins.adsbygoogle, [id^="google_ads_"], [id^="div-gpt-ad"], ' +
                                '[id^="taboola-"], .OUTBRAIN, [class^="trc_"], [data-google-query-id]'
                            );
                            for (var m = 0; m < adContainers.length; m++) {
                                if (!isProcessed(adContainers[m])) {
                                    climbAndRemoveAdParent(adContainers[m], 'dynamic nested ad');
                                }
                            }
                        } catch (e) { }
                    }
                }
            });

            observer.observe(document.body, {
                childList: true,
                subtree: true,
            });
            log('\uD83D\uDC41\uFE0F Ad MutationObserver active');
        } catch (e) {
            log('\u26A0\uFE0F Ad Observer error: ' + e.message);
        }
    }

    // ════════ Init ════════

    function init() {
        log('\uD83D\uDEE1\uFE0F AEGIS Ad Blocker v2.0');

        // Layer 1: CSS ซ่อนก่อน
        injectAdBlockCSS();

        // Layer 2+3: DOM scan + parent climb
        log('\uD83D\uDD0D Scanning for ads...');
        var removed = scanForAds();

        if (removed > 0) {
            log('\u2705 Removed ' + removed + ' ad(s) (initial scan)');
        } else {
            log('\u2705 No ads found (initial scan)');
        }

        // Layer 4: Observer
        startAdBlockObserver();

        // Re-scan หลัง 1.5 วินาที (โฆษณาจาก Google DFP มักโหลดช้า)
        setTimeout(function () {
            var r1 = scanForAds();
            if (r1 > 0) log('\u2705 Scan @1.5s: removed ' + r1 + ' ad(s). Total: ' + removedCount);
        }, 1500);

        // Re-scan หลัง 3 วินาที (Taboola/Outbrain โหลดช้ามาก)
        setTimeout(function () {
            var r2 = scanForAds();
            if (r2 > 0) log('\u2705 Scan @3s: removed ' + r2 + ' ad(s). Total: ' + removedCount);
        }, 3000);

        // Re-scan หลัง 6 วินาที (catch-all for very late ads)
        setTimeout(function () {
            var r3 = scanForAds();
            if (r3 > 0) log('\u2705 Scan @6s: removed ' + r3 + ' ad(s). Total: ' + removedCount);
        }, 6000);

        // Final sweep หลัง 10 วินาที
        setTimeout(function () {
            var r4 = scanForAds();
            if (r4 > 0) log('\u2705 Final sweep: removed ' + r4 + ' ad(s). Total: ' + removedCount);
            log('\uD83C\uDFC1 Ad blocking complete. Total removed: ' + removedCount);
        }, 10000);
    }

    // ════════ Start ════════
    if (document.readyState === 'loading') {
        // inject CSS ก่อน DOM พร้อม
        injectAdBlockCSS();
        document.addEventListener('DOMContentLoaded', function () {
            init();
        });
    } else {
        init();
    }

})();
