
import 'dart:async';

/// A stub for package:flutter/foundation.dart to allow CLI debugging
/// without pulling in dart:ui.

const bool kIsWeb = false;

Future<R> compute<Q, R>(FutureOr<R> Function(Q message) callback, Q message, {String? debugLabel}) async {
  return callback(message);
}

bool listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (int index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

class VisibleForTesting {
  const VisibleForTesting();
}

const VisibleForTesting visibleForTesting = VisibleForTesting();

void debugPrint(String? message, {int? wrapWidth}) {
  print(message);
}
