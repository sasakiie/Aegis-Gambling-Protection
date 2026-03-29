// ============================================================================
// AEGIS Shield — controllers/script_injection_controller.dart
// ============================================================================
// เตรียม JS string สำเร็จรูปให้ View ใช้ inject เข้า WebView
// แก้ช่องโหว่ #3: ย้าย JS preparation logic ออกจาก View
// ============================================================================

import 'package:flutter/services.dart' show rootBundle;
import 'keyword_loader.dart';
import 'easylist_service.dart';

/// ScriptInjectionController — เตรียม JS string สำหรับ WebView
class ScriptInjectionController {
  final KeywordLoader _keywords = KeywordLoader();
  String? _sanitizerJs;
  String? _adblockerJs;
  bool _prepared = false;

  bool get isPrepared => _prepared;

  /// เตรียม JS (เรียกครั้งเดียวตอน init)
  Future<void> prepare() async {
    try {
      _sanitizerJs = await rootBundle.loadString('assets/sanitizer.js');
      _adblockerJs = await rootBundle.loadString('assets/adblocker.js');
      _prepared = true;
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ ScriptInjectionController.prepare failed: $e');
    }
  }

  /// คืน JS สำหรับ inject keywords + sanitizer.js
  String get keywordsInjectionJs {
    return 'window._aegisKeywords = ${_keywords.toJsonForJs()};';
  }

  /// คืน sanitizer.js content
  String get sanitizerScript => _sanitizerJs ?? '';

  /// คืน adblocker.js content
  String get adblockerScript => _adblockerJs ?? '';

  /// คืน brand/pattern count สำหรับ log
  int get brandCount => _keywords.brandCount;

  /// คืน EasyList injection JS สำหรับ domain นั้น
  String getEasyListJs(String domain) {
    return EasyListService.instance.getInjectionJS(domain);
  }

  /// คืนจำนวน EasyList rules
  int get easyListRuleCount => EasyListService.instance.ruleCount;

  /// สร้าง JS สำหรับลบ element ตาม CSS Selectors ที่ AI ให้มา
  String getDynamicSelectorsJs(List<String> selectors) {
    if (selectors.isEmpty) return '';
    final selectorsJson = selectors.map((s) => '"${s.replaceAll('"', '\\"')}"').join(',');
    return '''
      (function() {
        try {
          var selectors = [$selectorsJson];
          var removed = 0;
          selectors.forEach(function(sel) {
            try {
              var els = document.querySelectorAll(sel);
              els.forEach(function(el) { el.remove(); removed++; });
            } catch(e) {}
          });
          if (window.AegisCacheMiss) {
            window.AegisCacheMiss.postMessage(removed.toString());
          }
        } catch(e) {}
      })();
    ''';
  }

  /// โหลด EasyList (background)
  void loadEasyList({void Function(String)? onLog}) {
    EasyListService.instance.loadFilters(onLog: onLog);
  }
}
