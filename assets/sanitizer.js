// ===================================================================
// AEGIS DOM Sanitizer v4.0 — Gambling Detection + Popup/Overlay Blocker
// ===================================================================
// หน้าที่: สแกนหน้าเว็บที่โหลดใน WebView เพื่อลบ banner พนัน,
//         popup/modal overlay, carousel/slider ads, และ sticky ads
//         โดยไม่ลบเนื้อหาปกติ (false positive prevention)
//
// อ้างอิงจากการวิเคราะห์ HTML จริงของ anime-seven.com:
//   <a href="https://ibit.ly/ufazeed">
//     <img src="https://www.anime-seven.com/pic/webp/ufazeed.webp"
//          alt="Advertisement" width="728" height="200" />
//   </a>
//
// วิธีตรวจจับ 4 ชั้น:
// 1. เช็ค URL shortener (ibit.ly ฯลฯ) ว่า path มีชื่อ brand พนันหรือไม่
// 2. เช็ค image filename (src) ว่าเป็นชื่อ brand พนันหรือไม่
// 3. เช็ค alt="Advertisement" บน image ขนาด banner (กว้าง>300, ratio>1.5:1)
// 4. เช็ค href/src URL เต็มว่ามี pattern พนันหรือไม่
//
// Flow การทำงาน:
// init() → scanDOM() → scan <a>, <img>, <iframe>, <div>
//   → startObserver() → จับ DOM mutation → scanElement()
//   → setTimeout 3วิ → re-scan สำหรับ content ที่โหลดช้า
//
// สื่อสารกับ Flutter:
//   AegisLogger.postMessage('...') → ส่ง log ไป Dashboard
// ===================================================================

(function () {
    'use strict';

    // ═══════════════════════════════════════════════════════════════
    // GAMBLING_BRANDS — รายชื่อ brand พนัน
    // ═══════════════════════════════════════════════════════════════
    // ใช้ keywords จาก gambling_keywords.json (inject ผ่าน Flutter)
    // ถ้าไม่มี → fallback ไปใช้ hardcoded list
    // ═══════════════════════════════════════════════════════════════
    var _injected = window._aegisKeywords || {};
    var GAMBLING_BRANDS = (_injected.brands && _injected.brands.length > 0)
        ? _injected.brands
        : [
            'ufabet', 'ufa365', 'ufa888', 'ufa168', 'ufa191',
            'ufazeed', 'ufabomb', 'ufac4', 'ufafat',
            'pgslot', 'pgsoft',
            'betflik', 'betflix', 'betflip',
            'joker123', 'jokergaming',
            'sexybaccarat', 'sexygame',
            'sagaming', 'sagame',
            'slotxo', 'slotgame', 'slotgame66', 'slotgame666', 'slotgame6666',
            'ambbet', 'superslot',
            'panama888', 'panama999',
            'lockdown168', 'lockdown888',
            'brazil99', 'brazil999',
            'sbobet', 'lsm99', 'gclub',
            'live22', 'mega888', 'kiss918',
            'ole777', 'fun88', 'w88',
            'dafabet', 'happyluke', 'empire777',
            'lucabet', 'foxz168', 'databet',
            'ruay', 'mafia88', 'biobet',
            'ssgame66', 'ssgame666',
            'kingdom66', 'kingdom666',
            'lotto77', 'lotto88',
            'sexygame1688', 'sagame1688',
        ];

    // ═══════════════════════════════════════════════════════════════
    // SHORTENER_DOMAINS — รายชื่อ URL shortener ที่ต้องตรวจ
    // ═══════════════════════════════════════════════════════════════
    // เอาไว้: เว็บพนันมักซ่อนลิงก์ผ่าน shortener เช่น ibit.ly/ufazeed
    //         ต้องดึง path ออกมาเช็คว่าเป็น brand พนันหรือไม่
    // ═══════════════════════════════════════════════════════════════
    var SHORTENER_DOMAINS = [
        'ibit.ly', 'bit.ly', 'tinyurl.com', 'goo.gl',
        'is.gd', 'v.gd', 'cutt.ly', 'rebrand.ly',
        'shorturl.at', 'tiny.cc',
    ];

    // สร้าง hash map จาก GAMBLING_BRANDS สำหรับ O(1) lookup
    var BRAND_SET = {};
    for (var i = 0; i < GAMBLING_BRANDS.length; i++) {
        BRAND_SET[GAMBLING_BRANDS[i].toLowerCase()] = true;
    }

    // ═══════════════════════════════════════════════════════════════
    // THAI_KEYWORDS — คำภาษาไทยที่เกี่ยวกับการพนัน
    // ═══════════════════════════════════════════════════════════════
    // ใช้ keywords จาก gambling_keywords.json (inject ผ่าน Flutter)
    // ถ้าไม่มี → fallback ไปใช้ hardcoded list (Unicode escape)
    // ═══════════════════════════════════════════════════════════════
    var THAI_KEYWORDS = (_injected.thaiKeywords && _injected.thaiKeywords.length > 0)
        ? _injected.thaiKeywords
        : [
            '\u0E40\u0E04\u0E23\u0E14\u0E34\u0E15\u0E1F\u0E23\u0E35',       // เครดิตฟรี
            '\u0E1D\u0E32\u0E01\u0E16\u0E2D\u0E19',           // ฝากถอน
            '\u0E2A\u0E25\u0E47\u0E2D\u0E15',               // สล็อต
            '\u0E1A\u0E32\u0E04\u0E32\u0E23\u0E48\u0E32',           // บาคาร่า
            '\u0E1E\u0E19\u0E31\u0E19\u0E2D\u0E2D\u0E19\u0E44\u0E25\u0E19\u0E4C',     // พนันออนไลน์
            '\u0E41\u0E17\u0E07\u0E1A\u0E2D\u0E25',           // แทงบอล
            '\u0E1D\u0E32\u0E01\u0E02\u0E31\u0E49\u0E19\u0E15\u0E48\u0E33',       // ฝากขั้นต่ำ
            '\u0E2B\u0E27\u0E22\u0E2D\u0E2D\u0E19\u0E44\u0E25\u0E19\u0E4C',     // หวยออนไลน์
            '\u0E1D\u0E32\u0E01\u0E16\u0E2D\u0E19\u0E2D\u0E2D\u0E42\u0E15\u0E49',   // ฝากถอนออโต้
            '\u0E04\u0E37\u0E19\u0E22\u0E2D\u0E14\u0E40\u0E2A\u0E35\u0E22',       // คืนยอดเสีย
            '\u0E2A\u0E21\u0E31\u0E04\u0E23\u0E04\u0E25\u0E34\u0E01',           // สมัครคลิก
            '\u0E2A\u0E21\u0E31\u0E04\u0E23\u0E40\u0E25\u0E22',           // สมัครเลย
        ];

    // ═══════════════════════════════════════════════════════════════
    // GAMBLING_REGEX — Regex patterns สำหรับจับ URL/text แบบกว้าง
    // ═══════════════════════════════════════════════════════════════
    // เอาไว้: จับ pattern ที่ exact match จับไม่ได้
    //         เช่น ufa + ตัวเลขอะไรก็ได้, slot-123, bet-456
    // ═══════════════════════════════════════════════════════════════
    var GAMBLING_REGEX = [
        /\bufa[a-z0-9]+/i,
        /slot\s*game/i,
        /pgslot/i,
        /betfli[kx]/i,
        /sagam[ei]/i,
        /sexygame/i,
        /panama\d+/i,
        /lockdown\d+/i,
        /brazil\d+/i,
        /kingdom\d+/i,
        /ssgame\d+/i,
        /lotto\d+/i,
        /sbobet/i,
        /gclub/i,
        /lsm\d+/i,
        /ambbet/i,
        /superslot/i,
        /slotxo/i,
        /live22/i,
        /mega\s*888/i,
        /ole\s*777/i,
        /fun\s*88/i,
        /mafia\s*88/i,
        /dafabet/i,
        /lucabet/i,
        /databet/i,
        /foxz\d+/i,
        // Pattern ทั่วไป: คำพนัน + ตัวเลข เช่น slot-99, bet888, game777
        /(?:slot|bet|game|play|win|vip|pro|club)[\-_]?\d{2,}/i,
        /\d{2,}(?:slot|bet|game|casino|play)/i,
    ];

    var removedCount = 0; // นับจำนวน element ที่ถูกลบทั้งหมด

    // ════════ Helper Functions ════════

    /**
     * log — ส่ง log message ไป Flutter
     * Logic: ใช้ AegisLogger.postMessage (JavaScriptChannel) + console.log
     * เอาไว้: สื่อสารจาก JS → Flutter Dashboard
     */
    function log(msg) {
        if (window.AegisLogger) window.AegisLogger.postMessage(msg);
        console.log('[AEGIS] ' + msg);
    }

    /**
     * extractPathName — ดึงชื่อไฟล์/path สุดท้ายจาก URL
     * Logic:
     *   1. แยก URL ด้วย '/' → เอาส่วนสุดท้าย
     *   2. ตัด extension (.webp, .jpg) + query string (?x=1) + hash (#section)
     *   3. แปลงเป็น lowercase
     * ตัวอย่าง:
     *   "https://site.com/pic/ufazeed.webp" → "ufazeed"
     *   "https://ibit.ly/ufazeed" → "ufazeed"
     * เอาไว้: ดึงชื่อ brand จาก URL เพื่อเช็คกับ BRAND_SET
     */
    function extractPathName(url) {
        if (!url) return '';
        try {
            var parts = url.split('/');
            var last = parts[parts.length - 1] || parts[parts.length - 2] || '';
            // ตัด extension, query string, hash
            last = last.split('.')[0].split('?')[0].split('#')[0];
            return last.toLowerCase();
        } catch (e) {
            return '';
        }
    }

    /**
     * isShortenerGamblingLink — เช็คว่า URL ผ่าน shortener + มีชื่อ brand พนัน
     * Logic:
     *   1. เช็คว่า URL มี shortener domain (ibit.ly, bit.ly ฯลฯ)
     *   2. ถ้าใช่ → ดึง path ออกมาเช็คกับ BRAND_SET (exact match)
     *   3. ถ้าไม่ match exact → ลอง regex patterns
     * ตัวอย่าง:
     *   "https://ibit.ly/ufazeed" → shortener + path "ufazeed" → detected!
     * เอาไว้: จับ banner ที่ซ่อนลิงก์ผ่าน URL shortener
     */
    function isShortenerGamblingLink(url) {
        if (!url) return false;
        var lower = url.toLowerCase();
        for (var i = 0; i < SHORTENER_DOMAINS.length; i++) {
            if (lower.indexOf(SHORTENER_DOMAINS[i]) !== -1) {
                // เป็น shortener URL → เช็ค path ว่ามี brand พนันหรือไม่
                var pathName = extractPathName(url);
                if (pathName && BRAND_SET[pathName]) return true;
                // ลอง regex patterns
                for (var j = 0; j < GAMBLING_REGEX.length; j++) {
                    if (GAMBLING_REGEX[j].test(pathName)) return true;
                }
            }
        }
        return false;
    }

    /**
     * isGamblingUrl — เช็คว่า URL ตรงกับ pattern พนันหรือไม่
     * Logic:
     *   1. เช็ค shortener links ก่อน (จับ ibit.ly/ufazeed)
     *   2. จากนั้นเช็ค URL เต็มกับ regex patterns
     * เอาไว้: ใช้กับ href ของ <a> tag และ src ของ <iframe>
     */
    function isGamblingUrl(url) {
        if (!url) return false;
        if (isShortenerGamblingLink(url)) return true;
        for (var i = 0; i < GAMBLING_REGEX.length; i++) {
            if (GAMBLING_REGEX[i].test(url)) return true;
        }
        return false;
    }

    /**
     * isGamblingImageSrc — เช็คว่า image filename เป็นชื่อ brand พนันหรือไม่
     * Logic:
     *   1. ดึง filename จาก src ด้วย extractPathName
     *   2. เช็ค exact match กับ BRAND_SET
     *   3. เช็ค regex match
     * ตัวอย่าง:
     *   "https://site.com/pic/ufazeed.webp" → filename "ufazeed" → detected!
     * เอาไว้: จับ banner ที่เป็น image โดยดูชื่อไฟล์
     */
    function isGamblingImageSrc(src) {
        if (!src) return false;
        var filename = extractPathName(src);
        if (!filename) return false;
        if (BRAND_SET[filename]) return true;
        for (var i = 0; i < GAMBLING_REGEX.length; i++) {
            if (GAMBLING_REGEX[i].test(filename)) return true;
        }
        return false;
    }

    /**
     * hasThaiGamblingKeywords — เช็คว่าข้อความมีคำพนันภาษาไทยหรือไม่
     * Logic: เช็ค substring match กับ THAI_KEYWORDS ทุกตัว
     * เอาไว้: ตรวจ text content/alt text ว่ามีคำเช่น "เครดิตฟรี" หรือไม่
     */
    function hasThaiGamblingKeywords(text) {
        if (!text) return false;
        for (var i = 0; i < THAI_KEYWORDS.length; i++) {
            if (text.indexOf(THAI_KEYWORDS[i]) !== -1) return true;
        }
        return false;
    }

    /**
     * getGamblingScore — คำนวณ "คะแนนพนัน" ของข้อความ
     * Logic:
     *   - brand name ที่พบ → +3 คะแนน/ตัว
     *   - Thai keyword ที่พบ → +3 คะแนน
     *   - score >= 3 → น่าสงสัยว่าเป็นเนื้อหาพนัน
     * เอาไว้: ตัดสินใจลบ element ที่มี score สูง (threshold = 3)
     *         ใช้ scoring เพื่อลด false positive
     */
    function getGamblingScore(text) {
        if (!text) return 0;
        var score = 0;
        var lower = text.toLowerCase();
        for (var i = 0; i < GAMBLING_BRANDS.length; i++) {
            if (lower.indexOf(GAMBLING_BRANDS[i]) !== -1) score += 3;
        }
        if (hasThaiGamblingKeywords(text)) score += 3;
        return score;
    }

    /**
     * markScanned — ทำเครื่องหมายว่า element ถูกสแกนแล้ว
     * Logic: ใส่ data-aegis="1" attribute ให้ element + ลูกทุกตัว
     * เอาไว้: ป้องกันสแกนซ้ำ (performance optimization)
     */
    function markScanned(el) {
        try {
            if (el && el.setAttribute) el.setAttribute('data-aegis', '1');
            var ch = el.querySelectorAll ? el.querySelectorAll('*') : [];
            for (var i = 0; i < ch.length; i++) {
                if (ch[i] && ch[i].setAttribute) ch[i].setAttribute('data-aegis', '1');
            }
        } catch (e) { }
    }

    /**
     * isScanned — เช็คว่า element ถูกสแกนแล้วหรือยัง
     * เอาไว้: ข้าม element ที่สแกนแล้ว → ไม่ลบซ้ำ
     */
    function isScanned(el) {
        try {
            return el && el.getAttribute && el.getAttribute('data-aegis') === '1';
        } catch (e) { return false; }
    }

    /**
     * removeEl — ลบ element จาก DOM + log ผลลัพธ์
     * Logic:
     *   1. ดึง tag name, href, id สำหรับ log
     *   2. markScanned → ป้องกันสแกนซ้ำ
     *   3. el.remove() → ลบจาก DOM จริง
     *   4. removedCount++ + log ข้อความ
     * เอาไว้: function กลางสำหรับลบ element ทุกชนิด
     */
    function removeEl(el, reason) {
        var tag = el.tagName ? el.tagName.toLowerCase() : '?';
        var href = '';
        try { href = el.getAttribute('href') || ''; } catch (e) { }
        var id = '';
        try { id = el.id ? '#' + el.id : ''; } catch (e) { }
        var identifier = id || (href ? href.substring(0, 60) : tag);

        markScanned(el);
        el.remove();
        removedCount++;
        log('\uD83E\uDDF9 Removed: <' + tag + '> ' + identifier + ' \u2014 ' + reason);
        return true;
    }

    // ════════ Core Scanning Logic ════════

    /**
     * scanAnchor — สแกน <a> tag ว่าเป็นลิงก์พนันหรือไม่
     * Logic (ตรวจ 3 วิธี):
     *   วิธี 1: เช็ค href URL → ตรง gambling pattern?
     *   วิธี 2: เช็ค child <img> elements:
     *     - image filename เป็น brand พนัน?
     *     - alt="Advertisement" + ขนาด banner (w>300, ratio>1.5:1)?
     *     - alt text มี gambling score >= 3?
     *   วิธี 3: เช็ค link text → gambling score >= 3? (text สั้น <120 ตัวอักษร)
     * เอาไว้: <a> เป็น element หลักที่โฆษณาพนันใช้ (link + image)
     */
    function scanAnchor(el) {
        var href = el.getAttribute('href') || '';

        // วิธี 1: เช็ค URL ของลิงก์
        if (isGamblingUrl(href)) {
            return removeEl(el, 'gambling link: ' + href.substring(0, 60));
        }

        // วิธี 2: เช็ค images ภายใน link
        var imgs = el.querySelectorAll('img');
        for (var i = 0; i < imgs.length; i++) {
            var src = imgs[i].getAttribute('src') || '';
            var alt = imgs[i].getAttribute('alt') || '';

            // เช็คชื่อไฟล์ภาพ
            if (isGamblingImageSrc(src)) {
                return removeEl(el, 'gambling image: ' + extractPathName(src));
            }

            // เช็ค alt="Advertisement" + ขนาด banner
            if (alt.toLowerCase() === 'advertisement') {
                var w = parseInt(imgs[i].getAttribute('width') || '0', 10);
                var h = parseInt(imgs[i].getAttribute('height') || '0', 10);
                // Banner-sized: กว้าง > 300px + aspect ratio > 1.5:1
                if (w > 300 && h > 0 && (w / h) > 1.5) {
                    return removeEl(el, 'advertisement banner (' + w + 'x' + h + ')');
                }
                // แม้ไม่มี dimensions แต่ alt=Advertisement ใน link น่าสงสัย
                if (href && href.length > 5) {
                    return removeEl(el, 'advertisement image in link');
                }
            }

            // เช็ค alt text ว่ามี gambling keywords
            if (getGamblingScore(alt) >= 3) {
                return removeEl(el, 'gambling alt text');
            }
        }

        // วิธี 3: เช็คข้อความใน link (เฉพาะ text สั้น → ไม่ลบบทความยาว)
        var text = (el.textContent || '').trim();
        if (text.length > 0 && text.length < 120 && getGamblingScore(text) >= 3) {
            return removeEl(el, 'gambling text in link');
        }

        return false;
    }

    /**
     * scanImage — สแกน <img> tag เดี่ยวๆ
     * Logic:
     *   1. เช็ค src → ชื่อไฟล์เป็น brand พนัน?
     *   2. เช็ค alt text → gambling score >= 3?
     * เอาไว้: จับ image เดี่ยวที่ไม่อยู่ใน <a> tag
     */
    function scanImage(el) {
        var src = el.getAttribute('src') || '';
        var alt = el.getAttribute('alt') || '';

        if (isGamblingImageSrc(src)) {
            return removeEl(el, 'gambling image: ' + extractPathName(src));
        }
        if (getGamblingScore(alt) >= 3) {
            return removeEl(el, 'gambling alt: ' + alt.substring(0, 40));
        }
        return false;
    }

    /**
     * scanIframe — สแกน <iframe> tag
     * Logic: เช็ค src URL → ตรง gambling pattern?
     * เอาไว้: จับ iframe ที่โหลดเว็บพนัน
     */
    function scanIframe(el) {
        var src = el.getAttribute('src') || '';
        if (isGamblingUrl(src)) {
            return removeEl(el, 'gambling iframe');
        }
        return false;
    }

    /**
     * scanContainer — สแกน container elements (div, section, aside, p)
     * Logic:
     *   1. ข้าม container ใหญ่ (text>300 + children>15) → เป็นเนื้อหาหลัก
     *   2. นับ gambling links ภายใน container (รวมทั้ง link images)
     *   3. ถ้า >= 2 gambling links → ลบทั้ง container (ad block)
     *   4. เช็ค Thai keywords ใน container เล็ก + มี image + gambling link
     * เอาไว้: จับ "กลุ่มโฆษณา" ที่รวมหลายลิงก์พนันไว้ด้วยกัน
     *         หลีกเลี่ยง container ใหญ่ → ลด false positive
     */
    function scanContainer(el) {
        var text = (el.textContent || '').trim();
        var childCount = 0;
        try { childCount = el.querySelectorAll('*').length; } catch (e) { }

        // ข้าม container ใหญ่ (เนื้อหาหลักของหน้าเว็บ)
        if (text.length > 300 && childCount > 15) return false;

        // นับ gambling links ภายใน container
        var links = el.querySelectorAll('a[href]');
        var gamblingLinkCount = 0;
        for (var i = 0; i < links.length; i++) {
            var href = links[i].getAttribute('href') || '';
            if (isGamblingUrl(href)) gamblingLinkCount++;
            // เช็ค images ภายใน link ด้วย
            var linkImgs = links[i].querySelectorAll('img');
            for (var j = 0; j < linkImgs.length; j++) {
                if (isGamblingImageSrc(linkImgs[j].getAttribute('src') || '')) {
                    gamblingLinkCount++;
                }
            }
        }

        // >= 2 gambling links → ad block → ลบทั้ง container
        if (gamblingLinkCount >= 2) {
            return removeEl(el, 'ad block with ' + gamblingLinkCount + ' gambling links');
        }

        // เช็ค Thai keywords ใน container เล็ก + มีรูป + gambling link
        if (text.length < 200 && hasThaiGamblingKeywords(text)) {
            var hasImg = el.querySelectorAll('img').length > 0;
            if (hasImg && gamblingLinkCount >= 1) {
                return removeEl(el, 'gambling container with Thai keywords');
            }
        }

        return false;
    }

    // ════════ Popup/Overlay Detection ════════

    // Common CSS classes/IDs for popups, modals, and overlays
    var POPUP_PATTERNS = [
        'popup', 'modal', 'overlay', 'lightbox', 'dialog',
        'interstitial', 'floating', 'splash', 'banner-float',
        'ads-popup', 'ad-overlay', 'ad-modal', 'ad-float',
        'cookie-banner', 'notification-bar', 'promo-popup',
    ];

    // Common CSS classes for carousels/sliders
    var CAROUSEL_PATTERNS = [
        'swiper', 'slick', 'carousel', 'slider', 'owl-carousel',
        'owl-stage', 'glide', 'splide', 'flickity', 'bx-wrapper',
        'bxslider', 'nivo', 'slide-banner', 'banner-slide',
        'hero-slider', 'hero-banner', 'banner-carousel',
    ];

    /**
     * hasMatchingClassOrId — เช็คว่า element มี class/id ตรงกับ patterns
     */
    function hasMatchingClassOrId(el, patterns) {
        var className = '';
        var id = '';
        try {
            className = (el.className || '').toString().toLowerCase();
            id = (el.id || '').toLowerCase();
        } catch (e) { return false; }

        for (var i = 0; i < patterns.length; i++) {
            if (className.indexOf(patterns[i]) !== -1) return true;
            if (id.indexOf(patterns[i]) !== -1) return true;
        }
        return false;
    }

    /**
     * scanPopupOverlay — ตรวจจับ popup/modal/overlay ที่ซ้อนทับหน้าเว็บ
     * Logic:
     *   1. เช็ค position: fixed/absolute
     *   2. เช็ค z-index > 100 (overlay มักมี z-index สูง)
     *   3. เช็คว่าครอบคลุมพื้นที่ > 30% ของ viewport
     *   4. ถ้ามี gambling content ข้างใน → ลบทันที
     *   5. ถ้าเป็น popup ขนาดใหญ่ที่ block content → ลบ
     */
    function scanPopupOverlay(el) {
        if (!el || !el.tagName) return false;
        if (isScanned(el)) return false;
        if (el === document.body || el === document.documentElement) return false;

        try {
            var style = window.getComputedStyle(el);
            var position = style.getPropertyValue('position');

            // ตรวจเฉพาะ fixed/absolute elements
            if (position !== 'fixed' && position !== 'absolute') return false;

            var zIndex = parseInt(style.getPropertyValue('z-index') || '0', 10);
            if (isNaN(zIndex)) zIndex = 0;

            // ต้อง z-index สูงพอ (overlay)
            if (zIndex < 50) return false;

            var rect = el.getBoundingClientRect();
            var vpWidth = window.innerWidth;
            var vpHeight = window.innerHeight;
            var elArea = rect.width * rect.height;
            var vpArea = vpWidth * vpHeight;
            var coverage = vpArea > 0 ? (elArea / vpArea) : 0;

            // เช็คเนื้อหาภายใน
            var text = (el.textContent || '').trim();
            var hasGamblingContent = getGamblingScore(text) >= 3 || hasThaiGamblingKeywords(text);
            var hasGamblingLinks = false;
            var links = el.querySelectorAll('a[href]');
            for (var i = 0; i < links.length; i++) {
                if (isGamblingUrl(links[i].getAttribute('href') || '')) {
                    hasGamblingLinks = true;
                    break;
                }
            }

            // Gambling popup → ลบทันที (ไม่ว่าจะขนาดไหน)
            if (hasGamblingContent || hasGamblingLinks) {
                return removeEl(el, 'gambling popup/overlay (z:' + zIndex + ')');
            }

            // ถ้าเป็น class ที่คือ popup + มี gambling content → ลบ
            if (hasMatchingClassOrId(el, POPUP_PATTERNS) && (hasGamblingContent || hasGamblingLinks)) {
                return removeEl(el, 'gambling modal/popup');
            }

            // Full-screen overlay backdrop (ครอบคลุม > 70% + semi-transparent)
            if (coverage > 0.7 && zIndex >= 100) {
                var bg = style.getPropertyValue('background-color') || '';
                var opacity = parseFloat(style.getPropertyValue('opacity') || '1');
                // ถ้าเป็น backdrop (พื้นหลังมืด/โปร่งใส) ที่ block content → ลบ
                if (opacity < 0.9 || bg.indexOf('rgba') !== -1) {
                    return removeEl(el, 'fullscreen overlay backdrop (z:' + zIndex + ')');
                }
            }
        } catch (e) { }

        return false;
    }

    /**
     * scanCarouselSlider — ตรวจจับ carousel/slider ที่มี gambling content
     * Logic:
     *   1. เช็ค class/id ว่าตรงกับ carousel patterns
     *   2. ถ้าตรง → เช็คเนื้อหาภายในว่ามี gambling content
     *   3. ถ้ามี → ลบ carousel ทั้งอัน
     */
    function scanCarouselSlider(el) {
        if (!el || !el.tagName) return false;
        if (isScanned(el)) return false;
        if (el === document.body || el === document.documentElement) return false;

        if (!hasMatchingClassOrId(el, CAROUSEL_PATTERNS)) return false;

        // เป็น carousel → เช็คเนื้อหา
        var text = (el.textContent || '').trim();
        var hasGambling = getGamblingScore(text) >= 3 || hasThaiGamblingKeywords(text);

        if (!hasGambling) {
            // เช็ค images ภายใน carousel
            var imgs = el.querySelectorAll('img');
            for (var i = 0; i < imgs.length; i++) {
                var src = imgs[i].getAttribute('src') || '';
                var alt = imgs[i].getAttribute('alt') || '';
                if (isGamblingImageSrc(src) || getGamblingScore(alt) >= 3) {
                    hasGambling = true;
                    break;
                }
            }
        }

        if (!hasGambling) {
            // เช็ค links ภายใน carousel
            var links = el.querySelectorAll('a[href]');
            for (var j = 0; j < links.length; j++) {
                if (isGamblingUrl(links[j].getAttribute('href') || '')) {
                    hasGambling = true;
                    break;
                }
            }
        }

        if (hasGambling) {
            return removeEl(el, 'gambling carousel/slider');
        }
        return false;
    }

    /**
     * scanStickyAd — ตรวจจับ sticky ads (แถบโฆษณาที่ติดอยู่บน/ล่างหน้าจอ)
     * Logic:
     *   1. เช็ค position: fixed/sticky
     *   2. เช็คว่าอยู่บนหรือล่างจอ (top ≈ 0 หรือ bottom ≈ 0)
     *   3. เช็คว่ากว้างเต็มจอ (width > 80% viewport)
     *   4. ถ้ามี gambling content → ลบ
     */
    function scanStickyAd(el) {
        if (!el || !el.tagName) return false;
        if (isScanned(el)) return false;
        if (el === document.body || el === document.documentElement) return false;

        try {
            var style = window.getComputedStyle(el);
            var position = style.getPropertyValue('position');
            if (position !== 'fixed' && position !== 'sticky') return false;

            var rect = el.getBoundingClientRect();
            var isWide = rect.width > window.innerWidth * 0.8;
            var isShort = rect.height < 200;
            var isTopOrBottom = rect.top < 10 || rect.bottom > window.innerHeight - 10;

            if (isWide && isShort && isTopOrBottom) {
                var text = (el.textContent || '').trim();
                if (getGamblingScore(text) >= 3 || hasThaiGamblingKeywords(text)) {
                    return removeEl(el, 'sticky gambling ad bar');
                }
                // เช็ค links
                var links = el.querySelectorAll('a[href]');
                for (var i = 0; i < links.length; i++) {
                    if (isGamblingUrl(links[i].getAttribute('href') || '')) {
                        return removeEl(el, 'sticky ad bar with gambling link');
                    }
                }
            }
        } catch (e) { }

        return false;
    }

    // ════════ Element Dispatcher ════════

    /**
     * scanElement — dispatcher: ส่ง element ไป scan function ตามประเภท
     * Logic:
     *   - A (ลิงก์) → scanAnchor
     *   - IMG (รูป) → scanImage
     *   - IFRAME → scanIframe
     *   - DIV/SECTION/ASIDE/P/FIGURE/ARTICLE → scanContainer
     *   - ทุก element → popup/carousel/sticky check
     *   - ข้าม: body, documentElement, หรือ element ที่สแกนแล้ว
     */
    function scanElement(el) {
        if (!el || !el.tagName) return false;
        if (isScanned(el)) return false;
        if (el === document.body || el === document.documentElement) return false;

        // เช็ค popup/overlay ก่อน (ลำดับความสำคัญสูงสุด)
        if (scanPopupOverlay(el)) return true;
        if (scanCarouselSlider(el)) return true;
        if (scanStickyAd(el)) return true;

        var tag = el.tagName.toUpperCase();

        if (tag === 'A') return scanAnchor(el);
        if (tag === 'IMG') return scanImage(el);
        if (tag === 'IFRAME') return scanIframe(el);
        if (tag === 'DIV' || tag === 'SECTION' || tag === 'ASIDE' ||
            tag === 'P' || tag === 'FIGURE' || tag === 'ARTICLE') {
            return scanContainer(el);
        }
        return false;
    }

    // ════════ Full DOM Scan ════════

    /**
     * scanDOM — สแกน DOM ทั้งหน้า 4 รอบ
     * Logic (scan ทีละประเภท → เรียงจากเฉพาะ → ทั่วไป):
     *   Phase 1: <a> tags ก่อน (แม่นยำที่สุด)
     *   Phase 2: <img> ที่เหลือ (ไม่อยู่ใน <a>)
     *   Phase 3: <iframe>
     *   Phase 4: containers (div, p, section, aside)
     * เอาไว้: scan แรกเมื่อหน้าโหลดเสร็จ + re-scan หลัง 3 วินาที
     */
    function scanDOM() {
        var removed = 0;

        // Phase 1: สแกน <a> ก่อน (แม่นยำที่สุด เพราะ pattern หลักคือ <a> + <img>)
        var links = document.querySelectorAll('a');
        for (var i = 0; i < links.length; i++) {
            if (!isScanned(links[i]) && scanElement(links[i])) removed++;
        }

        // Phase 2: image ที่เหลือ (ไม่ถูกลบไปกับ <a> tag)
        var imgs = document.querySelectorAll('img');
        for (var j = 0; j < imgs.length; j++) {
            if (!isScanned(imgs[j]) && scanElement(imgs[j])) removed++;
        }

        // Phase 3: iframes
        var iframes = document.querySelectorAll('iframe');
        for (var k = 0; k < iframes.length; k++) {
            if (!isScanned(iframes[k]) && scanElement(iframes[k])) removed++;
        }

        // Phase 4: containers (เช่น <p class="center_lnwphp"> ที่ห่อหลาย ads)
        var containers = document.querySelectorAll('div, p, section, aside');
        for (var m = 0; m < containers.length; m++) {
            if (!isScanned(containers[m]) && scanElement(containers[m])) removed++;
        }

        // Phase 5: Popup/Overlay scan — หา elements ที่ลอยทับหน้าจอ
        var allDivs = document.querySelectorAll('div, section, aside, nav, header, footer, span');
        for (var n = 0; n < allDivs.length; n++) {
            if (!isScanned(allDivs[n]) && scanPopupOverlay(allDivs[n])) removed++;
        }

        // Phase 6: Carousel/Slider scan — หา slider ที่มีเนื้อหาพนัน
        var carouselSelectors = '[class*="swiper"], [class*="slick"], [class*="carousel"],'
            + ' [class*="slider"], [class*="owl-"], [class*="glide"], [class*="splide"],'
            + ' [class*="banner-slide"], [class*="hero-banner"]';
        try {
            var carousels = document.querySelectorAll(carouselSelectors);
            for (var p = 0; p < carousels.length; p++) {
                if (!isScanned(carousels[p]) && scanCarouselSlider(carousels[p])) removed++;
            }
        } catch (e) { }

        // Phase 7: Sticky ads — หาแถบโฆษณาที่ติดอยู่บน/ล่างจอ
        for (var q = 0; q < allDivs.length; q++) {
            if (!isScanned(allDivs[q]) && scanStickyAd(allDivs[q])) removed++;
        }

        return removed;
    }

    // ════════ MutationObserver ════════

    /**
     * startObserver — เปิด MutationObserver จับการเพิ่ม element ใหม่
     * Logic:
     *   1. รอ document.body พร้อม (ถ้าไม่พร้อม → retry ทุก 500ms)
     *   2. สร้าง MutationObserver ที่จับ childList + subtree
     *   3. เมื่อมี node ใหม่ → scanElement + scan ลูกทั้งหมด
     * เอาไว้: จับ ads ที่โหลดทีหลังหน้าเพจโหลดเสร็จ (lazy-loaded, AJAX injected)
     */
    function startObserver() {
        if (!document.body) {
            log('\u26A0\uFE0F document.body not ready, retrying in 500ms...');
            setTimeout(startObserver, 500);
            return;
        }

        try {
            var observer = new MutationObserver(function (mutations) {
                for (var i = 0; i < mutations.length; i++) {
                    var mut = mutations[i];

                    // จับ element ใหม่ที่ถูกเพิ่มเข้า DOM
                    var added = mut.addedNodes;
                    for (var j = 0; j < added.length; j++) {
                        var node = added[j];
                        if (node.nodeType !== Node.ELEMENT_NODE) continue;
                        // สแกน node ใหม่ + ลูกทั้งหมด
                        scanElement(node);
                        try {
                            var targets = node.querySelectorAll('a, img, iframe, div, p, section, span');
                            for (var k = 0; k < targets.length; k++) {
                                if (!isScanned(targets[k])) scanElement(targets[k]);
                            }
                        } catch (e) { }
                    }

                    // จับ attribute changes (เช่น element ที่ถูกเปลี่ยน style เป็น popup ทีหลัง)
                    if (mut.type === 'attributes' && mut.target && mut.target.nodeType === Node.ELEMENT_NODE) {
                        // รีเซ็ต scan flag เพราะ attribute เปลี่ยน
                        try { mut.target.removeAttribute('data-aegis'); } catch (e) { }
                        scanElement(mut.target);
                    }
                }
            });

            // สังเกต DOM ทั้งหมด: children + attributes + subtree
            observer.observe(document.body, {
                childList: true,
                subtree: true,
                attributes: true,
                attributeFilter: ['style', 'class', 'id'],
            });
            log('\uD83D\uDC41\uFE0F MutationObserver active (DOM + style changes)');
        } catch (e) {
            log('\u26A0\uFE0F MutationObserver error: ' + e.message);
        }
    }

    // ════════ Init ════════

    /**
     * init — function หลักที่เริ่มทำงานทั้งหมด
     * Logic:
     *   1. สแกน DOM ครั้งแรก (scanDOM)
     *   2. เปิด MutationObserver สำหรับ element ที่เพิ่มภายหลัง
     *   3. setTimeout 3 วินาที → re-scan สำหรับ lazy-loaded content
     *      (รีเซ็ต data-aegis flag เพื่อสแกนใหม่)
     * เอาไว้: entry point เรียกจาก DOMContentLoaded หรือทันที
     */
    function init() {
        log('\uD83D\uDEE1\uFE0F AEGIS DOM Sanitizer v4.0');
        log('\uD83D\uDD0D Scanning (banners + popups + carousels)...');

        var removed = scanDOM();

        if (removed > 0) {
            log('\u2705 Removed ' + removed + ' gambling element(s)');
        } else {
            log('\u2705 Page clean (initial scan)');
        }

        startObserver();

        // re-scan หลัง 3 วินาที สำหรับ content ที่โหลดช้า (lazy-loaded)
        setTimeout(function () {
            log('\uD83D\uDD04 Re-scanning for late-loaded content...');
            // รีเซ็ต scan flags เพื่อสแกนใหม่ทั้งหมด
            try {
                var scanned = document.querySelectorAll('[data-aegis]');
                for (var i = 0; i < scanned.length; i++) {
                    scanned[i].removeAttribute('data-aegis');
                }
            } catch (e) { }
            var reRemoved = scanDOM();
            if (reRemoved > 0) {
                log('\u2705 Late scan: removed ' + reRemoved + ' more element(s). Total: ' + removedCount);
            }
        }, 3000);
    }

    // ════════ เริ่มทำงานเมื่อ DOM พร้อม ════════
    // ถ้า loading → รอ DOMContentLoaded
    // ถ้า interactive/complete → เริ่มทันที
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

})();
