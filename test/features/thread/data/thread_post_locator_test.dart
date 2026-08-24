import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart'
    as forum;
import 'package:y300/features/thread/data/services/thread_post_locator.dart';

void main() {
  test('projects a package location for existing App routes', () async {
    final source = _FakePostLocator(
      forum.DataReadSuccess(
        data: forum.ThreadPostLocationData(
          tid: '100',
          pid: '200',
          page: 3,
          resolvedUri: Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&page=3',
          ),
        ),
        capabilities: forum.ThreadPostLocatorReadCapabilities(
          values: forum.DataCapabilitySet.supported(
            forum.ThreadPostLocatorCapability.values,
          ),
        ),
        metadata: const forum.DataReadMetadata.network(),
      ),
    );
    final locator = PackageThreadPostLocator(source);

    final result = await locator.locate(
      tid: '100',
      pid: '200',
      sourceUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&pid=200',
      ),
    );

    expect(source.queries.single.tid, '100');
    expect(source.queries.single.pid, '200');
    expect(result.dataOrNull?.page, 3);
    expect(result.dataOrNull?.url, contains('page=3'));
  });

  test('does not hide a package identity failure', () async {
    final locator = PackageThreadPostLocator(
      _FakePostLocator(
        const forum.DataReadFailure(
          kind: forum.DataReadFailureKind.parse,
          code: 'thread_post_location_identity_mismatch',
          diagnosticMessage: 'identity mismatch',
        ),
      ),
    );

    final result = await locator.locate(
      tid: '100',
      pid: '200',
      sourceUri: Uri.parse('https://bbs.yamibo.com/'),
    );

    expect(result.isFailure, isTrue);
    expect(result.errorOrNull?.code, 'thread_post_location_identity_mismatch');
  });
}

final class _FakePostLocator implements forum.ThreadPostLocatorRepository {
  _FakePostLocator(this.result);

  final forum.DataReadResult<
    forum.ThreadPostLocationData,
    forum.ThreadPostLocatorReadCapabilities
  >
  result;
  final queries = <forum.ThreadPostLocationQuery>[];

  @override
  forum.ThreadPostLocatorSourceCapabilities get capabilities =>
      forum.ThreadPostLocatorSourceCapabilities(
        values: forum.DataCapabilitySet.supported(
          forum.ThreadPostLocatorCapability.values,
        ),
      );

  @override
  Future<
    forum.DataReadResult<
      forum.ThreadPostLocationData,
      forum.ThreadPostLocatorReadCapabilities
    >
  >
  locate(
    forum.ThreadPostLocationQuery query, {
    forum.CacheLoadPolicy cachePolicy = forum.CacheLoadPolicy.networkFirst,
  }) async {
    queries.add(query);
    return result;
  }
}
