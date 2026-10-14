import 'dart:async';
import 'package:flutter/services.dart';

enum AudioCaptureState { idle, requestingConsent, active, denied, error }

class EmbeddedAudioCaptureManager {
  AudioCaptureState _state = AudioCaptureState.idle;
  final _stateController = StreamController<AudioCaptureState>.broadcast();
  static const _methodChannel = MethodChannel('local_ai_video_translator/native_resolver');

  AudioCaptureState get state => _state;
  Stream<AudioCaptureState> get stateStream => _stateController.stream;

  /// Requests explicit user consent for Android playback audio capture (MediaProjection / AudioPlaybackCapture).
  /// Never invoked on app startup; only on explicit user request after native migration failure.
  Future<bool> requestConsentAndStartCapture() async {
    if (_state == AudioCaptureState.active) return true;

    _updateState(AudioCaptureState.requestingConsent);

    try {
      final bool? started = await _methodChannel.invokeMethod<bool>('startAudioCapture');
      if (started == true) {
        _updateState(AudioCaptureState.active);
        return true;
      } else {
        _updateState(AudioCaptureState.denied);
        return false;
      }
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        _updateState(AudioCaptureState.denied);
      } else {
        _updateState(AudioCaptureState.error);
      }
      return false;
    } catch (_) {
      _updateState(AudioCaptureState.error);
      return false;
    }
  }

  Future<void> stopCapture() async {
    try {
      await _methodChannel.invokeMethod('stopAudioCapture');
    } finally {
      _updateState(AudioCaptureState.idle);
    }
  }

  void _updateState(AudioCaptureState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  void dispose() {
    _stateController.close();
  }
}
