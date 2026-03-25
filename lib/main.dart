// ============================================================================
// AEGIS Shield — main.dart (Entry Point)
// ============================================================================
// จากเดิม 864 บรรทัด → เหลือ ~30 บรรทัด
//
// หน้าที่เดียว:
//   1. โหลด .env (Gemini API key)
//   2. โหลด gambling_keywords.json
//   3. สร้าง DashboardController (แก้ช่องโหว่ #2: ลำดับ Async)
//   4. runApp()
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'controllers/keyword_loader.dart';
import 'controllers/dashboard_controller.dart';
import 'controllers/debug_logger.dart';
import 'views/dashboard/dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Phase 0: เริ่มระบบ Debug Logger ──
  await DebugLogger.instance.init();
  DebugLogger.instance.system('🚀 AEGIS Shield starting...');

  // ── Phase 1: โหลด Config (ต้องเสร็จก่อน — ช่องโหว่ #2) ──
  try {
    await dotenv.load(fileName: '.env');
    final hasKey = (dotenv.env['GEMINI_API_KEY'] ?? '').isNotEmpty;
    DebugLogger.instance.system('✅ .env loaded (API key: ${hasKey ? "found" : "missing"})');
  } catch (e) {
    DebugLogger.instance.error('⚠️ .env load failed: $e');
    // ignore: avoid_print
    print('⚠️ .env not found or corrupted: $e — app will continue without API key');
  }

  try {
    final kw = KeywordLoader();
    await kw.load();
    DebugLogger.instance.system(
      '✅ Keywords loaded: ${kw.brandCount} brands, ${kw.patternCount} regex, '
      '${kw.providerCount} providers, ${kw.gameTypeCount} types',
    );
  } catch (e) {
    DebugLogger.instance.error('⚠️ Keywords load failed: $e');
    // ignore: avoid_print
    print('⚠️ gambling_keywords.json load failed: $e — using fallback keywords');
  }

  // ── Phase 2: สร้าง Controllers ──
  final dashboardController = DashboardController();
  DebugLogger.instance.system('✅ Controllers initialized');

  // ── Phase 3: เปิดแอป ──
  DebugLogger.instance.system('🏁 runApp() — AEGIS Shield ready');
  runApp(AegisApp(dashboardController: dashboardController));
}

class AegisApp extends StatelessWidget {
  final DashboardController dashboardController;

  const AegisApp({super.key, required this.dashboardController});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AEGIS Shield',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E21),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF00D4FF),
          secondary: const Color(0xFF7C4DFF),
          surface: const Color(0xFF1A1F36),
        ),
      ),
      home: DashboardScreen(controller: dashboardController),
    );
  }
}
