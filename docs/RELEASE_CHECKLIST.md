# Release Checklist

## Pre-Release Verification

- [x] **Source Compatibility**: Verified direct links, HLS, DASH, and local files through the Source Compatibility Inspector.
- [x] **Native Playback & MediaSession**: Hardened native playback backends with explicit state machines and request context isolation.
- [x] **Subtitle Pipeline**: Multi-format parsing (WebVTT, SRT, TTML), language detection fallback, and `SubtitleSelectionPolicy`.
- [x] **Audio Extraction & VAD**: PTS-bound PCM extraction, worker isolation, and advanced VAD with merge-small-gap policy.
- [x] **Local STT & Benchmarking**: ONNX/Whisper local STT adapter, model manager with SHA-256 validation, and RTF measurement.
- [x] **Local Vietnamese Translation**: Opus-MT neural translation, rolling context windows, translation cache, and subtitle compression.
- [x] **Guaranteed Subtitle Buffer Scheduler**: Playback gate, work mode state machine (`BLOCKED`, `TURBO`, `NORMAL`, `ECO`, `PAUSED`), and priority queue (P0–P5).
- [x] **Persistent AI Cache & Media Identity**: Layered fingerprinting robust to CDN token rotation, version invalidation, and bounded storage LRU cleanup.
- [x] **Embedded Fallback**: Secure capability probing and explicit user audio capture consent UX.
- [x] **Premium Voice-Over (TTS)**: Piper Vietnamese voice synthesis, duration fitting, ducking mix, and feature entitlements.
- [x] **Performance & Device Tiers**: Lite, Balanced, and Performance capability adaptation and long-run test plans.
- [x] **Production Hardening**: WebView security audit, user-friendly error UX, recovery flows, and privacy-safe diagnostics export.
- [x] **Documentation**: Complete milestone reports (Phases 1–12), benchmark guides, and test plans.
