import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_provider.dart';
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
  Future<ResolvedSource?> build() async => null;

  Future<ResolvedSource?> resolve(String input) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => ref.read(resolveSourceProvider)(input),
    );
    state = result;
    return result.value;
  }

  void reset() => state = const AsyncData(null);

  void setManualSubtitle(String path) {
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(manualSubtitlePath: path));
    }
  }
}
