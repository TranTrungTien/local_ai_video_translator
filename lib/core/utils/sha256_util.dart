import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

abstract final class Sha256Util {
  static Future<String> computeFileHash(dynamic file) async {
    if (kIsWeb) return ''; // Filesystem access not available on Web
    if (file is! io.File) return '';
    if (!await file.exists()) return '';
    final stream = file.openRead();
    final digest = await sha256.bind(stream).first;
    return digest.toString();
  }

  static String computeBytesHash(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  /// Generates a cryptographically secure random nonce for WebView security.
  static String generateNonce([int length = 32]) {
    final random = Random.secure();
    final values = List<int>.generate(length, (i) => random.nextInt(256));
    return base64Url.encode(values).replaceAll('=', '');
  }
}
