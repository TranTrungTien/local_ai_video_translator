# Architecture

## Product invariants

1. Long-form movie/anime/drama first.
2. Vietnamese target first.
3. Existing target subtitle wins. Existing source-language subtitle is translated before STT is considered.
4. STT, translation and TTS are intended to run on-device after model download.
5. Video continues to stream from the origin. The full movie is not required before playback.
6. Startup delay is acceptable to build an AI-ready buffer.
7. During viewing, untranslated playback is not acceptable. If the subtitle buffer is exhausted, playback deliberately waits.
8. Subtitle is core. Voice-over is premium and lower priority.
9. Native playback is preferred. Embedded WebView is a fallback.
10. No DRM/paywall/access-control bypass.

## Resolution state machine

```text
INPUT
  -> direct media? -> native
  -> HTTP page
      -> response itself media? -> native
      -> static video/media URL? -> native candidate
      -> iframe? -> recurse
      -> otherwise -> embedded WebView runtime mode
```

Static resolution is deliberately conservative. A URL ending in a media extension is only a candidate in production. Verification should prepare the native player and confirm segment access before destroying the WebView.

## Runtime WebView resolution

Dart-side JS observation is useful for same-frame DOM/fetch/XHR/performance resources but cannot be treated as a universal cross-origin iframe inspector. The Android extension point in `MainActivity.kt` exists so the compatibility PoC can move resource observation closer to the platform WebView.

## Playback modes

### Native

Full capability target: precise media position, seek, audio, subtitle tracks, AI lookahead and voice-over scheduling.

### Embedded

WebView keeps the original player. AI capabilities are conditional on audio and timeline access. Android playback-audio capture requires explicit system permission and can still be denied by the source app/player.

## AI selection path

```text
Vietnamese subtitle exists? -> use
else source subtitle exists? -> local translate
else accessible audio -> PCM+PTS -> VAD -> STT -> local translate
```

## AI buffer policy

Separate network playback buffer from AI-ready buffers. Never make model inference part of the media transport path.

- Initial subtitle target: configurable, default 45s.
- Normal target lookahead: configurable, default 2m.
- Low buffer: turbo AI work.
- Large buffer: throttle/pause AI work for thermal/battery reasons.
- Exhausted subtitles: pause playback and refill.
- Seek: cancel/reprioritize obsolete jobs around the new media PTS.

## Audio timeline invariant

All future PCM chunks must carry media presentation timestamps. Do not synchronize subtitle/dub against wall clock time.

## Premium dubbing

V1 premium uses sentence-chunk voice-over, not source separation or lip sync. Original audio can be ducked beneath generated Vietnamese speech. Each generated chunk is attached to media PTS and persisted independently.
