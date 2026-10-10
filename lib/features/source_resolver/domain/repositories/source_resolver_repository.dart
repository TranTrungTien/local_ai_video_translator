import '../entities/resolved_source.dart';

abstract interface class SourceResolverRepository {
  Future<ResolvedSource> resolve(String input);
}
