import 'package:flutter/material.dart';
import 'controllers/ad_removal_cache.dart';
import 'controllers/app_config.dart';
import 'controllers/dashboard_controller.dart';
import 'controllers/debug_logger.dart';
import 'controllers/keyword_loader.dart';
import 'views/dashboard/dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await DebugLogger.instance.init();
  DebugLogger.instance.system('AEGIS Shield starting');

  try {
    await AppConfig.load();
    DebugLogger.instance.system(
      'Config loaded (backend: ${AppConfig.pocketBaseUrl.isNotEmpty ? "configured" : "missing"}, '
      'Gemini key: ${AppConfig.hasGeminiApiKey ? "found" : "missing"})',
    );
  } catch (e) {
    DebugLogger.instance.error('Config load failed: $e');
    print('Config load failed: $e - app will continue with defaults');
  }

  try {
    final kw = KeywordLoader();
    await kw.load();
    DebugLogger.instance.system(
      'Keywords loaded: ${kw.brandCount} brands, ${kw.patternCount} regex, '
      '${kw.providerCount} providers, ${kw.gameTypeCount} types',
    );
  } catch (e) {
    DebugLogger.instance.error('Keywords load failed: $e');
    print('gambling_keywords.json load failed: $e - using fallback keywords');
  }

  try {
    await AdRemovalCache.init();
    DebugLogger.instance.system('AdRemovalCache initialized');
  } catch (e) {
    DebugLogger.instance.error('AdRemovalCache init failed: $e');
  }

  final dashboardController = DashboardController();
  DebugLogger.instance.system('Controllers initialized');
  DebugLogger.instance.system('runApp - AEGIS Shield ready');

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
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00D4FF),
          secondary: Color(0xFF7C4DFF),
          surface: Color(0xFF1A1F36),
        ),
      ),
      home: DashboardScreen(controller: dashboardController),
    );
  }
}
