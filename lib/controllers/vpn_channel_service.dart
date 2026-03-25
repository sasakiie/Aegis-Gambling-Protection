// ============================================================================
// AEGIS Shield — controllers/vpn_channel_service.dart
// ============================================================================
// Wrapper สำหรับ Platform Channels (Flutter ↔ Native Android)
// ============================================================================

import 'package:flutter/services.dart';
import 'dart:async';

/// VPN Channel Service — จัดการ MethodChannel + EventChannel สำหรับ VPN
class VpnChannelService {
  static const _vpnChannel = MethodChannel('com.aegis/vpn');
  static const _logChannel = EventChannel('com.aegis/logs');

  /// เปิด VPN Service
  static Future<void> start() async {
    await _vpnChannel.invokeMethod('startVpn');
  }

  /// ปิด VPN Service
  static Future<void> stop() async {
    await _vpnChannel.invokeMethod('stopVpn');
  }

  /// ถามสถานะ VPN
  static Future<bool> isRunning() async {
    final result = await _vpnChannel.invokeMethod<bool>('isVpnRunning');
    return result ?? false;
  }

  /// รับ stream log จาก VPN Service (EventChannel)
  static Stream<dynamic> get logStream => _logChannel.receiveBroadcastStream();
}
