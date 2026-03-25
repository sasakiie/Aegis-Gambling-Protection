// ============================================================================
// AEGIS Shield — views/dashboard/widgets/live_log_panel.dart
// ============================================================================
// Live Log panel widget with auto-scroll
// ============================================================================

import 'package:flutter/material.dart';
import '../../../models/log_entry.dart';

class LiveLogPanel extends StatefulWidget {
  final List<LogEntry> logs;

  const LiveLogPanel({super.key, required this.logs});

  @override
  State<LiveLogPanel> createState() => _LiveLogPanelState();
}

class _LiveLogPanelState extends State<LiveLogPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant LiveLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll เมื่อมี log ใหม่
    if (widget.logs.length > oldWidget.logs.length) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF21262D)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Log Panel Header ───
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF21262D))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.logs.isEmpty
                          ? Colors.grey
                          : const Color(0xFF3FB950),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'LIVE LOG',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: Color(0xFF8B949E),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${widget.logs.length} events',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8B949E),
                    ),
                  ),
                ],
              ),
            ),
            // ─── Log Entries List ───
            Expanded(
              child: widget.logs.isEmpty
                  ? Center(
                      child: Text(
                        'Waiting for activity...',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: widget.logs.length,
                      itemBuilder: (context, index) {
                        final log = widget.logs[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${log.time.hour.toString().padLeft(2, '0')}:${log.time.minute.toString().padLeft(2, '0')}:${log.time.second.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: Color(0xFF484F58),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  log.message,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    color: log.color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
