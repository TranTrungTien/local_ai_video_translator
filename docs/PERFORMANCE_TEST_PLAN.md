# Performance & Long-Run Test Plan

## Overview

This test plan defines the testing procedures for evaluating 1080p long-form video playback combined with local Vietnamese subtitle translation over extended viewing sessions (30, 60, and 120 minutes).

---

## Test Durations & Monitoring Procedures

1. **30-Minute Short Session**:
   - Focus: Initial cache warmup, memory stabilization, and STT RTF baseline.
2. **60-Minute Standard Session**:
   - Focus: Thermal state throttling, battery drain rate, and buffer stability.
3. **120-Minute Endurance Session**:
   - Focus: Memory leak detection, garbage collection efficiency, isolate cleanup, and subtitle synchronization drift.

---

## Key Metrics to Monitor

- **Memory Growth**: Peak RAM consumption must remain bounded without continuous upward leakage.
- **Thermal State**: Monitoring thermal transitions (`nominal` -> `fair` -> `serious`) to verify AI lookahead throttling.
- **Battery & Charging**: Current drain rate and charging state adaptation.
- **AI Buffer Stability**: Ensuring `subtitleAhead` remains above danger thresholds.
- **Video & Subtitle Sync**: Zero drift between media presentation timestamps (`PTS`) and rendered subtitle cues.
