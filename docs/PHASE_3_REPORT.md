# Phase 3 Completion Report: Existing Subtitle Pipeline

## Executive Summary

Phase 3 establishes a robust **Existing Subtitle Pipeline** that inspects, extracts, parses, and evaluates pre-existing subtitle and text tracks prior to invoking any resource-intensive Speech-to-Text (STT) inference. By prioritizing direct Vietnamese subtitles and foreign subtitle translation over raw audio STT, the pipeline minimizes latency and preserves translation accuracy.

---

## Key Components Implemented

### 1. Normalized Subtitle Domain Models
- **`SubtitleSegment` & `SubtitleDocument` (`lib/features/subtitles/domain/entities/subtitle_document.dart`)**:
  - Provides a standardized domain structure capturing `id`, `start` (Duration), `end` (Duration), `text`, `language`, `source`, and `confidence`.
  - Aggregates timed text segments into unified `SubtitleDocument` instances across various container formats.

### 2. Multi-Format Subtitle Parsers
- **`SubtitleParser` (`lib/features/subtitles/data/subtitle_parser.dart`)**:
  - **WebVTT & SRT Parsers**: Fully support timecode expressions (`HH:MM:SS,mmm`), HTML tag stripping (e.g., `<b>`, `<i>`, `<font>`), multiline captions, empty lines, and comment blocks.
  - **TTML Parser**: Extracts XML-based `<p begin="..." end="...">` timed text entries commonly found in DASH manifests.
  - **Robustness Features**:
    - Gracefully handles overlapping captions by sorting segments by start PTS.
    - Recovers from malformed timestamp entries without crashing playback or pipeline execution.
    - Preserves Unicode UTF-8 and Vietnamese diacritics (`ă, â, đ, ê, ô, ơ, ư, ạ, ả, ấ, ầ, ẩ, ẫ, ặ...`).

### 3. Language Detection & Metadata Analysis
- **`SubtitleLanguageDetector` (`lib/features/subtitles/data/subtitle_language_detector.dart`)**:
  - Inspects manifest declarations (`lang="vi"`, `LANGUAGE="en"`) and track titles.
  - Implements a text-language heuristic fallback analyzing Vietnamese diacritic frequency when metadata is missing or ambiguous.

### 4. Subtitle Selection Policy
- **`SubtitleSelectionPolicy` (`lib/features/subtitles/domain/subtitle_selection_policy.dart`)**:
  - Evaluates discovered tracks and returns an explicit decision:
    1. **`DIRECT_VI`**: Vietnamese subtitle found -> used directly without translation or STT.
    2. **`TRANSLATE_EXISTING`**: Foreign/source-language subtitle found -> queued for local neural machine translation.
    3. **`STT_REQUIRED`**: No useful subtitle tracks -> triggers Audio -> VAD -> Local STT pipeline.

### 5. Media Position Timeline Synchronization
- Subtitles are buffered in `TimelineSubtitleBuffer` and indexed against media position (`Duration`).
- Responds correctly to pause, resume, seek backward, seek forward, and buffering events without scheduling against the system wall-clock.

### 6. UI Status Integration
- **`AiBufferPanel` (`lib/features/pipeline/presentation/ai_buffer_panel.dart`)**:
  - Displays the active subtitle strategy, lookahead progress, work mode badge (`NORMAL`, `TURBO`, `ECO`, `BLOCKED`, `PAUSED`), and priority tier indicators (`Priority 1: Existing VI -> Priority 2: Translate -> Priority 3: STT`).

---

## Testing & Verification

- **Unit Tests (`test/subtitle_pipeline_test.dart`)**:
  - Validates WebVTT and TTML document parsing with multiline and Unicode content.
  - Tests malformed timestamp recovery.
  - Verifies language detection heuristics and diacritic recognition.
  - Validates `SubtitleSelectionPolicy` decision trees (`DIRECT_VI`, `TRANSLATE_EXISTING`, `STT_REQUIRED`).
- Offline-first unit test suite running entirely without external network dependencies.

---

## Summary of Completed Requirements

| Requirement | Status | Implementation File |
| :--- | :--- | :--- |
| **1. Normalized Subtitle Model** | Completed | `subtitle_document.dart` |
| **2. Robust Multi-Format Parsers** | Completed | `subtitle_parser.dart` |
| **3. Language Detection Fallback** | Completed | `subtitle_language_detector.dart` |
| **4. Subtitle Selection Policy** | Completed | `subtitle_selection_policy.dart` |
| **5. Timeline Position Sync** | Completed | `timeline_subtitle_buffer.dart` |
| **6. UI Strategy Indicators** | Completed | `ai_buffer_panel.dart` |
| **7. Unit Tests & Documentation** | Completed | `subtitle_pipeline_test.dart`, `PHASE_3_REPORT.md` |
