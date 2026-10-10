# Implementation Roadmap

## Phase 0 - Foundation (included)

Project structure, Riverpod, routing, network client, source model, playback backends, AI contracts, buffer policy, tests.

## Phase 1 - Source Compatibility Inspector

- Move Android runtime source observation into a dedicated native component.
- Capture redirect/iframe/candidate diagnostics.
- Verify candidates rather than trusting URL extension.
- Test 30-50 representative movie/anime/drama sources.
- Emit capability matrix: native, seek, audio, timing, lookahead.

Go/no-go metric: percentage of target sources reaching Native or Embedded-AI capability.

## Phase 2 - Native playback hardening

- Track enumeration.
- HTTP header/request-context propagation.
- HLS/DASH/progressive/local seek and resume.
- Player diagnostics, buffer health, dropped frames.

## Phase 3 - Audio + subtitle extraction

- Prefer existing Vietnamese subtitles.
- Translate existing source-language subtitle tracks before STT.
- PCM + PTS tap for audio where supported.
- VAD interface implementation.

## Phase 4 - Local subtitle AI

- Benchmark candidate mobile STT engines/models.
- Benchmark Vietnamese translation models.
- Device capability profile.
- Rolling context translation.
- Subtitle-ready queue.

## Phase 5 - Scheduler and cache

- Realtime-factor tracking.
- Dynamic startup threshold.
- Turbo/normal/eco/paused modes.
- Seek reprioritization.
- Thermal/battery/memory adaptation.
- Transcript/subtitle/media fingerprint persistence.

## Phase 6 - Embedded AI fallback

- Explicit MediaProjection consent.
- AudioPlaybackCapture when allowed.
- Embedded timeline/pause/seek capability probing.
- Subtitle overlay.

## Phase 7 - Premium voice-over

- Local Vietnamese TTS model pack.
- Sentence duration fitting.
- Chunk cache.
- Original audio ducking.
- Later: diarization/source separation as separate experiments.
