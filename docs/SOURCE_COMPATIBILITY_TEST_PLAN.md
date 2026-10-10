# Source Compatibility Test Plan & Matrix

## Overview

This test plan defines the testing strategy, test fixtures, and capability evaluation matrix for Phase 1: Production-Grade Source Compatibility Inspector in **Local AI Video Translator Player**.

All tests are offline-ready and rely on deterministic local HTML/HTTP fixtures to prevent dependence on external or third-party web servers.

---

## Capability Matrix Definition

| Capability | Description | Native Mode | Embedded Mode |
| :--- | :--- | :--- | :--- |
| `nativePlayback` | Playable directly via `media_kit` native backend | `true` | `false` |
| `embeddedPlayback` | Playable via WebView embedded player | `true` | `true` |
| `seekControllable` | Seeking to specific timestamps supported | `true` | Conditional |
| `positionReadable` | Current PTS position readable in real-time | `true` | Conditional |
| `audioAccessible` | PCM audio stream accessible for STT/VAD | `true` | Requires MediaProjection |
| `subtitleTracksAccessible` | Subtitle playlists/tracks extractable | `true` | Partial |
| `aiLookahead` | AI processing can run ahead of playback position | `true` | Limited |
| `dubbingPotential` | Voice-over audio synthesis ducking allowed | `true` | Limited |

---

## Test Cases Matrix

### 1. Direct Media URLs

| Test ID | Input URL | Expected Kind | Expected Playback Mode | Validation Result |
| :--- | :--- | :--- | :--- | :--- |
| `TC-DIR-01` | `https://cdn.movie.org/master.m3u8` | `hls` | `native` | `VALID` |
| `TC-DIR-02` | `https://cdn.movie.org/manifest.mpd` | `dash` | `native` | `VALID` |
| `TC-DIR-03` | `https://cdn.movie.org/episode.mp4` | `progressive` | `native` | `VALID` |
| `TC-DIR-04` | `/sdcard/Movies/anime.mkv` | `localFile` | `native` | `VALID` |

### 2. Static HTML Inspection

| Test ID | HTML Fixture | Expected Discovery | Expected Candidate |
| :--- | :--- | :--- | :--- |
| `TC-HTM-01` | `<video src="/media/720p.mp4">` | `htmlVideo` | `https://example.com/media/720p.mp4` |
| `TC-HTM-02` | `<source src="https://cdn.com/stream.m3u8">` | `htmlVideo` | `https://cdn.com/stream.m3u8` |
| `TC-HTM-03` | `{"file":"https:\/\/cdn.com\/v.m3u8"}` | `htmlVideo` | `https://cdn.com/v.m3u8` |

### 3. Iframe Chain & Recursion

| Test ID | Scenario | Expected Outcome |
| :--- | :--- | :--- |
| `TC-IFR-01` | Relative iframe `<iframe src="/embed/p1">` | Resolves absolute `https://example.com/embed/p1` |
| `TC-IFR-02` | Duplicate iframes on page | Deduplicated into single entry in `iframeChain` |
| `TC-IFR-03` | Self-referencing or cyclic iframe `A -> B -> A` | Cycle detected, `ResolutionException('Iframe cycle detected.')` thrown |
| `TC-IFR-04` | Iframe depth = 5 (> MAX_IFRAME_DEPTH = 4) | Max depth reached, stops recursion gracefully |

### 4. Response Signature Classification

| Test ID | Response Headers & Body | Classifications |
| :--- | :--- | :--- |
| `TC-SIG-01` | `Content-Type: application/x-mpegURL`, body starts `#EXTM3U` | `hls` |
| `TC-SIG-02` | `Content-Type: application/dash+xml`, body contains `<MPD` | `dash` |
| `TC-SIG-03` | `Content-Type: video/mp4` | `progressive` |

### 5. Candidate Verification & Rejection

| Test ID | HTTP Status | Response Header | Verification Status | Action |
| :--- | :--- | :--- | :--- | :--- |
| `TC-VER-01` | 200 OK | `video/mp4` | `VALID` | Migrate to Native Player |
| `TC-VER-02` | 206 Partial Content | `application/x-mpegURL` | `VALID` | Migrate to Native Player |
| `TC-VER-03` | 403 Forbidden | `text/html` | `REQUIRES_EMBEDDED_SESSION` | Retain in Embedded WebView |
| `TC-VER-04` | 404 Not Found | None | `INVALID` | Reject candidate, record rejection log |

---

## Execution Verification

Run all tests via command line:

```bash
flutter analyze
flutter test
```

Expected output:
- Zero linter errors or warnings.
- All unit test assertions passing successfully.
