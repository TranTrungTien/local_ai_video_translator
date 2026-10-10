import 'dart:async';

enum AudioCaptureState { idle, requestingConsent, active, denied, error }

class EmbeddedAudioCaptureManager {
  AudioCaptureState _state = AudioCaptureState.idle;
  final _stateController = StreamController<AudioCaptureState>.broadcast();

  AudioCaptureState get state => _state;
  Stream<AudioCaptureState> get stateStream => _stateController.stream;

  /// Requests explicit user consent for Android playback audio capture (MediaProjection / AudioPlaybackCapture).
  /// Never invoked on app startup; only on explicit user request after native migration failure.
  Future<bool> requestConsentAndStartCapture() async {
    _updateState(AudioCaptureState.requestingConsent);

    try {
      // Simulate Android MediaProjection / AudioPlaybackCapture consent flow
      await Future<void>.delayed(const Duration(milliseconds: 600));

      // In production Android, this invokes MediaProjectionManager.createScreenCaptureIntent()
      // and AudioPlaybackCaptureConfiguration.
      _updateState(AudioCaptureState.active);
      return true;
    } catch (_) {
      _updateState(AudioCaptureState.denied);
      return false;
    }
  }

  void stopCapture() {
    _updateState(AudioCaptureState.idle);
  }

  void _updateState(AudioCaptureState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  void dispose() {
    _stateController.close();
  }
}
