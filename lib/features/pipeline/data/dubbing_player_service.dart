import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/dub_segment.dart';
import 'dubbing_repository.dart';

class DubbingPlayerService {
  DubbingPlayerService(this._repository) {
    _player.stream.completed.listen((_) {
      _duckingController.add(false);
      _cleanupTempFile();
    });
  }

  final DubbingRepository _repository;
  final Player _player = Player();
  final _duckingController = StreamController<bool>.broadcast();
  File? _tempWavFile;

  Duration? _lastPlayedStart;

  Stream<bool> get duckingStream => _duckingController.stream;

  void syncWithPlayback(Duration position, bool isVideoPlaying) {
    if (!isVideoPlaying) {
      if (_player.state.playing) _player.pause();
      return;
    }

    final segment = _repository.getSegmentAt(position);
    if (segment != null && _lastPlayedStart != segment.startPts) {
      _playSegment(segment);
    }
  }

  Future<void> _playSegment(DubSegment segment) async {
    _lastPlayedStart = segment.startPts;
    _duckingController.add(true);

    try {
      final wavBytes = _createWavContainer(segment.generatedAudio);

      // Ghi ra file tạm thay vì dùng Base64 để tiết kiệm RAM
      final tempDir = await getTemporaryDirectory();
      _tempWavFile = File('${tempDir.path}/dub_temp.wav');
      await _tempWavFile!.writeAsBytes(wavBytes, flush: true);

      await _player.open(Media(_tempWavFile!.path));
      await _player.play();
    } catch (e) {
      _duckingController.add(false);
    }
  }

  Uint8List _createWavContainer(List<int> pcmBytes) {
    const int sampleRate = 16000;
    const int channels = 1;
    final int dataSize = pcmBytes.length;
    final int fileSize = 36 + dataSize;
    final header = ByteData(44);

    header.setUint32(0, 0x52494646, Endian.big); // RIFF
    header.setUint32(4, fileSize, Endian.little);
    header.setUint32(8, 0x57415645, Endian.big); // WAVE
    header.setUint32(12, 0x666D7420, Endian.big); // fmt
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * channels * 2, Endian.little);
    header.setUint16(32, channels * 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint32(36, 0x64617461, Endian.big); // data
    header.setUint32(40, dataSize, Endian.little);

    final wavBytes = Uint8List(44 + pcmBytes.length);
    wavBytes.setAll(0, header.buffer.asUint8List());
    wavBytes.setAll(44, pcmBytes);
    return wavBytes;
  }

  void setVolume(double volume) => _player.setVolume(volume);

  Future<void> _cleanupTempFile() async {
    try {
      if (_tempWavFile != null && await _tempWavFile!.exists()) {
        await _tempWavFile!.delete();
        _tempWavFile = null;
      }
    } catch (e) {
      // Ignored
    }
  }

  void dispose() {
    _player.dispose();
    _duckingController.close();
    _cleanupTempFile();
  }
}
