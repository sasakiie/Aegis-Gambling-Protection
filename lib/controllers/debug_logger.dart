import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum LogLevel { system, detection, ai, vpn, sanitizer, cache, error }

class DebugLogger {
  static DebugLogger? _instance;

  File? _logFile;
  IOSink? _sink;
  bool _ready = false;
  Future<void> _writeQueue = Future<void>.value();

  DebugLogger._();

  static DebugLogger get instance {
    _instance ??= DebugLogger._();
    return _instance!;
  }

  Future<void> init() async {
    if (_ready) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/aegis_debug.log');

      if (await _logFile!.exists()) {
        final size = await _logFile!.length();
        if (size > 5 * 1024 * 1024) {
          await _logFile!.delete();
        }
      }

      _sink = _logFile!.openWrite(mode: FileMode.append);
      _ready = true;

      await _enqueueWrite(<String>[
        '',
        '========================================================',
        '  AEGIS Debug Session - ${DateTime.now().toIso8601String()}',
        '========================================================',
      ], flush: true);
    } catch (e) {
      stderr.writeln('DebugLogger init failed: $e');
    }
  }

  void log(LogLevel level, String message) {
    if (!_ready || _sink == null) return;

    final timestamp = _formatTimestamp(DateTime.now());
    final tag = _levelTag(level);
    final line = '[$timestamp] [$tag] $message';
    unawaited(_enqueueWrite(<String>[line], flush: level == LogLevel.error));
  }

  void system(String msg) => log(LogLevel.system, msg);
  void detection(String msg) => log(LogLevel.detection, msg);
  void ai(String msg) => log(LogLevel.ai, msg);
  void vpn(String msg) => log(LogLevel.vpn, msg);
  void sanitizer(String msg) => log(LogLevel.sanitizer, msg);
  void cache(String msg) => log(LogLevel.cache, msg);
  void error(String msg) => log(LogLevel.error, msg);

  Future<String> readLog() async {
    if (_logFile == null || !await _logFile!.exists()) return '(no log file)';
    await _writeQueue;
    await _sink?.flush();
    return _logFile!.readAsString();
  }

  Future<int> logSize() async {
    if (_logFile == null || !await _logFile!.exists()) return 0;
    return _logFile!.length();
  }

  String? get logPath => _logFile?.path;

  Future<void> clearLog() async {
    if (_logFile == null) return;

    _writeQueue = _writeQueue.then((_) async {
      await _sink?.flush();
      await _sink?.close();

      if (await _logFile!.exists()) {
        await _logFile!.delete();
      }

      _sink = _logFile!.openWrite(mode: FileMode.append);
      _ready = true;
      _sink!.writeln(
        '[${_formatTimestamp(DateTime.now())}] [SYSTEM   ] Log cleared by admin',
      );
      await _sink!.flush();
    }).catchError((_) {});

    await _writeQueue;
  }

  Future<void> dispose() async {
    await _writeQueue;
    await _sink?.flush();
    await _sink?.close();
    _ready = false;
  }

  Future<void> _enqueueWrite(
    List<String> lines, {
    bool flush = false,
  }) {
    final sink = _sink;
    if (sink == null) return Future<void>.value();

    _writeQueue = _writeQueue.then((_) async {
      for (final line in lines) {
        sink.writeln(line);
      }

      if (flush || lines.length > 1) {
        await sink.flush();
      }
    }).catchError((_) {});

    return _writeQueue;
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}.'
        '${dt.millisecond.toString().padLeft(3, '0')}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  String _levelTag(LogLevel level) {
    switch (level) {
      case LogLevel.system:
        return 'SYSTEM   ';
      case LogLevel.detection:
        return 'DETECTION';
      case LogLevel.ai:
        return 'AI       ';
      case LogLevel.vpn:
        return 'VPN      ';
      case LogLevel.sanitizer:
        return 'SANITIZER';
      case LogLevel.cache:
        return 'CACHE    ';
      case LogLevel.error:
        return 'ERROR    ';
    }
  }
}
