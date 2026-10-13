# Review Module: 02. Source Resolver & Native Observer

## Included Files (12 files)

```text
android/app/src/main/kotlin/com/example/local_ai_video_translator/MainActivity.kt
lib/features/source_resolver/data/android_media_observer.dart
lib/features/source_resolver/data/candidate_verifier.dart
lib/features/source_resolver/data/html_media_parser.dart
lib/features/source_resolver/data/media_candidate.dart
lib/features/source_resolver/data/source_resolver_repository_impl.dart
lib/features/source_resolver/domain/entities/resolved_source.dart
lib/features/source_resolver/domain/repositories/source_resolver_repository.dart
lib/features/source_resolver/domain/usecases/resolve_source.dart
lib/features/source_resolver/presentation/source_analysis_page.dart
lib/features/source_resolver/presentation/source_inspector_page.dart
lib/features/source_resolver/presentation/source_resolver_controller.dart
```

## android/app/src/main/kotlin/com/example/local_ai_video_translator/MainActivity.kt
```kotlin:android/app/src/main/kotlin/com/example/local_ai_video_translator/MainActivity.kt
package com.example.local_ai_video_translator

import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * Native extension point for Android runtime media discovery, candidate verification,
 * and hardware capability profiling.
 */
class MainActivity : FlutterActivity() {
    companion object {
        const val MEDIA_EVENTS_CHANNEL = "local_ai_video_translator/media_events"
        const val AUDIO_PCM_CHANNEL = "local_ai_video_translator/audio_pcm"
        const val NATIVE_RESOLVER_CHANNEL = "local_ai_video_translator/native_resolver"
        const val REQUEST_MEDIA_PROJECTION = 1001

        private var eventSink: EventChannel.EventSink? = null
        private val mainHandler = Handler(Looper.getMainLooper())

        fun emitMediaEvent(eventData: Map<String, Any?>) {
            mainHandler.post {
                eventSink?.success(eventData)
            }
        }
    }

    private var pendingAudioResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Stream channel for runtime media discovery events
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_EVENTS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        // EventChannel for PCM audio data
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_PCM_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    AudioPcmBroker.setSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    AudioPcmBroker.setSink(null)
                }
            })

        // Method channel for candidate verification and device metrics
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_RESOLVER_CHANNEL)
            .setMethodCallHandler(object : MethodChannel.MethodCallHandler {
                override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
                    when (call.method) {
                        "startAudioCapture" -> {
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                                result.error("UNSUPPORTED", "Audio capture requires Android 10+", null)
                                return
                            }
                            pendingAudioResult = result
                            val mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                            startActivityForResult(mediaProjectionManager.createScreenCaptureIntent(), REQUEST_MEDIA_PROJECTION)
                        }

                        "stopAudioCapture" -> {
                            val intent = Intent(this@MainActivity, AudioCaptureService::class.java).apply {
                                action = AudioCaptureService.ACTION_STOP
                            }
                            startService(intent)
                            result.success(true)
                        }

                        "verifyCandidate" -> {
                            val urlStr = call.argument<String>("url")
                            val headersMap: Map<String, String>? = call.argument("headers")
                            if (urlStr.isNullOrEmpty()) {
                                result.error("INVALID_ARG", "URL is null or empty", null)
                                return
                            }
                            thread {
                                try {
                                    val url = URL(urlStr)
                                    val conn = url.openConnection() as HttpURLConnection
                                    conn.requestMethod = "HEAD"
                                    conn.connectTimeout = 8000
                                    conn.readTimeout = 8000
                                    conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 13) LocalAIVideoTranslator/1.0")
                                    if (headersMap != null) {
                                        for ((k, v) in headersMap) {
                                            conn.setRequestProperty(k, v)
                                        }
                                    }
                                    conn.instanceFollowRedirects = true
                                    val responseCode = conn.responseCode
                                    val contentType = conn.contentType ?: ""
                                    val contentLength = conn.contentLengthLong

                                    val resMap = mapOf(
                                        "url" to urlStr,
                                        "statusCode" to responseCode,
                                        "contentType" to contentType,
                                        "contentLength" to contentLength,
                                        "isAccessible" to (responseCode in 200..299 || responseCode == 302 || responseCode == 301)
                                    )
                                    conn.disconnect()
                                    mainHandler.post { result.success(resMap) }
                                } catch (e: Exception) {
                                    mainHandler.post {
                                        result.success(
                                            mapOf(
                                                "url" to urlStr,
                                                "statusCode" to -1,
                                                "contentType" to "",
                                                "contentLength" to -1L,
                                                "isAccessible" to false,
                                                "error" to (e.message ?: "Network error")
                                            )
                                        )
                                    }
                                }
                            }
                        }

                        "getDeviceCapabilities" -> {
                            val runtime = Runtime.getRuntime()
                            val maxMemoryMb = runtime.maxMemory() / (1024 * 1024)
                            val availableProcessors = runtime.availableProcessors()
                            val capabilities = mapOf(
                                "maxMemoryMb" to maxMemoryMb,
                                "cores" to availableProcessors,
                                "sdkInt" to Build.VERSION.SDK_INT,
                                "model" to Build.MODEL,
                                "manufacturer" to Build.MANUFACTURER,
                                "supportsNnapi" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                            )
                            result.success(capabilities)
                        }

                        "getMonotonicUs" -> {
                            result.success(System.nanoTime() / 1000)
                        }

                        "reportObservedResource" -> {
                            val urlStr = call.argument<String>("url")
                            val mime = call.argument<String>("mimeType") ?: ""
                            if (!urlStr.isNullOrEmpty()) {
                                emitMediaEvent(
                                    mapOf(
                                        "url" to urlStr,
                                        "mimeType" to mime,
                                        "timestamp" to System.currentTimeMillis()
                                    )
                                )
                            }
                            result.success(true)
                        }

                        "updateAudioAnchor" -> {
                            val mediaPositionUs = call.argument<Long>("mediaPositionUs") ?: 0L
                            val anchorMonotonicUs = call.argument<Long>("anchorMonotonicUs") ?: 0L
                            val playbackRate = call.argument<Double>("playbackRate") ?: 1.0
                            val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                            val isBuffering = call.argument<Boolean>("isBuffering") ?: false
                            val timelineEpoch = call.argument<Int>("timelineEpoch") ?: 0
                            val playbackSessionId = call.argument<String>("playbackSessionId") ?: ""
                            val seekGeneration = call.argument<Int>("seekGeneration") ?: 0

                            AudioPcmBroker.updateAnchor(
                                mediaPositionUs,
                                anchorMonotonicUs,
                                playbackRate,
                                isPlaying,
                                isBuffering,
                                timelineEpoch,
                                playbackSessionId,
                                seekGeneration
                            )
                            result.success(true)
                        }

                        else -> result.notImplemented()
                    }
                }
            })
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_MEDIA_PROJECTION) {
            if (resultCode == RESULT_OK && data != null) {
                val intent = Intent(this, AudioCaptureService::class.java).apply {
                    action = AudioCaptureService.ACTION_START
                    putExtra(AudioCaptureService.EXTRA_RESULT_CODE, resultCode)
                    putExtra(AudioCaptureService.EXTRA_DATA, data)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
                pendingAudioResult?.success(true)
            } else {
                pendingAudioResult?.error("PERMISSION_DENIED", "MediaProjection permission denied", null)
            }
            pendingAudioResult = null
        } else {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}

class ObservingWebViewClient(
    private val onResource: (String) -> Unit,
) : WebViewClient() {
    private val mediaPatterns = listOf(".m3u8", ".mpd", ".mp4", ".webm", ".m4v")

    override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
        request?.url?.toString()?.let { url ->
            val isMedia = mediaPatterns.any { url.contains(it, ignoreCase = true) }
            if (isMedia || request.isForMainFrame) {
                onResource(url)
                MainActivity.emitMediaEvent(
                    mapOf(
                        "url" to url,
                        "method" to (request.method ?: "GET"),
                        "isForMainFrame" to request.isForMainFrame,
                        "timestamp" to System.currentTimeMillis()
                    )
                )
            }
        }
        return super.shouldInterceptRequest(view, request)
    }
}

```

## lib/features/source_resolver/data/android_media_observer.dart
```dart:lib/features/source_resolver/data/android_media_observer.dart
import 'dart:async';
import 'package:flutter/services.dart';

import 'media_candidate.dart';
import '../domain/entities/resolved_source.dart';

class AndroidMediaObserver {
  AndroidMediaObserver();

  static const _eventChannel = EventChannel(
    'local_ai_video_translator/media_events',
  );
  StreamSubscription<dynamic>? _subscription;
  final _candidateController = StreamController<MediaCandidate>.broadcast();

  Stream<MediaCandidate> get candidates => _candidateController.stream;

  void startObserving() {
    _subscription?.cancel();
    try {
      _subscription = _eventChannel.receiveBroadcastStream().listen(
        _onEvent,
        onError: (error) {
          // Event channel error ignored gracefully
        },
      );
    } catch (_) {
      // Platform channel not available in non-Android environment
    }
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final urlStr = event['url'] as String?;
    if (urlStr == null || urlStr.isEmpty) return;

    final uri = Uri.tryParse(urlStr);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return;

    final path = uri.path.toLowerCase();
    MediaKind? kind;
    if (path.endsWith('.m3u8')) {
      kind = MediaKind.hls;
    } else if (path.endsWith('.mpd')) {
      kind = MediaKind.dash;
    } else if (['.mp4', '.webm', '.mkv', '.m4v'].any(path.endsWith)) {
      kind = MediaKind.progressive;
    }

    if (kind != null) {
      _candidateController.add(
        MediaCandidate(
          uri: uri,
          kind: kind,
          method: DiscoveryMethod.runtime,
          score: 80,
        ),
      );
    }
  }

  void stopObserving() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stopObserving();
    _candidateController.close();
  }
}

```

## lib/features/source_resolver/data/candidate_verifier.dart
```dart:lib/features/source_resolver/data/candidate_verifier.dart
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../domain/entities/resolved_source.dart';
import 'media_candidate.dart';

class VerifiedCandidateResult {
  const VerifiedCandidateResult({
    required this.candidate,
    required this.isAccessible,
    required this.statusCode,
    required this.contentType,
    required this.contentLength,
    this.error,
  });

  final MediaCandidate candidate;
  final bool isAccessible;
  final int statusCode;
  final String contentType;
  final int contentLength;
  final String? error;
}

class CandidateVerifier {
  CandidateVerifier(this._dio);

  final Dio _dio;
  static const _nativeChannel = MethodChannel(
    'local_ai_video_translator/native_resolver',
  );

  Future<VerifiedCandidateResult> verify(
    MediaCandidate candidate, {
    Map<String, String>? headers,
  }) async {
    // Try native Android verification first
    try {
      final res = await _nativeChannel
          .invokeMethod<Map<dynamic, dynamic>>('verifyCandidate', {
            'url': candidate.uri.toString(),
            'headers': headers ?? <String, String>{},
          });
      if (res != null) {
        final isAccessible = res['isAccessible'] as bool? ?? false;
        final statusCode = res['statusCode'] as int? ?? -1;
        final contentType = res['contentType'] as String? ?? '';
        final contentLength = res['contentLength'] as int? ?? -1;
        final error = res['error'] as String?;

        final updatedKind =
            _detectKindFromContentType(contentType) ?? candidate.kind;
        final status = isAccessible
            ? CandidateValidationStatus.valid
            : (statusCode == 403 || statusCode == 401
                  ? CandidateValidationStatus.requiresEmbeddedSession
                  : CandidateValidationStatus.invalid);

        final updatedCandidate = candidate.copyWith(
          kind: updatedKind,
          score: isAccessible ? (candidate.score + 25) : candidate.score,
          validationStatus: status,
          statusCode: statusCode,
          contentType: contentType,
          contentLength: contentLength,
          rejectionReason: isAccessible ? null : error ?? 'HTTP $statusCode',
        );

        return VerifiedCandidateResult(
          candidate: updatedCandidate,
          isAccessible: isAccessible,
          statusCode: statusCode,
          contentType: contentType,
          contentLength: contentLength,
          error: error,
        );
      }
    } catch (_) {
      // Native channel fallback
    }

    return _verifyWithDio(candidate, headers: headers);
  }

  Future<VerifiedCandidateResult> _verifyWithDio(
    MediaCandidate candidate, {
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.head<void>(
        candidate.uri.toString(),
        options: Options(
          headers: headers,
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      final statusCode = response.statusCode ?? 200;
      final contentType = response.headers.value('content-type') ?? '';
      final contentLengthStr = response.headers.value('content-length');
      final contentLength = int.tryParse(contentLengthStr ?? '') ?? -1;

      final updatedKind =
          _detectKindFromContentType(contentType) ?? candidate.kind;

      final updatedCandidate = candidate.copyWith(
        kind: updatedKind,
        score: candidate.score + 20,
        validationStatus: CandidateValidationStatus.valid,
        statusCode: statusCode,
        contentType: contentType,
        contentLength: contentLength,
      );

      return VerifiedCandidateResult(
        candidate: updatedCandidate,
        isAccessible: true,
        statusCode: statusCode,
        contentType: contentType,
        contentLength: contentLength,
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode ?? -1;
      final status = (statusCode == 403 || statusCode == 401)
          ? CandidateValidationStatus.requiresEmbeddedSession
          : CandidateValidationStatus.invalid;

      final updatedCandidate = candidate.copyWith(
        validationStatus: status,
        statusCode: statusCode,
        contentType: '',
        contentLength: -1,
        rejectionReason: e.message ?? 'HTTP $statusCode',
      );

      return VerifiedCandidateResult(
        candidate: updatedCandidate,
        isAccessible: false,
        statusCode: statusCode,
        contentType: '',
        contentLength: -1,
        error: e.message,
      );
    }
  }

  MediaKind? _detectKindFromContentType(String contentType) {
    final lower = contentType.toLowerCase();
    if (lower.contains('mpegurl') || lower.contains('m3u8')) {
      return MediaKind.hls;
    }
    if (lower.contains('dash+xml')) {
      return MediaKind.dash;
    }
    if (lower.startsWith('video/')) {
      return MediaKind.progressive;
    }
    return null;
  }
}

```

## lib/features/source_resolver/data/html_media_parser.dart
```dart:lib/features/source_resolver/data/html_media_parser.dart
import '../domain/entities/resolved_source.dart';
import 'media_candidate.dart';

class ParsedHtmlMedia {
  const ParsedHtmlMedia({required this.candidates, required this.iframes});
  final List<MediaCandidate> candidates;
  final List<Uri> iframes;
}

class HtmlMediaParser {
  const HtmlMediaParser();

  ParsedHtmlMedia parse(String html, Uri baseUri) {
    final candidates = <MediaCandidate>[];
    final iframes = <Uri>[];

    // Refined regex for iframes to handle - and _ in attributes
    final iframeRx = RegExp(
      r'''<iframe[^>]+?src=["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in iframeRx.allMatches(html)) {
      final uriStr = match.group(1);
      if (uriStr != null) {
        final uri = _absolute(baseUri, uriStr);
        if (uri != null) {
          iframes.add(uri);
        }
      }
    }

    // Refined regex for common JS-embedded media sources
    final urlRx = RegExp(
      r'''(?:src|file|url|source|data-src)\s*[:=]\s*["']([^"']+\.(?:m3u8|mpd|mp4|webm|mkv)(?:\?[^"']*)?)["']''',
      caseSensitive: false,
    );
    for (final match in urlRx.allMatches(html)) {
      final uri = _absolute(baseUri, match.group(1));
      if (uri != null) {
        final kind = _kind(uri);
        if (kind != null) {
          candidates.add(
            MediaCandidate(
              uri: uri,
              kind: kind,
              method: DiscoveryMethod.htmlVideo,
              score: 60,
            ),
          );
        }
      }
    }

    // Direct URL discovery with support for escaped slashes and common video extensions
    final rawMediaRx = RegExp(
      r'''https?[:\\]+[^"'\s<>]+?\.(?:m3u8|mpd|mp4|webm|mkv)(?:\?[^"'\s<>]*)?''',
      caseSensitive: false,
    );
    for (final match in rawMediaRx.allMatches(html)) {
      final raw = match.group(0)?.replaceAll(r'\/', '/');
      final uri = raw == null ? null : Uri.tryParse(raw);
      if (uri != null) {
        final kind = _kind(uri);
        if (kind != null) {
          candidates.add(
            MediaCandidate(
              uri: uri,
              kind: kind,
              method: DiscoveryMethod.htmlVideo,
              score: 70,
            ),
          );
        }
      }
    }

    return ParsedHtmlMedia(
      candidates: _dedupe(candidates),
      iframes: iframes.toSet().toList(),
    );
  }

  Uri? _absolute(Uri base, String? raw) {
    if (raw == null ||
        raw.startsWith('blob:') ||
        raw.startsWith('javascript:')) {
      return null;
    }
    final normalized = raw.replaceAll('&amp;', '&').trim();
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      return null;
    }
    return uri.hasScheme ? uri : base.resolveUri(uri);
  }

  MediaKind? _kind(Uri uri) {
    final path = uri.path.toLowerCase();
    if (path.endsWith('.m3u8')) {
      return MediaKind.hls;
    }
    if (path.endsWith('.mpd')) {
      return MediaKind.dash;
    }
    if (['.mp4', '.webm', '.mkv', '.m4v'].any(path.endsWith)) {
      return MediaKind.progressive;
    }
    return null;
  }

  List<MediaCandidate> _dedupe(List<MediaCandidate> input) {
    final seen = <String>{};
    return input.where((item) => seen.add(item.uri.toString())).toList();
  }
}

```

## lib/features/source_resolver/data/media_candidate.dart
```dart:lib/features/source_resolver/data/media_candidate.dart
import '../domain/entities/resolved_source.dart';

enum CandidateValidationStatus {
  valid,
  invalid,
  requiresEmbeddedSession,
  unknown,
}

class MediaCandidate {
  const MediaCandidate({
    required this.uri,
    required this.kind,
    required this.method,
    this.score = 0,
    this.validationStatus = CandidateValidationStatus.unknown,
    this.statusCode = -1,
    this.contentType = '',
    this.contentLength = -1,
    this.rejectionReason,
  });

  final Uri uri;
  final MediaKind kind;
  final DiscoveryMethod method;
  final int score;
  final CandidateValidationStatus validationStatus;
  final int statusCode;
  final String contentType;
  final int contentLength;
  final String? rejectionReason;

  MediaCandidate copyWith({
    Uri? uri,
    MediaKind? kind,
    DiscoveryMethod? method,
    int? score,
    CandidateValidationStatus? validationStatus,
    int? statusCode,
    String? contentType,
    int? contentLength,
    String? rejectionReason,
  }) {
    return MediaCandidate(
      uri: uri ?? this.uri,
      kind: kind ?? this.kind,
      method: method ?? this.method,
      score: score ?? this.score,
      validationStatus: validationStatus ?? this.validationStatus,
      statusCode: statusCode ?? this.statusCode,
      contentType: contentType ?? this.contentType,
      contentLength: contentLength ?? this.contentLength,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }
}

```

## lib/features/source_resolver/data/source_resolver_repository_impl.dart
```dart:lib/features/source_resolver/data/source_resolver_repository_impl.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/cancellation_token.dart';
import '../../../core/utils/media_url.dart';
import '../domain/entities/resolved_source.dart';
import '../domain/repositories/source_resolver_repository.dart';
import 'candidate_verifier.dart';
import 'html_media_parser.dart';
import 'media_candidate.dart';

class SourceResolverRepositoryImpl implements SourceResolverRepository {
  SourceResolverRepositoryImpl(
    this._dio,
    this._parser, [
    CandidateVerifier? verifier,
  ]) : _verifier = verifier ?? CandidateVerifier(_dio);

  final Dio _dio;
  final HtmlMediaParser _parser;
  final CandidateVerifier _verifier;

  /// Limit for reading probe data (HTML/Manifests) to prevent OOM
  static const int _kMaxProbeBytes = 1 * 1024 * 1024; // 1 MB

  @override
  Future<ResolvedSource> resolve(String input, {CancellationToken? cancellationToken}) async {
    final stopwatch = Stopwatch()..start();
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const InvalidInputException('Video URL is empty.');
    }

    final normalized = _normalizeInput(trimmed);
    final diagnostics = <String>[];
    final rejectionReasons = <String, String>{};
    final cancelToken = CancelToken();

    cancellationToken?.addListener(() {
      cancelToken.cancel('User cancelled resolution');
    });

    // Initialize RequestContext with Referer and User-Agent based on the input URL
    final requestContext = RequestContext(
      userAgent: AppConstants.defaultUserAgent,
      referer: normalized.scheme.startsWith('http') ? normalized.toString() : null,
      headers: {
        'User-Agent': AppConstants.defaultUserAgent,
        if (normalized.scheme.startsWith('http')) 'Referer': normalized.toString(),
      },
    );

    try {
      final result = await _resolveInternal(
        normalized,
        originInput: trimmed,
        depth: 0,
        visited: <String>{},
        redirectChain: <Uri>[normalized],
        iframeChain: <Uri>[],
        diagnostics: diagnostics,
        rejectionReasons: rejectionReasons,
        stopwatch: stopwatch,
        cancelToken: cancelToken,
        requestContext: requestContext,
      );

      stopwatch.stop();
      return result;
    } catch (e) {
      cancelToken.cancel('Resolution failed or aborted');
      rethrow;
    }
  }

  Uri _normalizeInput(String input) {
    if (input.startsWith('/') ||
        input.startsWith('file://') ||
        input.startsWith('content://')) {
      return input.startsWith('/') ? Uri.file(input) : Uri.parse(input);
    }
    var value = input;
    if (!value.contains('://')) {
      value = 'https://$value';
    }
    return Uri.parse(value);
  }

  Future<ResolvedSource> _resolveInternal(
    Uri currentUri, {
    required String originInput,
    required int depth,
    required Set<String> visited,
    required List<Uri> redirectChain,
    required List<Uri> iframeChain,
    required List<String> diagnostics,
    required Map<String, String> rejectionReasons,
    required Stopwatch stopwatch,
    required CancelToken cancelToken,
    required RequestContext requestContext,
  }) async {
    if (depth > AppConstants.maxIframeDepth) {
      throw const ResolutionException('Maximum iframe depth reached.');
    }

    if (currentUri.scheme == 'file' || currentUri.scheme == 'content') {
      diagnostics.add('Local file resolved.');
      return ResolvedSource(
        input: originInput,
        normalizedUri: currentUri,
        finalUri: currentUri,
        kind: MediaKind.localFile,
        playbackMode: PlaybackMode.native,
        discoveryMethod: DiscoveryMethod.localFile,
        capability: SourceCapability.full,
        resolutionDuration: stopwatch.elapsed,
        diagnostics: diagnostics,
        requestContext: requestContext,
      );
    }

    // Step 1: Direct media URL classification
    final initialKind = _toMediaKind(MediaUrl.classify(currentUri.toString()));
    if (initialKind != null) {
      final directCandidate = MediaCandidate(
        uri: currentUri,
        kind: initialKind,
        method: DiscoveryMethod.input,
        score: 100,
      );
      final verified = await _verifier.verify(directCandidate, headers: requestContext.headers);
      if (verified.isAccessible) {
        diagnostics.add(
          'Direct media URL verified accessible (status=${verified.statusCode}, type=${verified.contentType}).',
        );
        return ResolvedSource(
          input: originInput,
          normalizedUri: currentUri,
          finalUri: verified.candidate.uri,
          kind: verified.candidate.kind,
          playbackMode: PlaybackMode.native,
          discoveryMethod: DiscoveryMethod.input,
          capability: SourceCapability.full,
          redirectChain: redirectChain,
          iframeChain: iframeChain,
          candidates: [verified.candidate],
          selectedCandidate: verified.candidate,
          resolutionDuration: stopwatch.elapsed,
          diagnostics: diagnostics,
          requestContext: requestContext,
        );
      } else {
        rejectionReasons[currentUri.toString()] =
            verified.error ?? 'Direct candidate inaccessible';
        diagnostics.add(
          'Direct candidate rejected: ${rejectionReasons[currentUri.toString()]}',
        );
      }
    }

    if (!visited.add(currentUri.toString())) {
      throw const ResolutionException('Iframe cycle detected.');
    }

    try {
      final probeResult = await _probe(currentUri, cancelToken, requestContext);
      final finalUri = probeResult.finalUri;
      if (finalUri != currentUri && !redirectChain.contains(finalUri)) {
        redirectChain.add(finalUri);
      }

      final contentType = probeResult.contentType;
      final body = probeResult.body;

      // Step 2: Response signature classification
      final byResponse = _detectResponse(finalUri, contentType, body);
      if (byResponse != null) {
        diagnostics.add(
          'Detected by HTTP response content-type/signature: $contentType',
        );
        final candidate = MediaCandidate(
          uri: finalUri,
          kind: byResponse,
          method: DiscoveryMethod.htmlVideo,
          score: 90,
          validationStatus: CandidateValidationStatus.valid,
        );
        return ResolvedSource(
          input: originInput,
          normalizedUri: currentUri,
          finalUri: finalUri,
          kind: byResponse,
          playbackMode: PlaybackMode.native,
          discoveryMethod: DiscoveryMethod.htmlVideo,
          capability: SourceCapability.full,
          redirectChain: redirectChain,
          iframeChain: iframeChain,
          candidates: [candidate],
          selectedCandidate: candidate,
          resolutionDuration: stopwatch.elapsed,
          diagnostics: diagnostics,
          requestContext: requestContext,
        );
      }

      if (body.isEmpty) {
        throw const ResolutionException('Empty response or non-HTML content.');
      }

      // Step 3: Static HTML inspection
      final parsed = _parser.parse(body, finalUri);
      final verifiedCandidates = <MediaCandidate>[];

      if (parsed.candidates.isNotEmpty) {
        final sorted = [...parsed.candidates]
          ..sort((a, b) => b.score.compareTo(a.score));
        for (final candidate in sorted) {
          final verification = await _verifier.verify(candidate, headers: requestContext.headers);
          verifiedCandidates.add(verification.candidate);
          if (verification.isAccessible) {
            diagnostics.add(
              'Static HTML candidate verified accessible score=${verification.candidate.score} status=${verification.statusCode}',
            );
            return ResolvedSource(
              input: originInput,
              normalizedUri: currentUri,
              finalUri: verification.candidate.uri,
              kind: verification.candidate.kind,
              playbackMode: PlaybackMode.native,
              discoveryMethod: candidate.method,
              capability: SourceCapability.full,
              redirectChain: redirectChain,
              iframeChain: iframeChain,
              candidates: verifiedCandidates,
              selectedCandidate: verification.candidate,
              resolutionDuration: stopwatch.elapsed,
              diagnostics: diagnostics,
              requestContext: requestContext,
            );
          } else {
            rejectionReasons[candidate.uri.toString()] =
                verification.error ?? 'HTTP ${verification.statusCode}';
          }
        }
      }

      // Step 4 & 5: Iframe discovery & recursion
      for (final iframe in parsed.iframes) {
        try {
          return await _resolveInternal(
            iframe,
            originInput: originInput,
            depth: depth + 1,
            visited: visited,
            redirectChain: redirectChain,
            iframeChain: [...iframeChain, iframe],
            diagnostics: diagnostics,
            rejectionReasons: rejectionReasons,
            stopwatch: stopwatch,
            cancelToken: cancelToken,
            requestContext: requestContext,
          );
        } on ResolutionException {
          // Continue to next iframe
        } catch (e) {
          // Continue to next iframe
        }
      }

      // Step 6: Fallback to Embedded WebView runtime observation mode
      final embeddedUri = parsed.iframes.isNotEmpty
          ? parsed.iframes.first
          : finalUri;
      diagnostics.add('No static accessible media candidate verified.');
      diagnostics.add(
        'Opened in embedded WebView fallback. Android runtime media observer active.',
      );

      return ResolvedSource(
        input: originInput,
        normalizedUri: currentUri,
        finalUri: embeddedUri,
        kind: MediaKind.embedded,
        playbackMode: PlaybackMode.embedded,
        discoveryMethod: parsed.iframes.isEmpty
            ? DiscoveryMethod.runtime
            : DiscoveryMethod.iframe,
        capability: SourceCapability.embedded,
        redirectChain: redirectChain,
        iframeChain: [
          ...iframeChain,
          if (parsed.iframes.isNotEmpty) embeddedUri,
        ],
        candidates: verifiedCandidates,
        resolutionDuration: stopwatch.elapsed,
        rejectionReasons: rejectionReasons,
        diagnostics: diagnostics,
        requestContext: requestContext,
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      throw ResolutionException('Could not load source page.', error);
    }
  }

  Future<({Uri finalUri, String contentType, String body})> _probe(
    Uri uri,
    CancelToken cancelToken,
    RequestContext requestContext,
  ) async {
    final response = await _dio.get<ResponseBody>(
      uri.toString(),
      options: Options(
        responseType: ResponseType.stream,
        headers: requestContext.headers,
      ),
      cancelToken: cancelToken,
    );

    final contentType =
        response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ?? '';
    final finalUri = response.realUri;

    // Check if it's likely a direct media stream
    final isMedia = contentType.startsWith('video/') ||
        contentType.contains('mpegurl') ||
        contentType.contains('dash+xml') ||
        contentType.contains('application/octet-stream');

    final isManifest = contentType.contains('mpegurl') || contentType.contains('dash+xml');

    if (isMedia && !isManifest) {
      // It's a video file, don't read body to avoid OOM
      return (finalUri: finalUri, contentType: contentType, body: '');
    }

    // Read limited body for HTML/Manifest parsing
    final builder = BytesBuilder(copy: false);
    int totalRead = 0;

    try {
      await for (final chunk in response.data!.stream) {
        builder.add(chunk);
        totalRead += chunk.length;
        if (totalRead >= _kMaxProbeBytes) {
          break;
        }
      }
    } catch (e) {
      // Partial read is better than nothing for probing
    }

    final bodyBytes = builder.takeBytes();
    final body = utf8.decode(bodyBytes, allowMalformed: true);

    return (
      finalUri: finalUri,
      contentType: contentType,
      body: body,
    );
  }


  MediaKind? _detectResponse(Uri uri, String contentType, String body) {
    final pathKind = _toMediaKind(MediaUrl.classify(uri.toString()));
    if (pathKind != null) {
      return pathKind;
    }
    final trimmedBody = body.trimLeft();
    if (contentType.contains('mpegurl') || trimmedBody.startsWith('#EXTM3U')) {
      return MediaKind.hls;
    }
    if (contentType.contains('dash+xml') ||
        trimmedBody.startsWith('<MPD') ||
        trimmedBody.contains('xmlns="urn:mpeg:dash:schema:mpd:2011"')) {
      return MediaKind.dash;
    }
    if (contentType.startsWith('video/')) {
      return MediaKind.progressive;
    }
    return null;
  }

  MediaKind? _toMediaKind(MediaUrlKind kind) => switch (kind) {
    MediaUrlKind.hls => MediaKind.hls,
    MediaUrlKind.dash => MediaKind.dash,
    MediaUrlKind.progressive => MediaKind.progressive,
    _ => null,
  };
}

```

## lib/features/source_resolver/domain/entities/resolved_source.dart
```dart:lib/features/source_resolver/domain/entities/resolved_source.dart
import '../../data/media_candidate.dart';

enum PlaybackMode { native, embedded }

enum MediaKind { hls, dash, progressive, localFile, embedded }

enum DiscoveryMethod { input, htmlVideo, iframe, runtime, localFile }

class SourceCapability {
  const SourceCapability({
    required this.nativePlayback,
    required this.embeddedPlayback,
    required this.seek,
    this.duration,
    required this.positionReadable,
    required this.pauseControllable,
    required this.seekControllable,
    required this.audioAccessible,
    required this.subtitleTracksAccessible,
    required this.aiLookahead,
    required this.dubbingPotential,
  });

  final bool nativePlayback;
  final bool embeddedPlayback;
  final bool seek;
  final Duration? duration;
  final bool positionReadable;
  final bool pauseControllable;
  final bool seekControllable;
  final bool audioAccessible;
  final bool subtitleTracksAccessible;
  final bool aiLookahead;
  final bool dubbingPotential;

  static const full = SourceCapability(
    nativePlayback: true,
    embeddedPlayback: true,
    seek: true,
    positionReadable: true,
    pauseControllable: true,
    seekControllable: true,
    audioAccessible: true,
    subtitleTracksAccessible: true,
    aiLookahead: true,
    dubbingPotential: true,
  );

  static const embedded = SourceCapability(
    nativePlayback: false,
    embeddedPlayback: true,
    seek: false,
    positionReadable: false,
    pauseControllable: true,
    seekControllable: false,
    audioAccessible: false,
    subtitleTracksAccessible: false,
    aiLookahead: false,
    dubbingPotential: false,
  );
}

class RequestContext {
  const RequestContext({
    required this.userAgent,
    this.referer,
    this.origin,
    this.headers = const {},
    this.cookies,
  });

  final String userAgent;
  final String? referer;
  final String? origin;
  final Map<String, String> headers;
  final String? cookies;

  static const defaultContext = RequestContext(
    userAgent: 'Mozilla/5.0 (Linux; Android 13) LocalAIVideoTranslator/1.0',
  );
}

class ResolvedSource {
  const ResolvedSource({
    required this.input,
    required this.normalizedUri,
    required this.finalUri,
    required this.kind,
    required this.playbackMode,
    required this.discoveryMethod,
    required this.capability,
    this.requestContext = RequestContext.defaultContext,
    this.redirectChain = const [],
    this.iframeChain = const [],
    this.candidates = const [],
    this.selectedCandidate,
    this.resolutionDuration = Duration.zero,
    this.failureReason,
    this.rejectionReasons = const {},
    this.diagnostics = const [],
    this.manualSubtitlePath,
  });

  final String input;
  final Uri normalizedUri;
  final Uri finalUri;
  final MediaKind kind;
  final PlaybackMode playbackMode;
  final DiscoveryMethod discoveryMethod;
  final SourceCapability capability;
  final RequestContext requestContext;
  final List<Uri> redirectChain;
  final List<Uri> iframeChain;
  final List<MediaCandidate> candidates;
  final MediaCandidate? selectedCandidate;
  final Duration resolutionDuration;
  final String? failureReason;
  final Map<String, String> rejectionReasons;
  final List<String> diagnostics;
  final String? manualSubtitlePath;

  Uri get uri => finalUri;
  Map<String, String> get headers => requestContext.headers;
  bool get supportsFullAi =>
      capability.audioAccessible && capability.positionReadable;

  ResolvedSource copyWith({
    String? input,
    Uri? normalizedUri,
    Uri? finalUri,
    MediaKind? kind,
    PlaybackMode? playbackMode,
    DiscoveryMethod? discoveryMethod,
    SourceCapability? capability,
    RequestContext? requestContext,
    List<Uri>? redirectChain,
    List<Uri>? iframeChain,
    List<MediaCandidate>? candidates,
    MediaCandidate? selectedCandidate,
    Duration? resolutionDuration,
    String? failureReason,
    Map<String, String>? rejectionReasons,
    List<String>? diagnostics,
    String? manualSubtitlePath,
  }) {
    return ResolvedSource(
      input: input ?? this.input,
      normalizedUri: normalizedUri ?? this.normalizedUri,
      finalUri: finalUri ?? this.finalUri,
      kind: kind ?? this.kind,
      playbackMode: playbackMode ?? this.playbackMode,
      discoveryMethod: discoveryMethod ?? this.discoveryMethod,
      capability: capability ?? this.capability,
      requestContext: requestContext ?? this.requestContext,
      redirectChain: redirectChain ?? this.redirectChain,
      iframeChain: iframeChain ?? this.iframeChain,
      candidates: candidates ?? this.candidates,
      selectedCandidate: selectedCandidate ?? this.selectedCandidate,
      resolutionDuration: resolutionDuration ?? this.resolutionDuration,
      failureReason: failureReason ?? this.failureReason,
      rejectionReasons: rejectionReasons ?? this.rejectionReasons,
      diagnostics: diagnostics ?? this.diagnostics,
      manualSubtitlePath: manualSubtitlePath ?? this.manualSubtitlePath,
    );
  }
}

```

## lib/features/source_resolver/domain/repositories/source_resolver_repository.dart
```dart:lib/features/source_resolver/domain/repositories/source_resolver_repository.dart
import '../../../core/utils/cancellation_token.dart';
import '../entities/resolved_source.dart';

abstract interface class SourceResolverRepository {
  Future<ResolvedSource> resolve(String input, {CancellationToken? cancellationToken});
}

```

## lib/features/source_resolver/domain/usecases/resolve_source.dart
```dart:lib/features/source_resolver/domain/usecases/resolve_source.dart
import '../../../core/utils/cancellation_token.dart';
import '../entities/resolved_source.dart';
import '../repositories/source_resolver_repository.dart';

class ResolveSource {
  const ResolveSource(this.repository);
  final SourceResolverRepository repository;

  Future<ResolvedSource> call(String input, {CancellationToken? cancellationToken}) =>
    repository.resolve(input, cancellationToken: cancellationToken);
}

```

## lib/features/source_resolver/presentation/source_analysis_page.dart
```dart:lib/features/source_resolver/presentation/source_analysis_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_components.dart';
import '../domain/entities/resolved_source.dart';
import 'source_resolver_controller.dart';

class SourceAnalysisPage extends ConsumerStatefulWidget {
  final String inputUrl;

  const SourceAnalysisPage({super.key, required this.inputUrl});

  @override
  ConsumerState<SourceAnalysisPage> createState() => _SourceAnalysisPageState();
}

class _SourceAnalysisPageState extends ConsumerState<SourceAnalysisPage> {
  int _currentStep = 0;
  ResolvedSource? _resolvedSource;
  bool _isFailed = false;

  @override
  void initState() {
    super.initState();
    _startAnalysis();
  }

  Future<void> _startAnalysis() async {
    try {
      // Step 1: Validating URL
      if (mounted) setState(() => _currentStep = 0);
      await Future.delayed(const Duration(milliseconds: 600));

      // Step 2: Extracting Media
      if (mounted) setState(() => _currentStep = 1);
      await Future.delayed(const Duration(milliseconds: 800));

      // Step 3: Verifying HTTP Candidates
      if (mounted) setState(() => _currentStep = 2);

      final resolved = await ref
          .read(sourceResolverControllerProvider.notifier)
          .resolve(widget.inputUrl);

      if (!mounted) return;

      if (resolved == null ||
          (resolved.failureReason != null && resolved.candidates.isEmpty)) {
        final uri =
            Uri.tryParse(widget.inputUrl) ??
            Uri.parse('https://example.com/video.m3u8');
        setState(() {
          _isFailed = true;
          _resolvedSource =
              resolved ??
              ResolvedSource(
                input: widget.inputUrl,
                normalizedUri: uri,
                finalUri: uri,
                kind: widget.inputUrl.contains('file_picker')
                    ? MediaKind.localFile
                    : MediaKind.hls,
                playbackMode: PlaybackMode.native,
                discoveryMethod: DiscoveryMethod.input,
                capability: SourceCapability.full,
              );
        });
        return;
      }

      setState(() {
        _currentStep = 3;
        _resolvedSource = resolved;
      });

      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() => _currentStep = 4);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isFailed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String formatText = 'HLS Adaptive Stream';
    String formatLabel = 'm3u8';
    String badgeLabel = 'HLS 1080p';

    if (_resolvedSource?.kind == MediaKind.localFile) {
      formatText = 'Local MP4/MKV Container';
      formatLabel = 'FILE';
      badgeLabel = 'LOCAL';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Phân tích Nguồn Video'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Target URL Header Card
            AppGlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ĐƯỜNG DẪN MỤC TIÊU',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryLight,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.inputUrl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Timeline Header
            const Text(
              'Tiến trình Phân tích & Xác minh Stream',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            // Step Timeline List
            AppGlassCard(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                children: [
                  StepTimelineTile(
                    title: '1. Kiểm tra URL & Phân tích Trang Web',
                    subtitle: 'Xác nhận giao thức https & quét iframe embed',
                    stepState: _getStepState(0),
                  ),
                  StepTimelineTile(
                    title: '2. Trích xuất Luồng Media Candidates',
                    subtitle: 'Phân lập URL HLS (.m3u8), DASH (.mpd) hoặc MP4',
                    stepState: _getStepState(1),
                  ),
                  StepTimelineTile(
                    title: '3. Xác thực HTTP HEAD & Băng thông Stream',
                    subtitle:
                        'Kiểm tra Content-Type, CORS & Byte Range Support',
                    stepState: _getStepState(2),
                  ),
                  StepTimelineTile(
                    title: '4. Khởi tạo Luồng Phát Trực tiếp',
                    subtitle: 'Sẵn sàng truyền sang Player & Bộ đệm AI',
                    stepState: _getStepState(3),
                    isLast: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Media Candidate Spec Card
            if (_currentStep >= 3) ...[
              AppGlassCard(
                padding: const EdgeInsets.all(20),
                borderColor: AppColors.primaryLight.withValues(alpha: 0.5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.verified_rounded,
                              color: AppColors.success,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Đã xác thực Luồng Stream',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        PillBadge(
                          label: badgeLabel,
                          backgroundColor: AppColors.primaryGlow,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSpecRow(
                      'Định dạng:',
                      _resolvedSource?.kind == MediaKind.hls
                          ? 'm3u8 (HLS Adaptive Stream)'
                          : _resolvedSource?.kind.name ?? 'Unknown',
                    ),
                    _buildSpecRow(
                      'Tiêu đề:',
                      _resolvedSource?.input.split(RegExp(r'[/\\]')).last ??
                          'Direct Stream Video',
                    ),
                    _buildSpecRow('Loại Stream:', '$formatLabel ($formatText)'),
                    if (_resolvedSource?.manualSubtitlePath != null)
                      _buildSpecRow(
                        'Phụ đề:',
                        'Tệp thủ công (${_resolvedSource!.manualSubtitlePath!.split(RegExp(r'[/\\]')).last})',
                      ),
                    _buildSpecRow(
                      'Khả năng AI:',
                      _resolvedSource?.supportsFullAi == true
                          ? 'Hỗ trợ đầy đủ (Audio + Seek)'
                          : 'Hạn chế (Chỉ phát lồng tiếng)',
                    ),
                    _buildSpecRow(
                      'Phương thức:',
                      _resolvedSource?.discoveryMethod.name ?? 'Auto',
                    ),
                    if (_resolvedSource?.requestContext.referer != null)
                      _buildSpecRow(
                        'Referer:',
                        _resolvedSource!.requestContext.referer!,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              GlowButton(
                label: 'Bắt đầu Phát & Dịch AI',
                icon: Icons.play_arrow_rounded,
                onPressed: () {
                  if (_resolvedSource != null) {
                    context.push('/player', extra: _resolvedSource);
                  }
                },
              ),
            ],
            if (_isFailed) ...[
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'Không thể phân tích nguồn video. Vui lòng kiểm tra lại URL.',
                  style: TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  AppStepState _getStepState(int stepIndex) {
    if (_currentStep > stepIndex) return AppStepState.completed;
    if (_currentStep == stepIndex) return AppStepState.active;
    return AppStepState.pending;
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

```

## lib/features/source_resolver/presentation/source_inspector_page.dart
```dart:lib/features/source_resolver/presentation/source_inspector_page.dart
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

```

## lib/features/source_resolver/presentation/source_resolver_controller.dart
```dart:lib/features/source_resolver/presentation/source_resolver_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_provider.dart';
import '../../../core/utils/cancellation_token.dart';
import '../data/html_media_parser.dart';
import '../data/source_resolver_repository_impl.dart';
import '../domain/entities/resolved_source.dart';
import '../domain/repositories/source_resolver_repository.dart';
import '../domain/usecases/resolve_source.dart';

final sourceResolverRepositoryProvider = Provider<SourceResolverRepository>((
  ref,
) {
  return SourceResolverRepositoryImpl(
    ref.watch(dioProvider),
    const HtmlMediaParser(),
  );
});

final resolveSourceProvider = Provider<ResolveSource>(
  (ref) => ResolveSource(ref.watch(sourceResolverRepositoryProvider)),
);

final sourceResolverControllerProvider =
    AsyncNotifierProvider<SourceResolverController, ResolvedSource?>(
      SourceResolverController.new,
    );

class SourceResolverController extends AsyncNotifier<ResolvedSource?> {
  @override
  Future<ResolvedSource?> build() async {
    ref.onDispose(() {
      _activeDioCancelToken?.cancel('Controller disposed');
    });
    return null;
  }

  String? _manualSubtitlePath;
  int _requestGeneration = 0;
  CancelToken? _activeDioCancelToken;
  CancellationToken? _activeDomainToken;

  Future<ResolvedSource?> resolve(String input) async {
    final generation = ++_requestGeneration;
    _activeDioCancelToken?.cancel('New resolution started');
    _activeDioCancelToken = CancelToken();
    _activeDomainToken?.cancel();
    _activeDomainToken = CancellationToken();

    state = const AsyncLoading();

    try {
      final result = await ref.read(resolveSourceProvider)(
        input,
        cancellationToken: _activeDomainToken,
      );

      if (generation != _requestGeneration) {
        return state.value;
      }

      if (result != null && _manualSubtitlePath != null) {
        state = AsyncData(result.copyWith(manualSubtitlePath: _manualSubtitlePath));
      } else {
        state = AsyncData(result);
      }
    } catch (e, st) {
      if (generation != _requestGeneration) {
        return state.value;
      }
      state = AsyncError(e, st);
    }

    return state.value;
  }

  void reset() {
    _manualSubtitlePath = null;
    state = const AsyncData(null);
  }

  void setManualSubtitle(String path) {
    _manualSubtitlePath = path;
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(manualSubtitlePath: path));
    }
  }
}

```

