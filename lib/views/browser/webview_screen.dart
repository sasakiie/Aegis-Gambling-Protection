// ============================================================================
// AEGIS Shield — views/browser/webview_screen.dart
// ============================================================================
// WebView พร้อมระบบป้องกันเว็บพนัน + Ad Blocker
// ย้ายจาก lib/webview_screen.dart → lib/views/browser/webview_screen.dart
//
// แก้ช่องโหว่ #3: JS injection ใช้ ScriptInjectionController
// แก้ช่องโหว่ #4: Detection คืน DetectionVerdict → View ตัดสิน Navigation
// ============================================================================

import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:webview_flutter/webview_flutter.dart';

import '../../controllers/app_config.dart';
import '../../controllers/detection_controller.dart';
import '../../controllers/script_injection_controller.dart';
import '../../controllers/ad_removal_cache.dart';
import '../../controllers/ocr_service.dart';
import '../../controllers/report_service.dart';

import '../../models/classification_result.dart';
import '../../models/phase_b_models.dart';

/// WebViewScreen — เบราว์เซอร์ภายในแอป AEGIS
class WebViewScreen extends StatefulWidget {
  final void Function(String) onLog;
  final bool adBlockEnabled;

  const WebViewScreen({
    super.key,
    required this.onLog,
    this.adBlockEnabled = false,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late WebViewController _controller;
  final TextEditingController _urlController = TextEditingController();

  // ─── Controllers (MVC) ───
  final DetectionController _detectionCtrl = DetectionController();
  final ScriptInjectionController _scriptCtrl = ScriptInjectionController();
  final ReportService _reportService = ReportService();
  final Set<String> _submittedReportDomains = <String>{};
  int _pageLoadVersion = 0;

  // ─── UI State ───
  bool _isLoading = false;
  bool _isBlocked = false;
  bool _isAnalyzing = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // Blocked Page HTML
  // ═══════════════════════════════════════════════════════════════════════════
  String _blockedPageHtml(String url, {String reason = ''}) => '''
<!DOCTYPE html>
<html lang="th">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      background: linear-gradient(135deg, #0a0e21 0%, #1a0a2e 50%, #2d0a0a 100%);
      color: white; min-height: 100vh;
      display: flex; align-items: center; justify-content: center; padding: 20px;
    }
    .container { text-align: center; max-width: 400px; animation: fadeIn 0.5s ease-out; }
    @keyframes fadeIn { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }
    .shield { font-size: 80px; margin-bottom: 20px; display: block; animation: pulse 2s infinite; }
    @keyframes pulse { 0%, 100% { transform: scale(1); } 50% { transform: scale(1.1); } }
    h1 { font-size: 24px; color: #ff4444; margin-bottom: 12px; font-weight: 800; }
    .subtitle { font-size: 16px; color: #ff9999; margin-bottom: 24px; font-weight: 600; }
    .url-box { background: rgba(255,68,68,0.15); border: 1px solid rgba(255,68,68,0.3); border-radius: 12px; padding: 14px 18px; margin: 20px 0; word-break: break-all; font-size: 13px; color: #ff8888; font-family: monospace; }
    .info { font-size: 14px; color: rgba(255,255,255,0.6); line-height: 1.6; margin-top: 16px; }
    .ai-badge { display: inline-block; background: rgba(124,77,255,0.2); border: 1px solid rgba(124,77,255,0.4); border-radius: 20px; padding: 6px 16px; font-size: 12px; color: #b388ff; margin-top: 16px; font-weight: 600; }
    .reason-box { background: rgba(255,255,255,0.05); border-radius: 8px; padding: 10px 14px; margin-top: 12px; font-size: 12px; color: rgba(255,255,255,0.5); text-align: left; }
    .aegis-badge { margin-top: 30px; font-size: 12px; color: rgba(255,255,255,0.3); letter-spacing: 2px; }
  </style>
</head>
<body>
  <div class="container">
    <span class="shield">🛡️</span>
    <h1>เว็บไซต์ถูกบล็อก</h1>
    <div class="subtitle">Website Blocked by AEGIS</div>
    <div class="url-box">$url</div>
    <div class="info">
      เว็บไซต์นี้ถูกตรวจพบว่าเป็น<strong style="color:#ff6666;">เว็บพนันออนไลน์</strong><br>
      ซึ่งอาจเป็นอันตรายและผิดกฎหมาย<br><br>
      AEGIS ได้ทำการบล็อกการเข้าถึงเพื่อความปลอดภัยของคุณ
    </div>
    <div class="ai-badge">🤖 Detected by AEGIS AI</div>
    ${reason.isNotEmpty ? '<div class="reason-box">📋 Reason: $reason</div>' : ''}
    <div class="aegis-badge">PROTECTED BY AEGIS SHIELD</div>
  </div>
</body>
</html>
''';

  // ═══════════════════════════════════════════════════════════════════════════
  // Demo HTML
  // ═══════════════════════════════════════════════════════════════════════════
  static const String _demoHtml = '''
<!DOCTYPE html>
<html lang="th">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Test News Page</title>
  <style>
    body { font-family: sans-serif; background: #f5f5f5; padding: 16px; color: #333; }
    h1 { color: #1a1a2e; font-size: 22px; }
    p { line-height: 1.8; font-size: 15px; }
    .news-article { background: white; padding: 20px; border-radius: 12px; margin: 12px 0; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
    .ad-banner { background: linear-gradient(135deg, #ff4444, #cc0000); color: white; padding: 20px; border-radius: 12px; margin: 12px 0; text-align: center; font-weight: bold; font-size: 18px; }
    .ad-banner a { color: #FFD700; text-decoration: none; }
    .gambling-sidebar { background: #1a1a2e; color: #FFD700; padding: 16px; border-radius: 12px; margin: 12px 0; text-align: center; }
    .gambling-sidebar img { width: 100%; border-radius: 8px; margin: 8px 0; }
    .clean-ad { background: #e3f2fd; padding: 16px; border-radius: 12px; margin: 12px 0; text-align: center; color: #1565c0; }
  </style>
</head>
<body>
  <h1>📰 ข่าวเทคโนโลยีวันนี้</h1>
  <div class="news-article"><h2>AI เปลี่ยนโลกการทำงาน</h2><p>เทคโนโลยี Artificial Intelligence กำลังเปลี่ยนแปลงวิธีการทำงานของคนทั่วโลก จากการศึกษาล่าสุดพบว่า 70% ของบริษัทชั้นนำได้นำ AI มาใช้ในกระบวนการทำงานแล้ว</p></div>
  <div class="ad-banner" id="gambling-ad-1"><a href="https://ufa888-slot.com">🎰 UFA888 สล็อตออนไลน์ เครดิตฟรี 500 บาท!</a><p>ฝากถอนไม่มีขั้นต่ำ สมัครเลย!</p></div>
  <div class="news-article"><h2>Flutter 4.0 เปิดตัวฟีเจอร์ใหม่</h2><p>Google ได้เปิดตัว Flutter เวอร์ชันใหม่ล่าสุดพร้อมฟีเจอร์ที่ทำให้การพัฒนาแอปพลิเคชันข้ามแพลตฟอร์มง่ายขึ้น</p></div>
  <div class="gambling-sidebar" id="gambling-ad-2"><h3>🃏 บาคาร่า ฝากถอนออโต้</h3><a href="https://bet-casino-online.com"><img src="https://via.placeholder.com/300x100/FF0000/FFFFFF?text=CASINO+SLOT+888" alt="casino slot 888 bet online"></a><p>สล็อต เครดิตฟรี ไม่ต้องฝาก!</p></div>
  <div class="news-article"><h2>Cybersecurity Trends 2026</h2><p>ผู้เชี่ยวชาญด้านความปลอดภัยไซเบอร์คาดการณ์ว่าภัยคุกคามจาก Ransomware จะเพิ่มขึ้น 40% ในปี 2026</p></div>
  <div class="clean-ad" id="clean-ad"><p>📱 โปรโมชั่นมือถือรุ่นใหม่ ลดราคา 30%</p><a href="https://shop-electronics.com">ดูรายละเอียด</a></div>
  <script>
    setTimeout(function() {
      var lazyAd = document.createElement('div');
      lazyAd.id = 'lazy-gambling-ad';
      lazyAd.className = 'ad-banner';
      lazyAd.innerHTML = '<a href="https://slot-ufa-vip.com">🎰 สล็อต UFA VIP - ฝากถอนออโต้ 24 ชม.</a><p>เครดิตฟรี ไม่ต้องแชร์!</p>';
      document.body.appendChild(lazyAd);
    }, 2000);
  </script>
</body>
</html>
''';

  // ═══════════════════════════════════════════════════════════════════════════
  // initState
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    _initControllers();
    _setupWebView();
  }

  void _initControllers() {
    // DetectionController — ตั้งค่า Gemini + logging
    final apiKey = AppConfig.geminiApiKey;
    _detectionCtrl.initGeminiService(apiKey, logCallback: widget.onLog);

    // DetectionController — ฟัง isAnalyzing state
    _detectionCtrl.addListener(() {
      if (mounted) {
        setState(() => _isAnalyzing = _detectionCtrl.isAnalyzing);
      }
    });

    // ScriptInjectionController — เตรียม JS
    _scriptCtrl.prepare();
    _scriptCtrl.loadEasyList(onLog: widget.onLog);
  }

  void _setupWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          // ─── ชั้นที่ 1: Synchronous pre-filter check ───
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;

            // Pre-filter check (ช่องโหว่ #4: View ตัดสิน Navigation เอง)
            if (_detectionCtrl.isDefinitelyGambling(url)) {
              widget.onLog('🚫 BLOCKED: $url');
              widget.onLog('📋 Pre-filter: Known gambling brand blocked');
              _showBlockedPage(url, reason: 'Known gambling brand (pre-filter)');
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },

          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _isBlocked = false;
              _isAnalyzing = false;
            });
            _pageLoadVersion += 1;
            _submittedReportDomains.clear();
            _reportDebug(
              'page started url=$url pageLoadVersion=$_pageLoadVersion dedupe reset',
            );
          },

          // ─── ชั้นที่ 2-4: Async detection + DOM sanitizer ───
          onPageFinished: (url) async {
            setState(() => _isLoading = false);
            if (_isBlocked) return;

            // ดึง page title + deep content
            String pageTitle = '';
            String pageSnippet = '';
            try {
              final titleResult = await _controller
                  .runJavaScriptReturningResult('document.title || ""');
              pageTitle = titleResult.toString().replaceAll('"', '');

              final snippetResult = await _controller
                  .runJavaScriptReturningResult('''
                (function() {
                  var parts = [];
                  var bodyText = (document.body ? document.body.innerText : '').substring(0, 3000);
                  if (bodyText) parts.push('VISIBLE_TEXT: ' + bodyText);
                  var nextData = document.getElementById('__NEXT_DATA__');
                  if (nextData) {
                    var nd = nextData.textContent.substring(0, 4000);
                    parts.push('NEXT_DATA: ' + nd);
                  }
                  var metas = document.querySelectorAll('meta[name], meta[property]');
                  var metaTexts = [];
                  for (var i = 0; i < Math.min(metas.length, 10); i++) {
                    var name = metas[i].getAttribute('name') || metas[i].getAttribute('property') || '';
                    var content = metas[i].getAttribute('content') || '';
                    if (content) metaTexts.push(name + '=' + content);
                  }
                  if (metaTexts.length) parts.push('META: ' + metaTexts.join('; '));
                  var links = document.querySelectorAll('a[href]');
                  var linkTexts = [];
                  for (var i = 0; i < Math.min(links.length, 20); i++) {
                    var href = links[i].getAttribute('href') || '';
                    var text = (links[i].innerText || '').trim().substring(0, 50);
                    if (href && !href.startsWith('#') && !href.startsWith('javascript:'))
                      linkTexts.push(text + ' -> ' + href);
                  }
                  if (linkTexts.length) parts.push('LINKS: ' + linkTexts.join('; '));
                  var scripts = document.querySelectorAll('script[type="application/json"], script[type="application/ld+json"]');
                  for (var i = 0; i < scripts.length; i++) {
                    var content = scripts[i].textContent || '';
                    var lower = content.toLowerCase();
                    if (lower.indexOf('slot') !== -1 || lower.indexOf('casino') !== -1 ||
                        lower.indexOf('baccarat') !== -1 || lower.indexOf('betting') !== -1 ||
                        lower.indexOf('deposit') !== -1 || lower.indexOf('withdraw') !== -1 ||
                        lower.indexOf('pgsoft') !== -1 || lower.indexOf('sagame') !== -1) {
                      parts.push('SCRIPT_DATA: ' + content.substring(0, 3000));
                    }
                  }
                  var imgs = document.querySelectorAll('img');
                  var imgTexts = [];
                  for (var i = 0; i < Math.min(imgs.length, 15); i++) {
                    var alt = imgs[i].getAttribute('alt') || '';
                    var src = imgs[i].getAttribute('src') || '';
                    imgTexts.push((alt || 'no-alt') + ' src=' + src.substring(0, 100));
                  }
                  if (imgTexts.length) parts.push('IMAGES: ' + imgTexts.join('; '));
                  return parts.join(' ||| ');
                })()
              ''');
              pageSnippet = snippetResult.toString().replaceAll('"', '');
            } catch (e) {
              // ดึงไม่ได้ก็ไม่เป็นไร
            }

            // ─── 4-Layer Check (ช่องโหว่ #4: คืน DetectionResult) ───
            if (!url.startsWith('data:') && !url.startsWith('about:')) {
              widget.onLog('🔍 Starting 4-layer check for $url');
              final result = await _detectionCtrl.checkUrl(
                url,
                title: pageTitle,
                snippet: pageSnippet,
                captureScreenshot: _captureScreenshot,
              );
              // View ตัดสิน Navigation เอง จากผลที่ Controller คืนมา
              if (result.verdict == DetectionVerdict.blocked) {
                _showBlockedPage(url, reason: result.reason);
                return;
              } else if (result.verdict == DetectionVerdict.sanitize) {
                widget.onLog('🧹 Suspicious page allowed: removing gambling content instead of blocking');
                if (result.selectors.isNotEmpty) {
                  widget.onLog('💉 Injecting ${result.selectors.length} AI selectors...');
                  final js = _scriptCtrl.getDynamicSelectorsJs(result.selectors);
                  await _controller.runJavaScript(js);
                }
              } else if (result.selectors.isNotEmpty) {
                widget.onLog('💉 Injecting ${result.selectors.length} cached selectors...');
                final js = _scriptCtrl.getDynamicSelectorsJs(result.selectors);
                await _controller.runJavaScript(js);
              }
            }

            // ─── DOM Sanitizer (ช่องโหว่ #3: ใช้ ScriptInjectionController) ───
            await _injectSanitizer();

            // ─── Ad Blocker ───
            if (widget.adBlockEnabled) {
              await _injectAdBlocker();
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'AegisLogger',
        onMessageReceived: (message) {
          widget.onLog(message.message);
          _handlePotentialCommunityReport(message.message);
        },
      )
      ..addJavaScriptChannel(
        'AegisAdBlock',
        onMessageReceived: (message) {
          widget.onLog(message.message);
        },
      )
      ..addJavaScriptChannel(
        'AegisCacheMiss',
        onMessageReceived: (message) async {
          final removed = int.tryParse(message.message) ?? 0;
          if (removed == 0) {
            widget.onLog('⚠️ Cache Miss: 0 elements removed. AI is out of date / website updated.');
            final currentUrl = await _controller.currentUrl() ?? '';
            final domain = _extractDomain(currentUrl);
            final stopAi = await AdRemovalCache.reportCacheMiss(domain);
            
            if (!stopAi) {
               widget.onLog('🤖 Fallback: Re-triggering Gemini AI Analysis for new DOM...');
               final result = await _detectionCtrl.checkUrl(
                 currentUrl,
                 forceAiRefresh: true,
                 captureScreenshot: _captureScreenshot,
               );
               if (result.verdict == DetectionVerdict.blocked) {
                 _showBlockedPage(currentUrl, reason: result.reason);
               } else if (result.verdict == DetectionVerdict.sanitize) {
                 widget.onLog('🧹 Refreshed detection: sanitize page instead of blocking');
                 if (result.selectors.isNotEmpty) {
                   final js = _scriptCtrl.getDynamicSelectorsJs(result.selectors);
                   await _controller.runJavaScript(js);
                 }
               } else if (result.selectors.isNotEmpty) {
                 final js = _scriptCtrl.getDynamicSelectorsJs(result.selectors);
                 await _controller.runJavaScript(js);
               }
            } else {
               widget.onLog('📛 Miss count limit reached. Stopping AI to prevent infinite loops.');
            }
          } else {
            widget.onLog('🧹 Cache Hit: $removed elements successfully removed via CSS Selector.');
          }
        },
      )
      ..loadHtmlString(_demoHtml);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Helper Methods
  // ═══════════════════════════════════════════════════════════════════════════

  String _extractDomain(String url) {
    return _detectionCtrl.extractDomain(url);
  }

  Future<void> _handlePotentialCommunityReport(String message) async {
    final lower = message.toLowerCase();
    final hasRemoved = lower.contains('removed');
    final hasGambling = lower.contains('gambling');

    _reportDebug(
      'received jsLog="$message" hasRemoved=$hasRemoved hasGambling=$hasGambling',
    );

    if (!hasRemoved || !hasGambling) {
      _reportDebug('skip report because jsLog does not match community-report pattern');
      return;
    }

    final currentUrl = await _controller.currentUrl() ?? '';
    if (currentUrl.isEmpty ||
        currentUrl.startsWith('data:') ||
        currentUrl.startsWith('about:')) {
      _reportDebug('skip report because currentUrl is not reportable: $currentUrl');
      return;
    }

    final domain = _extractDomain(currentUrl);
    if (domain.isEmpty || _submittedReportDomains.contains(domain)) {
      _reportDebug(
        'skip report currentUrl=$currentUrl domain=$domain pageLoadVersion=$_pageLoadVersion alreadySubmitted=${_submittedReportDomains.contains(domain)}',
      );
      return;
    }

    _submittedReportDomains.add(domain);
    _reportDebug(
      'submitting community report for domain=$domain url=$currentUrl message=$message',
    );
    widget.onLog('📤 Attempting community report for $domain');

    final result = await _reportService.submitReport(
      ReportDraft(
        domain: domain,
        selectors: const [],
        isGambling: true,
        reason: message,
        reportType: ReportType.adSelector,
        clientVersion: 'aegis_shield_v3',
      ),
    );

    if (result.isSuccess) {
      _reportDebug('community report success for domain=$domain');
      widget.onLog('📤 Community report submitted for $domain');
      return;
    }

    _submittedReportDomains.remove(domain);
    _reportDebug(
      'community report failed for domain=$domain: ${result.failure?.message ?? "unknown"}',
    );
    widget.onLog(
      '⚠️ Community report failed for $domain: '
      '${result.failure?.message ?? "unknown"}',
    );
  }

  void _reportDebug(String message) {
    developer.log(message, name: 'CommunityReport');
    debugPrint('[CommunityReport] $message');
  }

  void _showBlockedPage(String url, {String reason = ''}) {
    setState(() => _isBlocked = true);
    _controller.loadHtmlString(_blockedPageHtml(url, reason: reason));
  }

  void _navigateTo(String url) {
    if (!url.startsWith('http')) url = 'https://$url';
    if (_detectionCtrl.isDefinitelyGambling(url)) {
      widget.onLog('🚫 BLOCKED: $url');
      widget.onLog('📋 Pre-filter: Known gambling brand');
      _showBlockedPage(url, reason: 'Known gambling brand (pre-filter)');
      return;
    }
    _controller.loadRequest(Uri.parse(url));
  }

  /// ช่องโหว่ #3 แก้แล้ว: View แค่รับ String สำเร็จรูปจาก Controller
  Future<void> _injectSanitizer() async {
    try {
      await _controller.runJavaScript(
        'window._aegisConfig = Object.assign({}, window._aegisConfig || {}, '
        '{ gamblingProtectionEnabled: true, adBlockEnabled: ${widget.adBlockEnabled ? 'true' : 'false'} });',
      );
      await _controller.runJavaScript(_scriptCtrl.keywordsInjectionJs);
      await _controller.runJavaScript(_scriptCtrl.sanitizerScript);
      widget.onLog(
        '🧹 DOM Sanitizer v4.0 injected (with ${_scriptCtrl.brandCount} keywords)',
      );
    } catch (e) {
      widget.onLog('❌ Failed to inject sanitizer: $e');
    }
  }

  Future<void> _injectAdBlocker() async {
    try {
      await _controller.runJavaScript(
        'window._aegisConfig = Object.assign({}, window._aegisConfig || {}, '
        '{ gamblingProtectionEnabled: true, adBlockEnabled: true });',
      );
      await _controller.runJavaScript(_scriptCtrl.adblockerScript);
      widget.onLog('🛡️ Ad Blocker v2.0 injected');

      try {
        final currentUrl = await _controller.currentUrl() ?? '';
        final domain = _extractDomain(currentUrl);
        final easylistJs = _scriptCtrl.getEasyListJs(domain);
        if (easylistJs.isNotEmpty) {
          await _controller.runJavaScript(easylistJs);
          widget.onLog(
            '📋 EasyList: ${_scriptCtrl.easyListRuleCount} rules active',
          );
        }
      } catch (e) {
        widget.onLog('⚠️ EasyList injection failed: $e');
      }
    } catch (e) {
      widget.onLog('❌ Failed to inject ad blocker: $e');
    }
  }

  Future<Uint8List?> _captureScreenshot() async {
    try {
      final dataUrl = await _controller.runJavaScriptReturningResult('''
        (function() {
          try {
            var canvas = document.createElement('canvas');
            var w = Math.min(document.documentElement.clientWidth || 360, 480);
            var h = Math.min(window.innerHeight || 640, 640);
            canvas.width = w; canvas.height = h;
            var ctx = canvas.getContext('2d');
            ctx.fillStyle = 'white';
            ctx.fillRect(0, 0, w, h);
            ctx.font = '14px sans-serif';
            ctx.fillStyle = 'black';
            var text = (document.body ? document.body.innerText : '').substring(0, 2000);
            var lines = text.split('\\n');
            var y = 20;
            for (var i = 0; i < lines.length && y < h - 10; i++) {
              var line = lines[i].trim();
              if (line) {
                ctx.fillText(line.substring(0, 60), 10, y);
                y += 18;
              }
            }
            return canvas.toDataURL('image/jpeg', 0.6);
          } catch(e) {
            return '';
          }
        })()
      ''');

      final dataUrlStr = dataUrl.toString().replaceAll('"', '');
      if (dataUrlStr.isNotEmpty && dataUrlStr.contains('data:image')) {
        final base64Part = dataUrlStr.split(',').last;
        final bytes = Uint8List.fromList(
          List<int>.from(Uri.parse('data:;base64,$base64Part').data!.contentAsBytes()),
        );
        widget.onLog(
          '📸 Viewport captured: ${(bytes.length / 1024).toStringAsFixed(0)} KB',
        );
        return bytes;
      }

      widget.onLog('📸 Viewport capture failed → text analysis fallback');
      return null;
    } catch (e) {
      widget.onLog('⚠️ Screenshot failed: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // dispose + build
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  void dispose() {
    OcrService.instance.close();
    _detectionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1F36),
        elevation: 0,
        title: const Text(
          'AEGIS Browser',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            fontSize: 16,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _controller.reload();
              widget.onLog('🔄 Page reloaded — re-scanning');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ─── URL Bar ───
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF1A1F36),
            child: Row(
              children: [
                Icon(
                  _isBlocked
                      ? Icons.block
                      : (_isAnalyzing ? Icons.psychology : Icons.lock),
                  color: _isBlocked
                      ? const Color(0xFFFF4444)
                      : (_isAnalyzing
                            ? const Color(0xFF7C4DFF)
                            : const Color(0xFF3FB950)),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                    decoration: InputDecoration(
                      hintText: 'Enter URL to test...',
                      hintStyle: TextStyle(color: Colors.grey.shade600),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0D1117),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: _navigateTo,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 20),
                  color: const Color(0xFF00D4FF),
                  onPressed: () => _navigateTo(_urlController.text),
                ),
              ],
            ),
          ),
          // ─── Loading / Analyzing indicator ───
          if (_isLoading)
            const LinearProgressIndicator(
              color: Color(0xFF00D4FF),
              backgroundColor: Color(0xFF1A1F36),
            ),
          if (_isAnalyzing)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: const Color(0xFF7C4DFF).withAlpha(30),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF7C4DFF),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    '🤖 AI กำลังวิเคราะห์เว็บไซต์...',
                    style: TextStyle(fontSize: 12, color: Color(0xFFB388FF)),
                  ),
                ],
              ),
            ),
          // ─── WebView ───
          Expanded(child: WebViewWidget(controller: _controller)),
          // ─── Status Bar ───
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF1A1F36),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isBlocked
                        ? const Color(0xFFFF4444)
                        : (_isAnalyzing
                              ? const Color(0xFF7C4DFF)
                              : const Color(0xFF3FB950)),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isBlocked
                      ? 'Website Blocked'
                      : (_isAnalyzing ? 'AI Analyzing...' : 'AI Protected'),
                  style: TextStyle(
                    fontSize: 11,
                    color: _isBlocked
                        ? const Color(0xFFFF4444)
                        : (_isAnalyzing
                              ? const Color(0xFF7C4DFF)
                              : const Color(0xFF3FB950)),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Icon(
                  _isBlocked
                      ? Icons.block
                      : (_isAnalyzing ? Icons.psychology : Icons.security),
                  size: 14,
                  color: _isBlocked
                      ? const Color(0xFFFF4444)
                      : (_isAnalyzing
                            ? const Color(0xFF7C4DFF)
                            : const Color(0xFF3FB950)),
                ),
                const SizedBox(width: 4),
                Text(
                  _isBlocked
                      ? 'Blocked'
                      : (_isAnalyzing ? 'Analyzing' : 'Protected'),
                  style: TextStyle(
                    fontSize: 11,
                    color: _isBlocked
                        ? const Color(0xFFFF4444)
                        : (_isAnalyzing
                              ? const Color(0xFF7C4DFF)
                              : const Color(0xFF3FB950)),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
