# Local STT Benchmarking & Performance Guide

## Overview

This guide explains how local on-device Speech-to-Text (STT) inference is measured, benchmarked, and tuned for mobile performance across Android devices.

---

## Key Performance Metrics

1. **Model Load Duration (`modelLoadDuration`)**:
   - Time required to initialize the ONNX/Whisper model runtime into memory.
2. **Peak Memory Consumption (`peakMemoryBytes`)**:
   - Total RAM consumed during model inference and audio buffering.
3. **Audio Duration (`audioDuration`)**:
   - Total length of the VAD speech audio segment being transcribed.
4. **Inference Duration (`inferenceDuration`)**:
   - Wall-clock time taken by the local STT engine to generate transcript segments.
5. **Realtime Factor (`realtimeFactor` or `RTF`)**:
   $$\text{RTF} = \frac{\text{Inference Duration}}{\text{Audio Duration}}$$
   - **RTF < 1.0**: Processing faster than real-time (ideal for live subtitle lookahead).
   - **RTF = 1.0**: Processing exactly at real-time speed.
   - **RTF > 1.0**: Processing slower than real-time (triggers Eco/Turbo scheduler adaptation).

---

## Device Capability Profiling

The `DeviceCapabilityProfile` evaluates hardware constraints:
- **Memory Class**: Devices with `< 1536 MB` RAM are flagged as `isLowMemoryDevice` and automatically enter a fallback quality tier.
- **Hardware Acceleration**: Prioritizes `NNAPI` / `GPU` delegates over CPU fallback when available.
- **Thermal Status**: Monitors thermal throttling (`nominal`, `fair`, `serious`, `critical`) to dynamically throttle AI scheduling and protect device battery.

---

## Best Practices for Local Inference

1. **Never Block UI**: All audio extraction, VAD segmentation, and STT inference run on asynchronous worker threads.
2. **Job Cancellation on Seek**: Whenever a user scrubs the timeline (seek), active STT jobs are immediately cancelled via `CancellationToken` to avoid wasted compute cycles on obsolete video segments.
3. **Context Overlap**: Speech windows preserve slight context overlap across VAD boundaries to maintain natural sentence boundary continuity.
