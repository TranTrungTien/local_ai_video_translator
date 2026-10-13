import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';

abstract final class Sha256Util {
  static Future<String> computeFileHash(File file) async {
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
