// ============================================================================
// AEGIS Shield — views/dashboard/widgets/feature_toggle_card.dart
// ============================================================================
// Reusable toggle card widget
// ============================================================================

import 'package:flutter/material.dart';

class FeatureToggleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final Function(bool) onChanged;
  final Color activeColor;

  const FeatureToggleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: value
            ? activeColor.withAlpha(25)
            : const Color(0xFF1A1F36),
        border: Border.all(
          color: value ? activeColor.withAlpha(100) : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: value
            ? [
                BoxShadow(
                  color: activeColor.withAlpha(30),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: value ? activeColor.withAlpha(50) : Colors.grey.shade800,
          ),
          child: Icon(icon, color: value ? activeColor : Colors.grey, size: 24),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: value ? Colors.white : Colors.grey.shade400,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: activeColor,
        ),
      ),
    );
  }
}
