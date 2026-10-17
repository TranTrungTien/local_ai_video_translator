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

  RequestContext copyWith({
    String? userAgent,
    String? referer,
    String? origin,
    Map<String, String>? headers,
    String? cookies,
  }) {
    return RequestContext(
      userAgent: userAgent ?? this.userAgent,
      referer: referer ?? this.referer,
      origin: origin ?? this.origin,
      headers: headers ?? this.headers,
      cookies: cookies ?? this.cookies,
    );
  }
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
