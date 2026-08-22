import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/repositories/thread_repository.dart';

final class ThreadRepositoryContractDriver {
  const ThreadRepositoryContractDriver({
    required this.name,
    required this.createRepository,
    required this.tid,
  });

  final String name;
  final ThreadRepository Function() createRepository;
  final String tid;
}

void runThreadRepositoryContractSuite(
  ThreadRepositoryContractDriver Function() createDriver,
) {
  final suiteName = createDriver().name;
  group('ThreadRepository contract: $suiteName', () {
    test(
      'returns stable ordered identities and source-neutral metadata',
      () async {
        final driver = createDriver();
        final result = await driver.createRepository().getThreadDetail(
          tid: driver.tid,
        );

        expect(
          result,
          isA<
            DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities>
          >(),
        );
        final success =
            result
                as DataReadSuccess<
                  ThreadDetailData,
                  ThreadDetailReadCapabilities
                >;
        expect(success.data.tid, driver.tid);
        expect(success.data.posts, isNotEmpty);
        expect(
          success.data.posts
              .map((post) => post.pid)
              .every((pid) => pid.trim().isNotEmpty),
          isTrue,
        );
        expect(
          success.data.posts.map((post) => post.pid).toSet(),
          hasLength(success.data.posts.length),
        );
        expect(
          success.capabilities.supports(ThreadDetailCapability.threadIdentity),
          isTrue,
        );
        expect(
          success.capabilities.supports(ThreadDetailCapability.orderedPosts),
          isTrue,
        );
        expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
      },
    );
  });
}
