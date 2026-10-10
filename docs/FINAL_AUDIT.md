# Final Architecture and Regression Audit

## Executive Summary

This production-readiness audit examines the entire repository structure, data flows, AI pipelines, player session backends, caching repositories, security boundaries, and telemetry exporters across all 12 implementation phases.

---

## 1. Major Flow Audit

1. **Source Ingestion & Resolution**:
   - **Share URL / Paste URL / Local File** -> Normalization -> Resolver -> Static HTML & Iframe recursive scraping -> Runtime WebView resource observation -> Verified Candidate (`CandidateVerifier`) -> Native vs Embedded decision.
2. **Subtitle Priority & Extraction**:
   - **Existing Vietnamese Subtitle** -> Used directly (`DIRECT_VI`).
   - **Existing Foreign Subtitle** -> Parsed (WebVTT/SRT/TTML) -> Translated locally to Vietnamese (`TRANSLATE_EXISTING`).
   - **No Subtitle** -> PCM Audio + Media Presentation Timestamps (PTS) extraction -> VAD segmentation (merge-small-gap & min duration) -> Local STT transcription -> Neural machine translation (`STT_REQUIRED`).
3. **Guaranteed AI Scheduler & Playback Gate**:
   - Dynamic startup threshold factoring in device capability tier, STT RTF, translation throughput, and playback rate.
   - Work mode state machine (`BLOCKED`, `TURBO`, `NORMAL`, `ECO`, `PAUSED`).
   - `PlaybackGate` centralizes pause/resume decisions, guaranteeing video never outruns Vietnamese subtitles.
   - High-priority seek handling flushes obsolete timeline entries and cancels stale tasks.
4. **Persistent Cache & Media Identity**:
   - Layered fingerprinting (`MediaIdentity`) robust to ephemeral CDN token rotation.
   - Version-aware cache invalidation (`CacheInvalidationPolicy`).
   - Bounded local repository (`AiCacheRepository`) with automatic LRU eviction.
5. **Embedded Fallback & Premium Voice-Over**:
   - Independent capability probing (`EmbeddedCapabilityProbe`).
   - Explicit user consent UX for Android playback-audio capture (never on startup).
   - Premium Piper local Vietnamese TTS with duration fitting and voice-over ducking.

---

## 2. Issue Classification

### Critical Issues Found
- **None.** All critical safety invariants (guaranteed subtitle buffer pause, request context isolation, and SHA-256 model verification) are fully enforced.

### High Issues Found
- **Memory Pressure Accumulation during Long Endurance Sessions**: Unbounded growth risk if cache eviction or PCM queue backpressure failed.
  - *Resolution*: Implemented `BoundedPcmQueue` backpressure eviction and `AiCacheRepository` LRU storage bounding.

### Medium Issues Found
- **CDN Token Expiration**: Ephemeral query parameters causing cache misses on valid media sessions.
  - *Resolution*: Implemented layered `MediaIdentity` fingerprinting that strips signed query parameters while preserving core path and stream metadata.

### Low Issues Found
- **Verbose Error Logging**: Raw exception stack traces potentially surfacing in logs or UI.
  - *Resolution*: Implemented `UserFriendlyError` mapping and `DiagnosticsExporter` sensitive data redaction.

---

## 3. Resolved Issues

1. **StreamSubscription Leaks**: Secured via `ref.onDispose` cleanup and explicit subscription cancellation in player states.
2. **Seek Race Conditions**: High-priority seek transition cancels obsolete background tasks and flushes obsolete timeline buffers.
3. **Wall-clock vs Media PTS**: All subtitle and audio processing strictly anchored to media presentation timestamps (`PTS`).
4. **Unbounded Caches**: Implemented LRU eviction and capacity bounds across PCM streaming queues and persistent record repositories.

---

## 4. Remaining Risks

1. **Device-Specific ONNX Hardware Delegation**: Performance variance across older Mali/Adreno GPU/NNAPI accelerators requires fallback to multi-threaded CPU execution.
2. **Protected DRM Streams**: Encrypted EME/DRM streams correctly retain embedded WebView fallback mode, where subtitle overlay relies on audio capture consent.

---

## 5. Release Blockers
- **None.** All release blockers identified in earlier phases have been successfully resolved and tested.

---

## 6. Recommended Device Test Matrix

| Tier | Representative Devices | Target Resolution | Expected AI Work Mode |
| :--- | :--- | :--- | :--- |
| **Lite** | Moto G Series, Entry-level Android Go (<2GB RAM) | 720p | ECO / NORMAL (Throttled Lookahead) |
| **Balanced** | Mid-range Samsung Galaxy A Series, Pixel 6a (4GB RAM) | 1080p | NORMAL / TURBO |
| **Performance** | Pixel 7/8/9, Galaxy S Series (8GB+ RAM) | 1080p | TURBO / ECO (Full Acceleration) |

---

## Readiness Classification

### **BETA READY**

### Explanation of Classification
The application has successfully completed all 12 implementation phases, encompassing source compatibility inspection, hardened native media sessions, multi-format subtitle parsing, PTS-bound audio extraction, VAD, local STT, neural machine translation, guaranteed subtitle buffer scheduling, persistent version-aware caching, secure embedded fallbacks, local TTS dubbing, thermal/memory device tier adaptation, and production hardening. The codebase is thoroughly unit-tested, secure against credential leakage, resilient to network and playback failures, and ready for Beta distribution and real-world device evaluation.
