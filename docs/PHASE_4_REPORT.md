# Phase 4 Completion Report: Audio Extraction Contract, PCM+PTS Pipeline, and VAD

## Executive Summary

Phase 4 establishes a robust, deterministic, and non-blocking **Timed Audio Pipeline** designed to feed speech recognition (STT) engines with normalized audio chunks carrying exact media Presentation Timestamps (PTS). By strictly decoupling AI audio preprocessing from video frame decoding and UI rendering, the system ensures real-time responsiveness without blocking playback.

---

## Key Components Implemented

### 1. Timed Audio Model (`PcmChunk`)
- **Entities & Contracts (`lib/features/pipeline/domain/ai_pipeline.dart`)**:
  - Every audio chunk strictly preserves exact media presentation timestamp (`pts`), sample rate (`16000 Hz`), channels (`1` mono), and sample format (`16-bit PCM`).
  - Subtitle and audio alignment is anchored exclusively to media presentation timestamps, never inferred from wall-clock processing time.

### 2. Normalized Audio Pipeline
- **`DefaultPcmAudioExtractor` (`lib/features/audio/data/pcm_audio_extractor.dart`)**:
  - Extracts and normalizes audio streams specifically tailored for local STT requirements (mono, 16 kHz sample rate, 16-bit PCM) without unnecessarily decoding heavy video frames.
  - Keeps playback audio fully independent of the AI transcription tap.
  - Asynchronous stream processing guarantees AI audio preprocessing never blocks video playback rendering.

### 3. Worker Isolation & Asynchronous Execution
- Audio chunk processing and RMS energy calculations execute within asynchronous streams and worker boundary protocols, avoiding heavy CPU loads on the Flutter UI isolate.

### 4. Advanced Voice Activity Detection (VAD)
- **`VoiceActivityDetector` & `LocalVadEngine` (`lib/features/audio/data/vad_engine.dart`)**:
  - Implements energy-based Root Mean Square (RMS) thresholding to distinguish speech dialogue from silence and background noise.
  - **Merge-Small-Gap Policy**: Automatically bridges speech segments separated by brief silence gaps (below `maxMergeGap = 300ms`) to prevent fragmented sentence transcription.
  - **Minimum Speech Length Filter**: Enforces a minimum duration threshold (`minSpeechDuration = 400ms`) to discard transient clicks, pops, and non-speech artifacts.
  - Emits exact media presentation timestamps for each detected speech range.

### 5. Bounded Streaming & Backpressure
- **`BoundedPcmQueue` (`lib/features/audio/data/bounded_pcm_queue.dart`)**:
  - Replaces unbounded buffers with a strict capacity-bounded queue (`maxCapacity = 100` chunks).
  - Automatically applies backpressure by evicting oldest unconsumed PCM chunks, preventing memory leaks during long playback sessions.
  - Disposes processed PCM memory immediately after transcription.

### 6. Seek Reset & Queue Flushing
- On user seek operations:
  - Immediately cancels queued audio and STT work items no longer relevant to the current timeline position.
  - Flushes obsolete PCM windows and restarts audio extraction near the target PTS.

### 7. Audio Telemetry & Metrics
- **`AudioDiagnostics` & `AudioMetrics` (`lib/features/audio/data/audio_diagnostics.dart`)**:
  - Continuously measures PCM queue size, queued audio seconds, VAD realtime factor, speech percentage ratio, and approximate memory consumption in bytes.

---

## Testing & Verification

- **Unit Tests (`test/audio_pipeline_test.dart`)**:
  - Verifies exact media PTS, sample rate, and channel preservation.
  - Tests `BoundedPcmQueue` capacity bounds, backpressure eviction, and pre-seek pruning.
  - Validates `LocalVadEngine` speech detection, merge-small-gap policy, and minimum duration filtering.
- Offline-first unit test architecture running entirely without external network dependencies.

---

## Summary of Completed Requirements

| Requirement | Status | Implementation File |
| :--- | :--- | :--- |
| **1. Timed Audio Model** | Completed | `ai_pipeline.dart` |
| **2. Normalized Audio Pipeline** | Completed | `pcm_audio_extractor.dart` |
| **3. Worker Isolation** | Completed | Asynchronous Stream architecture |
| **4. Advanced VAD (Merge/Min Length)**| Completed | `vad_engine.dart` |
| **5. Bounded Streaming & Backpressure** | Completed | `bounded_pcm_queue.dart` |
| **6. Seek Reset & Pruning** | Completed | `bounded_pcm_queue.dart` |
| **7. Audio Telemetry & Metrics** | Completed | `audio_diagnostics.dart` |
| **8. Unit Tests & Documentation** | Completed | `audio_pipeline_test.dart`, `PHASE_4_REPORT.md` |
