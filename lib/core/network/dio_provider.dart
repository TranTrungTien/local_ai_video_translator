import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';

final dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: AppConstants.networkTimeout,
      receiveTimeout: AppConstants.networkTimeout,
      followRedirects: true,
      maxRedirects: 5,
      headers: const {'User-Agent': 'LocalAIVideoTranslator/0.1'},
    ),
  );
});
