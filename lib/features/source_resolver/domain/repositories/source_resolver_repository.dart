import '../../../../core/utils/cancellation_token.dart';
import '../entities/resolved_source.dart';

abstract interface class SourceResolverRepository {
  Future<ResolvedSource> resolve(String input, {CancellationToken? cancellationToken});
}
