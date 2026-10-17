import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_provider.dart';
import '../../../core/utils/cancellation_token.dart';
import '../data/html_media_parser.dart';
import '../data/source_resolver_repository_impl.dart';
import '../domain/entities/resolved_source.dart';
import '../domain/repositories/source_resolver_repository.dart';
import '../domain/usecases/resolve_source.dart';

final sourceResolverRepositoryProvider = Provider<SourceResolverRepository>((
  ref,
) {
  return SourceResolverRepositoryImpl(
    ref.watch(dioProvider),
    const HtmlMediaParser(),
  );
});

final resolveSourceProvider = Provider<ResolveSource>(
  (ref) => ResolveSource(ref.watch(sourceResolverRepositoryProvider)),
);

final sourceResolverControllerProvider =
    AsyncNotifierProvider<SourceResolverController, ResolvedSource?>(
      SourceResolverController.new,
    );

class SourceResolverController extends AsyncNotifier<ResolvedSource?> {
  @override
  Future<ResolvedSource?> build() async {
    ref.onDispose(() {
      _activeDioCancelToken?.cancel('Controller disposed');
    });
    return null;
  }

  String? _manualSubtitlePath;
  int _requestGeneration = 0;
  CancelToken? _activeDioCancelToken;
  CancellationToken? _activeDomainToken;

  Future<ResolvedSource?> resolve(String input) async {
    final generation = ++_requestGeneration;
    _activeDioCancelToken?.cancel('New resolution started');
    _activeDioCancelToken = CancelToken();
    _activeDomainToken?.cancel();
    _activeDomainToken = CancellationToken();

    state = const AsyncLoading();

    try {
      final result = await ref.read(resolveSourceProvider)(
        input,
        cancellationToken: _activeDomainToken,
      );

      if (generation != _requestGeneration) {
        return state.value;
      }

      if (result != null) {
        if (_manualSubtitlePath != null) {
          state = AsyncData(result.copyWith(manualSubtitlePath: _manualSubtitlePath));
        } else {
          state = AsyncData(result);
        }
      } else {
        state = const AsyncData(null);
      }
    } catch (e, st) {
      if (generation != _requestGeneration) {
        return state.value;
      }
      state = AsyncError(e, st);
    }

    return state.value;
  }

  void reset() {
    _manualSubtitlePath = null;
    state = const AsyncData(null);
  }

  void setManualSubtitle(String path) {
    _manualSubtitlePath = path;
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(manualSubtitlePath: path));
    }
  }
}
