# Phase 2 Completion Report: Native Playback Hardening and MediaSession Abstraction

## Executive Summary

Phase 2 successfully transitions native media playback from basic streaming into a robust, observable, and enterprise-grade **MediaSession** subsystem. Designed for seamless interoperability with the upcoming local AI translation pipeline, this phase introduces a unified state-machine abstraction, fine-grained track models for audio and subtitles, explicit request context isolation, safe two-phase native migration from WebView, and comprehensive playback diagnostics.

---

## Key Components Implemented

### 1. Domain-Level MediaSession Abstraction
- **`MediaSession` Interface (`lib/features/player/domain/services/media_session.dart`)**:
  - Exposes state as a reactive stream (`snapshotStream`) and property getter (`currentSnapshot`) rather than polling UI widgets.
  - Core control contracts: `open(ResolvedSource source)`, `play()`, `pause()`, `seek(Duration position)`, `setPlaybackRate(double rate)`, `selectVideoTrack()`, `selectAudioTrack()`, `selectSubtitleTrack()`, and `close()`.
- **`NativeMediaSession` Implementation (`lib/features/player/data/native_media_session.dart`)**:
  - Powered by `media_kit` under the hood.
  - Synchronizes position, duration, buffered range, playback state, rates, tracks, and errors into `MediaSessionSnapshot`.

### 2. Independent Track Model & Multiple Audio Support
- **Entities (`lib/features/player/domain/entities/media_track.dart`)**:
  - `VideoTrack`: Captures `id`, `label`, `language`, `width`, `height`, `bitrate`, `codec`, `isSelected`.
  - `AudioTrack`: Captures `id`, `label`, `language`, `channels`, `sampleRate`, `codec`, `isSelected`, `isDefault`. Supports multiple audio streams without assuming the first track is dialogue (e.g., separating commentary, multi-language dubs, or background audio).
  - `PlayerSubtitleTrack`: Captures `id`, `label`, `language`, `format`, `uri`, `isEmbedded`, `isSelected`, and `classification`.

### 3. Subtitle Discovery & Classification
- Automatically enumerates embedded and manifest-derived subtitle tracks.
- Classifies subtitle language strings into three semantic categories:
  - `SubtitleClassification.vietnamese`: `vi`, `vietnamese`, `vie`.
  - `SubtitleClassification.sourceLanguage`: `en`, `english`, `ja`, `japanese`, `zh`, `chinese`.
  - `SubtitleClassification.unknownOther`: Any other language or fallback.
- Exposes metadata to the AI pipeline without premature translation.

### 4. Isolated Request Context Propagation
- **`RequestContext` (`lib/features/source_resolver/domain/entities/resolved_source.dart`)**:
  - Preserves legitimate request headers required by protected or authenticated streams (`User-Agent`, `Referer`, `Origin`, cookies/session auth tokens).
  - Passed directly to native HTTP client requests (`media_kit` headers) to prevent 403 Forbidden or session timeout errors.
  - Strictly isolated per session to prevent session state or auth tokens leaking between unrelated media streams.

### 5. Player State Machine & Explicit Error Models
- **`PlayerStatus` (`lib/features/player/domain/entities/player_state.dart`)**:
  - `idle`, `initializing`, `ready`, `playing`, `paused`, `buffering`, `seeking`, `ended`, `error`.
- **Structured Error Hierarchy (`PlayerError`)**:
  - `PlaybackInitializationException`
  - `MediaFormatUnsupportedException`
  - `NetworkStreamException`
  - `NativePlayerBackendException`

### 6. Safe Two-Phase Native Migration
- **`NativeMigrationController` (`lib/features/player/data/migration_controller.dart`)**:
  - Enforces strict safety barriers when transitioning from an embedded WebView session to native playback:
    1. **Embedded**: Initial playback running inside WebView.
    2. **Validating Candidate**: Verifies candidate URI accessibility via `CandidateVerifier` (HTTP HEAD/GET).
    3. **Preparing Native**: Opens and buffers native `NativeMediaSession` in the background *while keeping the WebView running* (preventing black screens or interruption).
    4. **Native Ready**: Confirms player is successfully prepared.
    5. **Position Capture**: Captures current playback position from the active source.
    6. **Switch Playback**: Seeks native player to the captured position and switches UI.
    7. **Cleanup**: Disposes WebView.
  - **Fallback Guarantee**: If native preparation or verification fails at any stage, the app cleanly reverts and remains in embedded WebView mode without crashing.

### 7. Comprehensive Diagnostics & Telemetry
- **`PlayerDiagnostics` (`lib/features/player/data/player_diagnostics.dart`)**:
  - Measures prepare duration, buffer event count, current position, buffered position, selected tracks, media type, and migration results.
  - Prepares forward-looking telemetry hooks for dropped-frame counts, decoder info (hardware/software acceleration), and real-time bandwidth estimation.

---

## Testing & Verification

- Unit tests (`test/media_session_test.dart`, `test/track_model_test.dart`) validate:
  - Snapshot initial state and `copyWith` state transformations.
  - Request context isolation between independent sessions.
  - Subtitle track classification rules (`vi`, `en`, `ja`, etc.).
  - Multi-audio track model independence.
- Offline-first unit test architecture ensuring no external network dependency.

---

## Summary of Completed Requirements

| Requirement | Status | Implementation File |
| :--- | :--- | :--- |
| **1. MediaSession Abstraction** | Completed | `media_session.dart`, `native_media_session.dart` |
| **2. Independent Track Model** | Completed | `media_track.dart` |
| **3. Subtitle Discovery & Classification** | Completed | `media_track.dart`, `native_media_session.dart` |
| **4. Request Context & Isolation** | Completed | `resolved_source.dart`, `native_media_session.dart` |
| **5. Player State & Error Models** | Completed | `player_state.dart`, `native_media_session.dart` |
| **6. Safe Native Migration** | Completed | `migration_controller.dart`, `embedded_player_view.dart` |
| **7. Diagnostics & Telemetry** | Completed | `player_diagnostics.dart` |
| **8. Testing & Documentation** | Completed | `media_session_test.dart`, `track_model_test.dart`, `PHASE_2_REPORT.md` |
