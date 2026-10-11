import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../diagnostics_service.dart';

class DiagnosticLogOverlay extends ConsumerWidget {
  const DiagnosticLogOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagnostics = ref.watch(diagnosticsServiceProvider);

    return Container(
      color: Colors.black.withValues(alpha: 0.9),
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'SYSTEM DIAGNOSTICS LOG',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.white),
                      onPressed: () {
                        final allLogs = diagnostics.logs.join('\n');
                        Clipboard.setData(ClipboardData(text: allLogs));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Logs copied to clipboard')),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_sweep, color: Colors.white),
                      onPressed: () => diagnostics.clear(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white24),
          Expanded(
            child: StreamBuilder<DiagnosticEntry>(
              stream: diagnostics.stream,
              builder: (context, snapshot) {
                final logs = diagnostics.logs.reversed.toList();
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: logs.length,
                  separatorBuilder: (_, _) => const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final entry = logs[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: SelectableText(
                        entry.toString(),
                        style: TextStyle(
                          color: _getColor(entry.level),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _getColor(LogLevel level) {
    switch (level) {
      case LogLevel.error: return Colors.redAccent;
      case LogLevel.warning: return Colors.orangeAccent;
      case LogLevel.debug: return Colors.grey;
      case LogLevel.info: return Colors.white70;
    }
  }
}
