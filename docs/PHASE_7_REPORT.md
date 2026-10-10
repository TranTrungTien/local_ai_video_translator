# Phase 7 Completion Report: AI Scheduler and Guaranteed Subtitle Buffer

## Executive Summary

Phase 7 establishes the core architectural cornerstone of the application: the **Guaranteed Subtitle Buffer AI Scheduler**. This phase guarantees that once viewing commences, video playback never outruns required Vietnamese subtitles. If the translated subtitle buffer becomes exhausted, playback pauses automatically to refill the AI buffer and resumes seamlessly without displaying untranslated content.

---

## Key Components Implemented

### 1. Independent Buffer Model
- **Buffers (`lib/features/pipeline/domain/buffer_policy.dart`)**:
  - `NetworkPlaybackBuffer`: Tracks progressive/HLS/DASH network buffering progress.
  - `SubtitleReadyBuffer`: Tracks translated subtitle availability (`subtitleReadyUntil`, `subtitleAhead`).
  - `DubReadyBuffer`: Tracks AI voice-over speech synthesis progress (`dubReadyUntil`, `dubAhead`).
  - Completely decouples network download buffering from AI translation lookahead buffering.

### 2. Dynamic Startup Threshold
- Calculates startup wait time dynamically based on device capability tier (`DeviceCapabilityProfile`), measured STT RTF, translation throughput, and playback rate.
- Fast devices require a smaller initial wait, while resource-constrained devices safely buffer a larger initial safety window.

### 3. Work Mode State Machine (`BLOCKED`, `TURBO`, `NORMAL`, `ECO`, `PAUSED`)
- **Transitions (`AiBufferPolicy`)**:
  - **`BLOCKED`**: No subtitle ahead (`subtitleAhead <= 0`). Pauses playback immediately.
  - **`TURBO`**: Low lookahead buffer. Maximizes AI concurrency to catch up.
  - **`NORMAL`**: Below target lookahead. Standard processing mode.
  - **`ECO`**: Healthy lookahead buffer. Throttles background processing to conserve battery and thermal budget.
  - **`PAUSED`**: Very large lookahead buffer (ahead > 5 minutes). Suspends background AI tasks.

### 4. Centralized Playback Gate
- **`PlaybackGate` (`lib/features/pipeline/domain/playback_gate.dart`)**:
  - Centralizes media progression decisions. Eliminates scattered `if (missing) player.pause()` checks across widgets by evaluating buffer snapshots and playback rate in a single authority.

### 5. High-Priority Seek Handling
- On user seek operations:
  - Immediately cancels obsolete low-priority lookahead tasks.
  - Flushes outdated timeline buffer entries.
  - Re-evaluates buffer state around the new target presentation timestamp (PTS) and resumes guaranteed playback.

### 6. Playback Rate Scaling
- Fully integrates `playbackRate` (e.g., at 1.5x playback, subtitle consumption velocity is 1.5x, scaling required lookahead thresholds accordingly).

### 7. Task Priority Tiers (P0 to P5)
- **Priority Queue (`TaskPriorityQueue`)**:
  - **P0**: Playback-critical work.
  - **P1**: Currently needed subtitle.
  - **P2**: Next subtitle window.
  - **P3**: Target lookahead.
  - **P4**: Dubbing / voice-over.
  - **P5**: Distant cache / refinement.

### 8. Device Pressure Adaptation & Safety Guarantee
- Monitors thermal, memory, and RTF metrics.
- Under device pressure, background lookahead and dubbing are deprioritized to guarantee playback smoothness.
- **Absolute Guarantee**: If the subtitle buffer reaches zero, the scheduler intentionally pauses playback rather than displaying untranslated foreign video.

---

## Testing & Verification

- **State-Machine Tests (`test/ai_scheduler_test.dart`)**:
  - Validates dynamic startup threshold calculations.
  - Tests work mode transitions (`BLOCKED`, `TURBO`, `NORMAL`, `ECO`, `PAUSED`).
  - Verifies `PlaybackGate` decision making under buffer exhaustion and healthy states.
- Offline-first unit test architecture running without external network dependencies.

---

## Summary of Completed Requirements

| Requirement | Status | Implementation File |
| :--- | :--- | :--- |
| **1. Independent Buffer Model** | Completed | `buffer_policy.dart` |
| **2. Dynamic Startup Threshold** | Completed | `buffer_policy.dart` |
| **3. Work Mode State Machine** | Completed | `buffer_policy.dart`, `ai_scheduler_test.dart` |
| **4. Centralized Playback Gate** | Completed | `playback_gate.dart` |
| **5. High-Priority Seek Handling**| Completed | `ai_scheduler_controller.dart`, `task_priority_queue.dart` |
| **6. Playback Rate Scaling** | Completed | `buffer_policy.dart`, `playback_gate.dart` |
| **7. Task Priority Tiers (P0-P5)** | Completed | `task_priority_queue.dart` |
| **8. Device Pressure & Safety** | Completed | `buffer_policy.dart`, `playback_gate.dart` |
| **9. Unit Tests & Documentation** | Completed | `ai_scheduler_test.dart`, `PHASE_7_REPORT.md` |
