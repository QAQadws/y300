import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart'
    as forum;
import 'package:y300/features/thread/data/repositories/thread_post_ratings_repository.dart';

void main() {
  group('PackageThreadPostRatingsRepository', () {
    test('derives tid and pid then projects package ratings', () async {
      final source = _FakeRatingsRepository(
        forum.DataReadSuccess(
          data: const forum.ThreadPostRatingsData(
            participantCount: 1,
            totalScoreText: '积分 +2 点',
            ratings: [
              forum.ThreadPostRating(
                userName: 'Alice',
                score: '+2',
                reason: 'agree',
              ),
            ],
          ),
          capabilities: _capabilities,
          metadata: const forum.DataReadMetadata.network(),
        ),
      );
      final repository = PackageThreadPostRatingsRepository(repository: source);

      final result = await repository.loadAll(
        'https://bbs.yamibo.com/forum.php?mod=misc&action=viewratings'
        '&tid=100&pid=200',
      );

      expect(result.isSuccess, isTrue);
      expect(source.queries.single.tid, '100');
      expect(source.queries.single.pid, '200');
      expect(result.dataOrNull!.totalScoreText, '积分 +2 点');
      expect(result.dataOrNull!.ratings.single.userName, 'Alice');
    });

    test('preserves structured package failure', () async {
      final source = _FakeRatingsRepository(
        const forum.DataReadFailure(
          kind: forum.DataReadFailureKind.parse,
          code: 'ratings_invalid',
          diagnosticMessage: 'invalid ratings',
        ),
      );
      final repository = PackageThreadPostRatingsRepository(repository: source);

      final result = await repository.loadAll(
        'https://bbs.yamibo.com/forum.php?tid=100&pid=200',
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.code, 'ratings_invalid');
    });
  });
}

final _capabilities = forum.ThreadPostRatingsReadCapabilities(
  values: forum.DataCapabilitySet.supported(
    forum.ThreadPostRatingsCapability.values,
  ),
);

final class _FakeRatingsRepository
    implements forum.ThreadPostRatingsRepository {
  _FakeRatingsRepository(this.result);

  final forum.DataReadResult<
    forum.ThreadPostRatingsData,
    forum.ThreadPostRatingsReadCapabilities
  >
  result;
  final queries = <forum.ThreadPostRatingsQuery>[];

  @override
  forum.ThreadPostRatingsSourceCapabilities get capabilities =>
      forum.ThreadPostRatingsSourceCapabilities(
        values: forum.DataCapabilitySet.supported(
          forum.ThreadPostRatingsCapability.values,
        ),
      );

  @override
  Future<
    forum.DataReadResult<
      forum.ThreadPostRatingsData,
      forum.ThreadPostRatingsReadCapabilities
    >
  >
  load(
    forum.ThreadPostRatingsQuery query, {
    forum.CacheLoadPolicy cachePolicy = forum.CacheLoadPolicy.networkFirst,
  }) async {
    queries.add(query);
    return result;
  }
}
