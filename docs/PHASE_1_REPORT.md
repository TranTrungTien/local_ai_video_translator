# Phase 1 Completion Report: Production-Grade Source Compatibility Inspector

## Executive Summary

Phase 1 delivers a production-grade **Source Compatibility Inspector** for long-form video sources (movies, anime, drama/TV episodes). The system analyzes direct media links, static HTML pages, recursive iframes, and dynamic WebView network streams before candidate selection or AI pipeline activation. Candidates are verified via HTTP accessibility checks, ensuring native playback migration occurs only for playable media streams.

---

## Files Added

1. `lib/core/diagnostics/diagnostics_service.dart`: Subsystem logger and diagnostic event broadcaster.
2. `lib/core/utils/sha256_util.dart`: File integrity hash calculator for AI model manifests.
3. `lib/features/source_resolver/data/candidate_verifier.dart`: HTTP HEAD/GET candidate accessibility verifier supporting `valid`, `invalid`, `requiresEmbeddedSession`, and `unknown` status.
4. `lib/features/source_resolver/data/android_media_observer.dart`: Flutter stream listener for Android native WebView resource events.
5. `lib/features/source_resolver/presentation/source_inspector_page.dart`: Developer-facing Inspector screen with capability breakdown and copyable diagnostic reports.
6. `lib/features/subtitles/domain/entities/subtitle_track.dart`: Subtitle track entity (`webvtt`, `srt`, `hlsSegment`).
7. `lib/features/subtitles/data/subtitle_parser.dart`: WebVTT and SRT caption parsers with timestamp parsing and formatting cleanup.
8. `lib/features/subtitles/data/subtitle_repository_impl.dart`: HLS and local sidecar subtitle track extractor.
9. `lib/features/audio/domain/entities/audio_stream_info.dart`: Audio metadata container.
10. `lib/features/audio/data/pcm_audio_extractor.dart`: Media presentation timestamp (PTS) PCM chunk generator.
11. `lib/features/audio/data/vad_engine.dart`: RMS energy-based Voice Activity Detection engine.
12. `lib/features/settings/data/model_manager_repository.dart`: Local AI model download manager with SHA-256 verification and file management.
13. `lib/features/settings/presentation/model_manager_page.dart`: UI for downloading, tracking, and deleting STT/Translation/TTS/VAD models.
14. `lib/features/pipeline/data/local_stt_engine.dart`: Local Whisper STT adapter.
15. `lib/features/pipeline/data/local_translation_engine.dart`: Local Opus-MT rolling-context translation engine.
16. `lib/features/pipeline/data/local_tts_engine.dart`: Local Piper TTS synthesis engine.
17. `lib/features/pipeline/domain/timeline_subtitle_buffer.dart`: Thread-safe ordered PTS subtitle cue buffer.
18. `lib/features/player/presentation/subtitle_overlay.dart`: Synchronized high-contrast Vietnamese subtitle overlay.
19. `test/source_compatibility_test.dart`: Unit tests for URL classification, static HTML parsing, response signatures, iframe deduplication, and cycle detection.
20. `test/subtitle_parser_test.dart`: Unit tests for WebVTT and SRT parsers.
21. `test/candidate_verifier_test.dart`: Unit tests for candidate data structures.
22. `test/model_manager_test.dart`: Unit tests for AI model manifests.
23. `docs/PHASE_1_REPORT.md`: This completion report.
24. `docs/SOURCE_COMPATIBILITY_TEST_PLAN.md`: Source testing strategy and capability matrix.

---

## Files Modified

1. `android/app/src/main/kotlin/com/example/local_ai_video_translator/MainActivity.kt`: Expanded with `NATIVE_RESOLVER_CHANNEL` and `MEDIA_EVENTS_CHANNEL` for candidate verification and HTTP request interception.
2. `lib/features/source_resolver/domain/entities/resolved_source.dart`: Expanded with `normalizedUri`, `finalUri`, `redirectChain`, `requestContext`, `candidates`, `resolutionDuration`, `rejectionReasons`, and fine-grained `SourceCapability`.
3. `lib/features/source_resolver/data/media_candidate.dart`: Added `validationStatus`, `statusCode`, `contentType`, `contentLength`, and `rejectionReason`.
4. `lib/features/source_resolver/data/source_resolver_repository_impl.dart`: Integrated URL normalization, candidate verification, response signature detection (`#EXTM3U`, `<MPD`), stopwatch timing, and rejection logging.
5. `lib/features/pipeline/presentation/ai_scheduler_controller.dart`: Integrated subtitle priority resolution (Existing VI -> Foreign Subtitle Translation -> Local STT) and timeline buffer synchronization.
6. `lib/features/pipeline/presentation/ai_buffer_panel.dart`: Updated UI with strategy indicator, work mode badge, and lookahead progress bar.
7. `lib/features/player/presentation/native_player_view.dart`: Integrated video position stream, `SubtitleOverlay`, and auto-pause buffer refill mechanism.
8. `lib/features/player/presentation/embedded_player_view.dart`: Integrated Android media observer, JS channel, and `SubtitleOverlay`.
9. `lib/features/player/presentation/player_page.dart`: Added Source Inspector app bar button.
10. `lib/features/home/presentation/home_page.dart`: Updated entry screen with AI model manager navigation and refined scope card.
11. `lib/app/router/app_router.dart`: Added `/models` route.
12. `pubspec.yaml`: Added `crypto: ^3.0.3` dependency and updated version constraints.

---

## Architecture Decisions

1. **Progressive Resolution Pipeline**:
   The resolver follows a strict priority chain:
   `Direct URL -> HTTP Response Signature -> Static HTML Video Tags -> Escaped Script Configs -> Recursive Iframe -> Android WebView Runtime Observer`.

2. **Candidate Verification Before Native Migration**:
   A `.m3u8` or `.mpd` link discovered in HTML or JavaScript is never trusted blindly. It is verified using `CandidateVerifier` via HTTP HEAD/GET requests with the appropriate request context (User-Agent, Referer). Only `VALID` candidates initiate native player migration; otherwise, the app remains in embedded WebView mode.

3. **Separation of Platform and UI Layer**:
   Android WebView request observation is decoupled from the UI layer via `EventChannel` and `AndroidMediaObserver`, ensuring Flutter isolates handle domain model creation without UI coupling.

4. **Detailed Compatibility Breakdown**:
   Replaced binary `isCompatible` flags with fine-grained boolean fields in `SourceCapability` (`nativePlayback`, `embeddedPlayback`, `seekControllable`, `positionReadable`, `audioAccessible`, `subtitleTracksAccessible`, `aiLookahead`, `dubbingPotential`).

---

## Completed Functionality

- [x] Input normalization for URLs, relative paths, and local files.
- [x] HLS (`#EXTM3U`), DASH (`<MPD`), and Progressive (`video/*`) response classification.
- [x] Static HTML parsing for `<video>`, `<source>`, and escaped script URLs (`\/`).
- [x] Recursive iframe resolution respecting `MAX_IFRAME_DEPTH` with visited tracking and cycle prevention.
- [x] Android native WebView resource request interception.
- [x] Candidate verification with status codes, content-types, and rejection logging.
- [x] Comprehensive Source Compatibility Inspector screen with copy/export diagnostic text functionality.
- [x] Local unit tests with deterministic fixtures.

---

## Known Limitations

1. **Protected DRM / Token Streams**:
   Protected streams requiring dynamic token renewal or EME/DRM encryption are recognized as `requiresEmbeddedSession` and retained in WebView fallback mode, respecting safety bounds.
2. **User Play Interaction**:
   Websites that load media source links only after user click interaction rely on the embedded WebView runtime observer. Once the user clicks play on the page, the observer captures the resource and updates candidates.

---

## Tests Performed

All tests executed cleanly with zero failures and zero linter issues:

```text
flutter analyze -> No issues found!
flutter test    -> 20 tests passed!
```

- `test/source_compatibility_test.dart`
- `test/subtitle_parser_test.dart`
- `test/candidate_verifier_test.dart`
- `test/model_manager_test.dart`
- `test/buffer_policy_test.dart`
- `test/media_url_test.dart`
- `test/widget_test.dart`

---

## Recommended Next Steps (Phase 2)

1. Hardening native HLS/DASH header propagation (`User-Agent`, `Referer`, `Cookie`) in `media_kit`.
2. Extracting embedded HLS subtitle tracks from verified `.m3u8` manifests.
3. Native PCM audio tap integration for local video playback.
