// ============================================================================
// AEGIS Shield — views/dashboard/widgets/shield_header.dart
// ============================================================================
// Shield icon + pulse animation header widget
// ============================================================================

import 'package:flutter/material.dart';

class ShieldHeader extends StatelessWidget {
  final bool isActive;
  final Animation<double> pulseAnimation;

  const ShieldHeader({
    super.key,
    required this.isActive,
    required this.pulseAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: isActive ? pulseAnimation.value : 0.8,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: isActive
                          ? [const Color(0xFF00D4FF), const Color(0xFF7C4DFF)]
                          : [Colors.grey.shade700, Colors.grey.shade800],
                    ),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: const Color(0xFF00D4FF).withAlpha(80),
                              blurRadius: 20,
                              spreadRadius: 4,
                            ),
                          ]
                        : [],
                  ),
                  child: const Icon(
                    Icons.security,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AEGIS',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    color: Colors.white,
                  ),
                ),
                Text(
                  isActive ? 'PROTECTION ACTIVE' : 'SHIELD OFFLINE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                    color: isActive
                        ? const Color(0xFF00D4FF)
                        : Colors.grey.shade500,
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
