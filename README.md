# Local AI Video Translator Player

Android-first Flutter player for long-form movies, anime, and drama episodes with on-device Vietnamese AI translation.

> Share a supported long-form video URL or file and watch it in Vietnamese.

## What is real in this source

- **Production-Grade Source Compatibility Inspector**:
  - Direct media URL classification & normalization.
  - Response content-type and signature detection (`#EXTM3U`, `<MPD`, `video/*`).
  - Static HTML parser for `<video>`, `<source>`, and script configurations with unescaping.
  - Recursive iframe discovery with `MAX_IFRAME_DEPTH` protection and cycle detection.
  - Candidate verification via HTTP HEAD/GET checks (`VALID`, `INVALID`, `REQUIRES_EMBEDDED_SESSION`, `UNKNOWN`).
  - Expanded `ResolvedSource`, `RequestContext`, and `SourceCapability` models.
- **Android Native Runtime WebView Observer**:
  - Native Kotlin request observer in `MainActivity.kt` capturing HTTP/HTTPS media resources.
  - Filters root playlists/manifests while discarding transport stream chunks (`.ts`, `.m4s`).
  - Bi-directional platform bridge via MethodChannel and EventChannel.
- **Developer-Facing Compatibility Inspector UI**:
  - Displays input/normalized/final URLs, redirect chain, iframe chain.
  - Displays candidate list with confidence score, discovery method, and validation results.
  - Complete capability matrix & failure/rejection diagnostics.
  - One-tap "Copy Diagnostic Text" feature for troubleshooting source pages.
- **Synchronized AI Pipeline & Timeline Buffer**:
  - Subtitle priority pipeline (Existing VI -> Foreign Subtitle Translation -> Local STT + Translation).
  - Media presentation timestamp (PTS) timeline buffer with auto-pause/refill mechanism.
  - High-contrast `SubtitleOverlay` rendering active Vietnamese cues on video.
  - On-device AI Model Manager supporting STT (Whisper), Translation (Opus-MT), TTS (Piper), and VAD (Silero).

## Safety / scope boundary

This project is for media the user is permitted to access. It intentionally contains no DRM bypass, paywall bypass, credential theft, token circumvention, or protected-stream decryption.

## Toolchain baseline

- Flutter stable 3.41+ / Dart 3.11+ baseline.
- Android minSdk 24.
- JDK 17.
- Android-first. iOS is a later product phase.

## Run

From the project root:

```bash
flutter pub get
dart format .
flutter analyze
flutter test
flutter run
```

## Documentation

- [`docs/ARCHITECTURE.md`](file:///C:/Users/projects/local_ai_video_translator/docs/ARCHITECTURE.md) - System invariants & component design.
- [`docs/ROADMAP.md`](file:///C:/Users/projects/local_ai_video_translator/docs/ROADMAP.md) - Phase execution roadmap.
- [`docs/PHASE_1_REPORT.md`](file:///C:/Users/projects/local_ai_video_translator/docs/PHASE_1_REPORT.md) - Phase 1 completion report.
- [`docs/SOURCE_COMPATIBILITY_TEST_PLAN.md`](file:///C:/Users/projects/local_ai_video_translator/docs/SOURCE_COMPATIBILITY_TEST_PLAN.md) - Source inspection testing plan & matrix.
