# Phase 9 Completion Report: Embedded Player AI Fallback for Android

## Executive Summary

Phase 9 establishes a secure, capability-gated **Embedded Player AI Fallback** for Android web-based or protected media sources when native media migration is unavailable. Rather than crashing or attempting risky cross-origin DOM injections, the system performs independent capability probing, requires explicit user action for Android playback audio capture (MediaProjection / AudioPlaybackCapture), and gracefully degrades when audio or timeline synchronization cannot be verified.

---

## Key Components Implemented

### 1. Independent Capability Probing
- **`EmbeddedCapabilityProbe` (`lib/features/player/domain/embedded_capability.dart`)**:
  - Independently probes embedded web player features: `canPlay`, `canPause`, `canReadPosition`, `canObserveSeek`, and `canAccessAudio`.
  - Ensures Embedded AI subtitles are never activated unless required capabilities are actually verified and available.

### 2. Secure Audio Playback Capture
- **`EmbeddedAudioCaptureManager` (`lib/features/player/data/embedded_audio_capture.dart`)**:
  - Integrates Android playback-audio capture (`AudioPlaybackCapture` / `MediaProjection`) through supported platform APIs.
  - **Requirements Enforced**:
    - Explicit user action required (user must tap "Enable AI Subtitles").
    - Clear UI explanation provided.
    - Immediate handling of permission denial.
    - Proper lifecycle cleanup (`dispose()`).
  - Degrades gracefully if capture is unavailable without faking silence.

### 3. Timeline Synchronization & Handling
- Maps captured audio streams to actual embedded media presentation positions.
- Correctly handles pause, resume, buffering, and seek events. If reliable synchronization cannot be established, AI subtitles are disabled for that source, honoring correctness over pretending to support unsupported pages.

### 4. Non-Intrusive Subtitle Overlay
- Renders Vietnamese subtitles over/around the embedded WebView player (`SubtitleOverlay`) without relying on brittle cross-origin DOM modifications.

### 5. Permission UX & Startup Protection
- **Strict Rule Enforced**: Playback capture permissions and consent dialogs are **never** requested on app startup.
- They are requested **only** when:
  1. Native mode migration has failed.
  2. The user explicitly requests AI subtitles by tapping the action button.
  3. Embedded audio access is required.

---

## Testing & Verification

- Validated capability probe states and explicit consent flows within `EmbeddedPlayerView` (`lib/features/player/presentation/embedded_player_view.dart`).
- Verified offline-first compliance and clean lifecycle cleanup on widget disposal.

---

## Summary of Completed Requirements

| Requirement | Status | Implementation File |
| :--- | :--- | :--- |
| **1. Capability Probe** | Completed | `embedded_capability.dart` |
| **2. Audio Playback Capture & Consent** | Completed | `embedded_audio_capture.dart` |
| **3. Timeline Mapping & Sync** | Completed | `embedded_player_view.dart` |
| **4. Subtitle Overlay** | Completed | `subtitle_overlay.dart` |
| **5. Permission UX (No Startup Prompts)** | Completed | `embedded_player_view.dart` |
| **6. Documentation & Report** | Completed | `PHASE_9_REPORT.md` |
