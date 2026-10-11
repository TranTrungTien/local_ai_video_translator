import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/diagnostics/diagnostics_service.dart';
import '../data/dubbing_repository.dart';
import 'ai_scheduler_controller.dart';

class DubbingController extends StateNotifier<bool> {
  DubbingController({
    required DubbingRepository repository,
    required this.ref,
  }) : _repository = repository,
       super(true) { // Trạng thái mặc định: Bật lồng tiếng
    _init();
  }

  final DubbingRepository _repository;
  final Ref ref;
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription? _activeIdSub;

  void _init() {
    // Lắng nghe tín hiệu từ AiScheduler khi có một đoạn dubbing cần phát
    _activeIdSub = _repository.activeIdStream.listen((id) async {
      if (!state) return;
      
      if (id == null) {
        await _audioPlayer.stop();
        return;
      }
      
      final segment = _repository.getSegmentAt(ref.read(aiSchedulerProvider).playbackPosition);
      if (segment != null) {
        await _playSegment(segment.generatedAudio);
      }
    });
  }

  Future<void> _playSegment(List<int> audioData) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_dub.wav');
      
      // Thêm WAV Header (16kHz, Mono, 16-bit) để Audioplayers có thể đọc được
      final wavData = _addWavHeader(audioData, 16000);
      await tempFile.writeAsBytes(wavData);
      
      await _audioPlayer.play(DeviceFileSource(tempFile.path), mode: PlayerMode.lowLatency);
    } catch (e) {
      ref.read(diagnosticsServiceProvider).log('Dubbing', 'Play error: $e', level: LogLevel.error);
    }
  }

  List<int> _addWavHeader(List<int> pcmData, int sampleRate) {
    final int fileSize = pcmData.length + 36;
    final ByteData header = ByteData(44);
    
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    
    // fmt chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); //  
    header.setUint32(16, 16, Endian.little); // Chunk size
    header.setUint16(20, 1, Endian.little);  // PCM format
    header.setUint16(22, 1, Endian.little);  // Mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little); // Byte rate
    header.setUint16(32, 2, Endian.little);  // Block align
    header.setUint16(34, 16, Endian.little); // Bits per sample
    
    // data chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, pcmData.length, Endian.little);
    
    return header.buffer.asUint8List().toList() + pcmData;
  }

  void toggleDubbing() {
    state = !state;
    if (!state) _audioPlayer.stop();
  }

  @override
  void dispose() {
    _activeIdSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}

final dubbingControllerProvider = StateNotifierProvider<DubbingController, bool>((ref) {
  return DubbingController(
    repository: ref.watch(dubbingRepositoryProvider),
    ref: ref,
  );
});
