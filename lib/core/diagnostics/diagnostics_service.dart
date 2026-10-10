import 'dart:async';
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

  List<DiagnosticEntry> get logs => List.unmodifiable(_logs);
  Stream<DiagnosticEntry> get stream => _controller.stream;

  void log(
    String subsystem,
    String message, {
    LogLevel level = LogLevel.info,
    Object? details,
  }) {
    final entry = DiagnosticEntry(
      timestamp: DateTime.now(),
      subsystem: subsystem,
      message: message,
      level: level,
      details: details,
    );
    _logs.add(entry);
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }
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
