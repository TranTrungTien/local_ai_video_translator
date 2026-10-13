import '../../../../core/utils/cancellation_token.dart';
import '../entities/resolved_source.dart';
import '../repositories/source_resolver_repository.dart';

class ResolveSource {
  const ResolveSource(this.repository);
  final SourceResolverRepository repository;

  Future<ResolvedSource> call(String input, {CancellationToken? cancellationToken}) =>
    repository.resolve(input, cancellationToken: cancellationToken);
}
