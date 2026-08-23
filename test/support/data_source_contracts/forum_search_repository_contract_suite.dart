import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/search/domain/models/forum_search_models.dart';
import 'package:y300/features/search/domain/repositories/forum_search_repository.dart';

final class ForumSearchRepositoryContractDriver {
  const ForumSearchRepositoryContractDriver({
    required this.name,
    required this.createRepository,
    required this.query,
  });

  final String name;
  final ForumSearchRepository Function() createRepository;
  final ForumSearchQuery query;
}

void runForumSearchRepositoryContractSuite(
  ForumSearchRepositoryContractDriver Function() createDriver,
) {
  final suiteName = createDriver().name;
  group('ForumSearchRepository contract: $suiteName', () {
    test(
      'returns ordered stable topics with current network metadata',
      () async {
        final driver = createDriver();
        final result = await driver.createRepository().load(driver.query);

        expect(
          result,
          isA<DataReadSuccess<ForumSearchData, ForumSearchReadCapabilities>>(),
        );
        final success =
            result
                as DataReadSuccess<
                  ForumSearchData,
                  ForumSearchReadCapabilities
                >;
        expect(
          success.data.query.normalizedKeyword,
          driver.query.normalizedKeyword,
        );
        expect(
          success.data.topics.map((topic) => topic.tid).toSet(),
          hasLength(success.data.topics.length),
        );
        expect(
          success.capabilities.supports(
            ForumSearchCapability.stableTopicIdentity,
          ),
          isTrue,
        );
        expect(
          success.capabilities.supports(ForumSearchCapability.orderedTopics),
          isTrue,
        );
        expect(success.metadata, const DataReadMetadata.network());
      },
    );

    test(
      'rejects an invalid query before a repository read is needed',
      () async {
        final result = await createDriver().createRepository().load(
          const ForumSearchQuery(keyword: ' '),
        );
        expect(result.failureOrNull?.kind, DataReadFailureKind.business);
      },
    );
  });
}
