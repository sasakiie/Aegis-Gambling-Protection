// ============================================================================
// AEGIS Shield — views/dashboard/dashboard_screen.dart
// ============================================================================
// Dashboard หลักแสดง Shield + Toggles + Log panel
// ใช้ ListenableBuilder ฟัง DashboardController (แก้ช่องโหว่ #1)
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../controllers/dashboard_controller.dart';

import '../../models/log_entry.dart';
import '../browser/webview_screen.dart';
import 'widgets/shield_header.dart';
import 'widgets/feature_toggle_card.dart';
import 'widgets/live_log_panel.dart';

class DashboardScreen extends StatefulWidget {
  final DashboardController controller;

  const DashboardScreen({super.key, required this.controller});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  // ─── Animation ───
  late AnimationController _shieldPulse;
  late Animation<double> _pulseAnim;

  DashboardController get ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    // Pulse animation สำหรับ Shield icon
    _shieldPulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _shieldPulse, curve: Curves.easeInOut),
    );

    // โหลดข้อมูล AI status
    ctrl.loadAiStatus();
    // เริ่มรับ log จาก VPN
    ctrl.startListeningVpnLogs();
    // ข้อความต้อนรับ
    ctrl.addLog('🚀 AEGIS Shield v3.0 Ready', LogType.success);
    ctrl.addLog('   3-Layer Protection: Network → DOM → AI', LogType.info);
  }

  @override
  void dispose() {
    _shieldPulse.dispose();
    super.dispose();
  }

  void _showSettingsDialog() async {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    final maskedKey = apiKey.isEmpty
        ? 'Not configured'
        : '${apiKey.substring(0, 8)}...${apiKey.substring(apiKey.length - 4)}';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.settings, color: Color(0xFF00D4FF), size: 20),
            SizedBox(width: 8),
            Text(
              'AI Setting',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gemini API Key',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    apiKey.isNotEmpty ? Icons.check_circle : Icons.error,
                    size: 16,
                    color: apiKey.isNotEmpty
                        ? const Color(0xFF3FB950)
                        : const Color(0xFFFF6B6B),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      maskedKey,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (apiKey.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'เพิ่ม GEMINI_API_KEY ในไฟล์ .env ที่ root ของ project',
                  style: TextStyle(color: Color(0xFFFF9999), fontSize: 11),
                ),
              ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cached, color: Color(0xFF00D4FF), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Cached domains: ${ctrl.cachedDomains}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      await ctrl.clearCache();
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        color: Color(0xFFFF6B6B),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _openTestBrowser() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebViewScreen(
          onLog: (msg) => ctrl.addLog(msg, LogType.cleaned),
          adBlockEnabled: ctrl.adBlockEnabled,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: SafeArea(
        // ListenableBuilder ดักฟัง DashboardController → rebuild เมื่อ state เปลี่ยน
        child: ListenableBuilder(
          listenable: ctrl,
          builder: (context, _) {
            return Column(
              children: [
                // ─── Header ───
                ShieldHeader(
                  isActive: ctrl.isActive,
                  pulseAnimation: _pulseAnim,
                ),
                // ─── AI Status Bar ───
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GestureDetector(
                    onTap: _showSettingsDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: ctrl.hasApiKey
                            ? const Color(0xFF7C4DFF).withAlpha(20)
                            : const Color(0xFFFF6B6B).withAlpha(20),
                        border: Border.all(
                          color: ctrl.hasApiKey
                              ? const Color(0xFF7C4DFF).withAlpha(60)
                              : const Color(0xFFFF6B6B).withAlpha(60),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            ctrl.hasApiKey ? Icons.psychology : Icons.warning_amber,
                            size: 16,
                            color: ctrl.hasApiKey
                                ? const Color(0xFF7C4DFF)
                                : const Color(0xFFFF6B6B),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              ctrl.hasApiKey
                                  ? 'AI Protection Active · ${ctrl.cachedDomains} cached'
                                  : 'Tap to configure Gemini AI key',
                              style: TextStyle(
                                fontSize: 12,
                                color: ctrl.hasApiKey
                                    ? const Color(0xFFB388FF)
                                    : const Color(0xFFFF9999),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.settings,
                            size: 14,
                            color: ctrl.hasApiKey
                                ? const Color(0xFF7C4DFF)
                                : const Color(0xFFFF6B6B),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // ─── Toggle Cards ───
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      FeatureToggleCard(
                        icon: Icons.shield,
                        title: 'Ad Blocker',
                        subtitle: 'Block ads & popups in AEGIS Browser',
                        value: ctrl.adBlockEnabled,
                        onChanged: ctrl.toggleAdBlock,
                        activeColor: const Color(0xFF00D4FF),
                      ),
                      const SizedBox(height: 12),
                      FeatureToggleCard(
                        icon: Icons.casino,
                        title: 'Gambling Protection',
                        subtitle: 'AI-powered website blocking & banner removal',
                        value: ctrl.bannerRemoverEnabled,
                        onChanged: ctrl.toggleBannerRemover,
                        activeColor: const Color(0xFF7C4DFF),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // ─── Open Test Browser Button ───
                if (ctrl.bannerRemoverEnabled)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _openTestBrowser,
                        icon: const Icon(Icons.language, size: 20),
                        label: const Text('Open Test Browser'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C4DFF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                // ─── Live Log Panel ───
                LiveLogPanel(logs: ctrl.logs),
              ],
            );
          },
        ),
      ),
    );
  }
}
