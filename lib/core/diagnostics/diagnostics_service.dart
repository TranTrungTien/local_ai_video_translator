import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LogLevel { debug, info, warning, error }

class DiagnosticEntry {
  const DiagnosticEntry({
    required this.timestamp,
    required this.subsystem,
    required this.message,
    required this.level,
    this.details,
  });

  final DateTime timestamp;
  final String subsystem;
  final String message;
  final LogLevel level;
  final Object? details;

  @override
  String toString() {
    final timeStr = timestamp.toIso8601String().substring(11, 19);
    final detailStr = details != null ? ' | $details' : '';
    return '[$timeStr] [${level.name.toUpperCase()}] [$subsystem] $message$detailStr';
  }
}

class DiagnosticsService {
  final _logs = <DiagnosticEntry>[];
  final _controller = StreamController<DiagnosticEntry>.broadcast();
  final Map<String, DateTime> _lastPosLogTime = {};

  List<DiagnosticEntry> get logs => List.unmodifiable(_logs);

  Stream<DiagnosticEntry> get stream => _controller.stream;

  void log(
    String subsystem,
    String message, {
    LogLevel level = LogLevel.info,
    Object? details,
  }) {
    final now = DateTime.now();

    // Log throttling: Protect the UI thread and stream listeners from high-frequency spam.
    // We skip the entire entry creation and notification for 'pos=' logs if < 1s has passed.
    if (subsystem == 'UI' && message.contains('pos=')) {
      final lastLog = _lastPosLogTime[subsystem] ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (now.difference(lastLog).inMilliseconds < 1000) {
        return;
      }
      _lastPosLogTime[subsystem] = now;
    }

    final entry = DiagnosticEntry(
      timestamp: now,
      subsystem: subsystem,
      message: message,
      level: level,
      details: details,
    );

    _logs.add(entry);
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }

    debugPrint(entry.toString());
    _controller.add(entry);
  }

  void clear() {
    _logs.clear();
  }

  void dispose() {
    _controller.close();
  }
}

final diagnosticsServiceProvider = Provider<DiagnosticsService>((ref) {
  final service = DiagnosticsService();
  ref.onDispose(service.dispose);
  return service;
});
