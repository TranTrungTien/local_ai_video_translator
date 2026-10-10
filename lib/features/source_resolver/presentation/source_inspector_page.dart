import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/media_candidate.dart';
import '../domain/entities/resolved_source.dart';

class SourceInspectorPage extends StatelessWidget {
  const SourceInspectorPage({required this.source, super.key});

  final ResolvedSource source;

  void _copyDiagnostics(BuildContext context) {
    final buffer = StringBuffer()
      ..writeln('=== LOCAL AI VIDEO TRANSLATOR - SOURCE INSPECTION REPORT ===')
      ..writeln('Input: ${source.input}')
      ..writeln('Normalized URL: ${source.normalizedUri}')
      ..writeln('Final URL: ${source.finalUri}')
      ..writeln('Playback Mode: ${source.playbackMode.name}')
      ..writeln('Media Kind: ${source.kind.name}')
      ..writeln('Discovery Method: ${source.discoveryMethod.name}')
      ..writeln(
        'Resolution Duration: ${source.resolutionDuration.inMilliseconds}ms',
      )
      ..writeln()
      ..writeln('--- REDIRECT CHAIN ---')
      ..writeln(
        source.redirectChain.isEmpty ? 'None' : source.redirectChain.join('\n'),
      )
      ..writeln()
      ..writeln('--- IFRAME CHAIN ---')
      ..writeln(
        source.iframeChain.isEmpty ? 'None' : source.iframeChain.join('\n'),
      )
      ..writeln()
      ..writeln('--- CANDIDATES (${source.candidates.length}) ---');

    for (final c in source.candidates) {
      buffer.writeln('- [${c.validationStatus.name.toUpperCase()}] ${c.uri}');
      buffer.writeln(
        '  Kind: ${c.kind.name} | Method: ${c.method.name} | Score: ${c.score} | HTTP: ${c.statusCode}',
      );
      if (c.rejectionReason != null) {
        buffer.writeln('  Rejection: ${c.rejectionReason}');
      }
    }

    buffer
      ..writeln()
      ..writeln('--- CAPABILITIES ---')
      ..writeln('Native Playback: ${source.capability.nativePlayback}')
      ..writeln('Embedded Playback: ${source.capability.embeddedPlayback}')
      ..writeln('Seek Controllable: ${source.capability.seekControllable}')
      ..writeln('Position Readable: ${source.capability.positionReadable}')
      ..writeln('Audio Accessible: ${source.capability.audioAccessible}')
      ..writeln(
        'Subtitle Track Accessible: ${source.capability.subtitleTracksAccessible}',
      )
      ..writeln('AI Lookahead: ${source.capability.aiLookahead}')
      ..writeln('Dubbing Potential: ${source.capability.dubbingPotential}')
      ..writeln()
      ..writeln('--- DIAGNOSTIC LOGS ---')
      ..writeln(source.diagnostics.join('\n'));

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostic report copied to clipboard!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cap = source.capability;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Source Compatibility Inspector'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: 'Copy Diagnostic Text',
            onPressed: () => _copyDiagnostics(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(
            'URLs & Resolution Path (${source.resolutionDuration.inMilliseconds}ms)',
          ),
          _DetailTile('Input', source.input),
          _DetailTile('Normalized', source.normalizedUri.toString()),
          _DetailTile('Final URL', source.finalUri.toString()),
          _DetailTile(
            'Playback Mode',
            source.playbackMode.name.toUpperCase(),
            isHighlight: true,
          ),
          _DetailTile('Media Kind', source.kind.name.toUpperCase()),
          _DetailTile('Discovery', source.discoveryMethod.name),
          const SizedBox(height: 16),

          _SectionHeader('Redirect Chain (${source.redirectChain.length})'),
          if (source.redirectChain.isEmpty)
            const Text(
              'No redirects recorded.',
              style: TextStyle(color: Colors.white54),
            )
          else
            ...source.redirectChain.map(
              (u) => Text('• $u', style: const TextStyle(fontSize: 12)),
            ),
          const SizedBox(height: 16),

          _SectionHeader('Iframe Chain (${source.iframeChain.length})'),
          if (source.iframeChain.isEmpty)
            const Text(
              'No iframes in chain.',
              style: TextStyle(color: Colors.white54),
            )
          else
            ...source.iframeChain.map(
              (u) => Text('• $u', style: const TextStyle(fontSize: 12)),
            ),
          const SizedBox(height: 16),

          _SectionHeader('Media Candidates (${source.candidates.length})'),
          if (source.candidates.isEmpty)
            const Text(
              'No candidates collected yet.',
              style: TextStyle(color: Colors.white54),
            )
          else
            ...source.candidates.map((c) => _CandidateCard(candidate: c)),
          const SizedBox(height: 16),

          _SectionHeader('Capability Matrix'),
          _CapabilityRow('Native Playback', cap.nativePlayback),
          _CapabilityRow('Embedded Playback', cap.embeddedPlayback),
          _CapabilityRow('Seek Controllable', cap.seekControllable),
          _CapabilityRow('Position Readable', cap.positionReadable),
          _CapabilityRow('Audio Accessible', cap.audioAccessible),
          _CapabilityRow(
            'Subtitle Track Accessible',
            cap.subtitleTracksAccessible,
          ),
          _CapabilityRow('AI Lookahead', cap.aiLookahead),
          _CapabilityRow('Dubbing Potential', cap.dubbingPotential),
          const SizedBox(height: 16),

          _SectionHeader('Diagnostics & Rejection Logs'),
          ...source.diagnostics.map(
            (d) => Text(
              '• $d',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
          if (source.rejectionReasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Rejections:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orangeAccent,
              ),
            ),
            ...source.rejectionReasons.entries.map(
              (e) => Text(
                '${e.key} => ${e.value}',
                style: const TextStyle(fontSize: 11, color: Colors.orange),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: Color(0xFF7C5CFC),
        ),
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile(this.label, this.value, {this.isHighlight = false});
  final String label;
  final String value;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
                color: isHighlight ? Colors.greenAccent : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.candidate});
  final MediaCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final isVal = candidate.validationStatus == CandidateValidationStatus.valid;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isVal
          ? Colors.green.withValues(alpha: 0.1)
          : Colors.red.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isVal ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    candidate.validationStatus.name.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    candidate.uri.toString(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Kind: ${candidate.kind.name} | Method: ${candidate.method.name} | Score: ${candidate.score} | Status: ${candidate.statusCode}',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
            if (candidate.rejectionReason != null)
              Text(
                'Rejection: ${candidate.rejectionReason}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.orangeAccent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow(this.label, this.supported);
  final String label;
  final bool supported;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            supported ? Icons.check_circle : Icons.cancel,
            color: supported ? Colors.greenAccent : Colors.redAccent,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
