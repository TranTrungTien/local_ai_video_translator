import 'package:flutter_riverpod/flutter_riverpod.dart';

class DubbingController extends StateNotifier<bool> {
  DubbingController({required this.ref})
    : super(false) { // Changed default from true to false (Sub-only by default)
    _init();
  }

  final Ref ref;

  void _init() {
    // Controller này hiện tại chỉ đóng vai trò toggle trạng thái Dubbing
    // Việc phát âm thanh thực tế đã được chuyển qua DubbingPlayerService
    // để đồng bộ hóa tốt hơn với Native Media Session.
  }

  void toggleDubbing() {
    state = !state;
  }

}

final dubbingControllerProvider =
    StateNotifierProvider<DubbingController, bool>((ref) {
      return DubbingController(
        ref: ref,
      );
    });
