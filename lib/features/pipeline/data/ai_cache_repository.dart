import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../domain/cache_invalidation.dart';
import '../domain/media_identity.dart';
import '../domain/ai_pipeline.dart';

class AiCachedRecord {
  const AiCachedRecord({
    required this.fingerprint,
    required this.sttVersion,
    required this.translationVersion,
    required this.targetLanguage,
    required this.pipelineVersion,
    required this.segments,
    required this.createdAt,
    required this.sizeBytes,
  });

  final String fingerprint;
  final String sttVersion;
  final String translationVersion;
  final String targetLanguage;
  final String pipelineVersion;
  final List<TimedTextSegment> segments;
  final DateTime createdAt;
  final int sizeBytes;

  Map<String, dynamic> toJson() => {
    'fingerprint': fingerprint,
    'sttVersion': sttVersion,
    'translationVersion': translationVersion,
    'targetLanguage': targetLanguage,
    'pipelineVersion': pipelineVersion,
    'createdAt': createdAt.toIso8601String(),
    'sizeBytes': sizeBytes,
    'segments': segments
        .map(
          (s) => {
            'startMs': s.start.inMilliseconds,
            'endMs': s.end.inMilliseconds,
            'text': s.text,
            'language': s.language,
          },
        )
        .toList(),
  };

  factory AiCachedRecord.fromJson(Map<String, dynamic> json) {
    final rawSegments = (json['segments'] as List<dynamic>?) ?? [];
    final segments = rawSegments
        .map(
          (e) => TimedTextSegment(
            start: Duration(milliseconds: e['startMs'] as int),
            end: Duration(milliseconds: e['endMs'] as int),
            text: e['text'] as String,
            language: e['language'] as String?,
          ),
        )
        .toList();

    return AiCachedRecord(
      fingerprint: json['fingerprint'] as String,
      sttVersion: json['sttVersion'] as String,
      translationVersion: json['translationVersion'] as String,
      targetLanguage: json['targetLanguage'] as String,
      pipelineVersion: json['pipelineVersion'] as String,
      segments: segments,
      createdAt: DateTime.parse(json['createdAt'] as String),
      sizeBytes: json['sizeBytes'] as int,
    );
  }
}

class AiCacheRepository {
  AiCacheRepository({CacheInvalidationPolicy? invalidationPolicy})
    : _invalidationPolicy =
          invalidationPolicy ?? CacheInvalidationPolicy.currentPolicy;

  final CacheInvalidationPolicy _invalidationPolicy;
  final Map<String, AiCachedRecord> _memoryCache = {};

  Future<Directory> get _cacheDir async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/ai_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> saveRecord({
    required MediaIdentity identity,
    required List<TimedTextSegment> segments,
  }) async {
    final fingerprint = identity.generateFingerprint();
    final jsonStr = jsonEncode({
      'fingerprint': fingerprint,
      'sttVersion': _invalidationPolicy.sttModelVersion,
      'translationVersion': _invalidationPolicy.translationModelVersion,
      'targetLanguage': _invalidationPolicy.targetLanguage,
      'pipelineVersion': _invalidationPolicy.pipelineVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'sizeBytes': segments.fold<int>(0, (sum, s) => sum + s.text.length * 2),
      'segments': segments
          .map(
            (s) => {
              'startMs': s.start.inMilliseconds,
              'endMs': s.end.inMilliseconds,
              'text': s.text,
              'language': s.language,
            },
          )
          .toList(),
    });

    final record = AiCachedRecord(
      fingerprint: fingerprint,
      sttVersion: _invalidationPolicy.sttModelVersion,
      translationVersion: _invalidationPolicy.translationModelVersion,
      targetLanguage: _invalidationPolicy.targetLanguage,
      pipelineVersion: _invalidationPolicy.pipelineVersion,
      segments: segments,
      createdAt: DateTime.now(),
      sizeBytes: jsonStr.length,
    );

    _memoryCache[fingerprint] = record;

    try {
      final dir = await _cacheDir;
      final file = File('${dir.path}/$fingerprint.json');
      await file.writeAsString(jsonStr);
    } catch (_) {
      // Disk write fallback
    }
  }

  Future<List<TimedTextSegment>?> getRecord(MediaIdentity identity) async {
    final fingerprint = identity.generateFingerprint();

    if (_memoryCache.containsKey(fingerprint)) {
      final rec = _memoryCache[fingerprint]!;
      if (_invalidationPolicy.isCompatible(
        cachedSttVersion: rec.sttVersion,
        cachedTranslationVersion: rec.translationVersion,
        cachedTargetLang: rec.targetLanguage,
        cachedPipelineVersion: rec.pipelineVersion,
      )) {
        return rec.segments;
      }
    }

    try {
      final dir = await _cacheDir;
      final file = File('${dir.path}/$fingerprint.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final jsonMap = jsonDecode(content) as Map<String, dynamic>;
        final rec = AiCachedRecord.fromJson(jsonMap);

        if (_invalidationPolicy.isCompatible(
          cachedSttVersion: rec.sttVersion,
          cachedTranslationVersion: rec.translationVersion,
          cachedTargetLang: rec.targetLanguage,
          cachedPipelineVersion: rec.pipelineVersion,
        )) {
          _memoryCache[fingerprint] = rec;
          return rec.segments;
        }
      }
    } catch (_) {
      // Disk read fallback
    }

    return null;
  }

  Future<int> getTotalCacheSizeBytes() async {
    int total = 0;
    for (final rec in _memoryCache.values) {
      total += rec.sizeBytes;
    }

    try {
      final dir = await _cacheDir;
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            total += await entity.length();
          }
        }
      }
    } catch (_) {}

    return total;
  }

  Future<void> clearMedia(MediaIdentity identity) async {
    final fingerprint = identity.generateFingerprint();
    _memoryCache.remove(fingerprint);

    try {
      final dir = await _cacheDir;
      final file = File('${dir.path}/$fingerprint.json');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> clearAll() async {
    _memoryCache.clear();

    try {
      final dir = await _cacheDir;
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (_) {}
  }

  /// Bounded storage automatic cleanup policy (LRU / max size enforcement)
  Future<void> enforceBoundedStorage({
    int maxSizeBytes = 100 * 1024 * 1024,
  }) async {
    final currentSize = await getTotalCacheSizeBytes();
    if (currentSize <= maxSizeBytes) return;

    try {
      final dir = await _cacheDir;
      if (await dir.exists()) {
        final files = <File>[];
        await for (final entity in dir.list()) {
          if (entity is File) {
            files.add(entity);
          }
        }

        // Sort by last modified (oldest first for LRU eviction)
        files.sort(
          (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
        );

        for (final file in files) {
          await file.delete();
          // Remove from memory cache as well
          final name = file.uri.pathSegments.last;
          final fingerprint = name.replaceAll('.json', '');
          _memoryCache.remove(fingerprint);

          final newSize = await getTotalCacheSizeBytes();
          if (newSize <= maxSizeBytes) break;
        }
      }
    } catch (_) {}
  }
}
