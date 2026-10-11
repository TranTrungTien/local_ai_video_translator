import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exception.dart';
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
  Future<ResolvedSource> resolve(String input) async {
    final stopwatch = Stopwatch()..start();
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const InvalidInputException('Video URL is empty.');
    }

    final normalized = _normalizeInput(trimmed);
    final diagnostics = <String>[];
    final rejectionReasons = <String, String>{};
    final cancelToken = CancelToken();

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
