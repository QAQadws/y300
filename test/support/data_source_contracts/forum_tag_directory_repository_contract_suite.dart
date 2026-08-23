import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/tags/domain/models/forum_tag_directory_models.dart';
import 'package:y300/features/tags/domain/repositories/forum_tag_directory_repository.dart';

enum ForumTagDirectoryContractScenario {
  populated,
  empty,
  invalidQuery,
  parseFailure,
  networkFailure,
}

final class ForumTagDirectoryRepositoryContractDriver {
  const ForumTagDirectoryRepositoryContractDriver({
    required this.name,
    required this.createRepository,
  });

  final String name;
  final ForumTagDirectoryRepository Function(
    ForumTagDirectoryContractScenario scenario,
  )
  createRepository;
}

void runForumTagDirectoryRepositoryContractSuite(
  ForumTagDirectoryRepositoryContractDriver Function() createDriver,
) {
  group('ForumTagDirectoryRepository contract', () {
    test('preserves identity and source order', () async {
      final driver = createDriver();
      final result = await driver
          .createRepository(ForumTagDirectoryContractScenario.populated)
          .load(const ForumTagDirectoryQuery(tagId: '21920'));

      expect(result.isSuccess, isTrue, reason: driver.name);
      final data = result.dataOrNull!;
      expect(data.tag.id, '21920');
      expect(data.topics.map((topic) => topic.tid), ['1', '2']);
      expect(data.topics.map((topic) => topic.title), ['first', 'second']);
      final metadata = result.when(
        success: (_, _, value) => value,
        failure: (_) => throw StateError('expected success'),
      );
      expect(metadata.origin, DataReadOrigin.network);
      expect(metadata.freshness, DataReadFreshness.current);
    });

    test('represents an explicitly empty directory as success', () async {
      final driver = createDriver();
      final result = await driver
          .createRepository(ForumTagDirectoryContractScenario.empty)
          .load(const ForumTagDirectoryQuery(tagId: '21920'));

      expect(result.isSuccess, isTrue, reason: driver.name);
      expect(result.dataOrNull!.topics, isEmpty);
    });

    test('rejects invalid query before a read', () async {
      final driver = createDriver();
      final result = await driver
          .createRepository(ForumTagDirectoryContractScenario.invalidQuery)
          .load(const ForumTagDirectoryQuery(tagId: ''));

      expect(
        result,
        isA<
          DataReadFailure<
            ForumTagDirectoryData,
            ForumTagDirectoryReadCapabilities
          >
        >(),
      );
      expect(result.failureOrNull!.kind, DataReadFailureKind.business);
    });

    test(
      'classifies parse and network failures without transport payloads',
      () async {
        final driver = createDriver();
        final parseResult = await driver
            .createRepository(ForumTagDirectoryContractScenario.parseFailure)
            .load(const ForumTagDirectoryQuery(tagId: '21920'));
        final networkResult = await driver
            .createRepository(ForumTagDirectoryContractScenario.networkFailure)
            .load(
              const ForumTagDirectoryQuery(tagId: '21920'),
              cachePolicy: CacheLoadPolicy.networkFirst,
            );

        expect(parseResult.failureOrNull!.kind, DataReadFailureKind.parse);
        expect(networkResult.failureOrNull!.kind, DataReadFailureKind.network);
        expect(
          networkResult.failureOrNull!.diagnosticMessage,
          isNot(contains('<')),
        );
      },
    );
  });
}
