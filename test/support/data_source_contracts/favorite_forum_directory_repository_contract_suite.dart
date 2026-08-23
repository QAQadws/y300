import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/favorites/domain/models/favorite_directory_models.dart';
import 'package:y300/features/favorites/domain/repositories/favorite_directory_repositories.dart';

enum FavoriteForumDirectoryContractScenario {
  populated,
  empty,
  missingList,
  emptyIdentity,
  emptyTitle,
  duplicateIdentity,
  duplicateRemoteIdentity,
  malformedNumber,
  networkFailure,
  timeout,
  cancelled,
  unauthorized,
  businessFailure,
  serverFailure,
}

final class FavoriteForumDirectoryRepositoryContractDriver {
  const FavoriteForumDirectoryRepositoryContractDriver({
    required this.name,
    required this.createRepository,
  });

  final String name;
  final FavoriteForumDirectoryRepository Function(
    FavoriteForumDirectoryContractScenario scenario,
  )
  createRepository;
}

void runFavoriteForumDirectoryRepositoryContractSuite(
  FavoriteForumDirectoryRepositoryContractDriver Function() createDriver,
) {
  final suiteName = createDriver().name;
  group('FavoriteForumDirectoryRepository contract: $suiteName', () {
    test('preserves source order, identities and optional fields', () async {
      final result = await createDriver()
          .createRepository(FavoriteForumDirectoryContractScenario.populated)
          .load(const FavoriteForumDirectoryQuery());

      expect(result.isSuccess, isTrue);
      final success =
          result
              as DataReadSuccess<
                FavoriteForumDirectoryData,
                FavoriteForumDirectoryReadCapabilities
              >;
      expect(success.data.items.map((item) => item.fid), <String>['55', '30']);
      expect(success.data.items.map((item) => item.remoteFavoriteId), <String?>[
        'fav-55',
        'fav-30',
      ]);
      expect(success.data.items.first.threadCount, 12);
      expect(success.data.items.first.postCount, 34);
      expect(success.data.items.first.todayPostCount, 5);
      expect(
        success.capabilities.supports(
          FavoriteForumDirectoryCapability.stableRemoteFavoriteIdentity,
        ),
        isTrue,
      );
      expect(success.metadata.origin, DataReadOrigin.network);
      expect(success.metadata.freshness, DataReadFreshness.current);
    });

    test('returns an explicitly empty list as success', () async {
      final result = await createDriver()
          .createRepository(FavoriteForumDirectoryContractScenario.empty)
          .load(const FavoriteForumDirectoryQuery());

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.items, isEmpty);
    });

    for (final scenario in const <FavoriteForumDirectoryContractScenario>[
      FavoriteForumDirectoryContractScenario.missingList,
      FavoriteForumDirectoryContractScenario.emptyIdentity,
      FavoriteForumDirectoryContractScenario.emptyTitle,
      FavoriteForumDirectoryContractScenario.duplicateIdentity,
      FavoriteForumDirectoryContractScenario.duplicateRemoteIdentity,
      FavoriteForumDirectoryContractScenario.malformedNumber,
    ]) {
      test('fails closed for ${scenario.name}', () async {
        final result = await createDriver()
            .createRepository(scenario)
            .load(const FavoriteForumDirectoryQuery());

        expect(result.failureOrNull?.kind, DataReadFailureKind.parse);
      });
    }

    for (final scenario
        in const <
          (FavoriteForumDirectoryContractScenario, DataReadFailureKind)
        >[
          (
            FavoriteForumDirectoryContractScenario.networkFailure,
            DataReadFailureKind.network,
          ),
          (
            FavoriteForumDirectoryContractScenario.timeout,
            DataReadFailureKind.timeout,
          ),
          (
            FavoriteForumDirectoryContractScenario.cancelled,
            DataReadFailureKind.cancelled,
          ),
          (
            FavoriteForumDirectoryContractScenario.unauthorized,
            DataReadFailureKind.unauthorized,
          ),
          (
            FavoriteForumDirectoryContractScenario.businessFailure,
            DataReadFailureKind.business,
          ),
          (
            FavoriteForumDirectoryContractScenario.serverFailure,
            DataReadFailureKind.server,
          ),
        ]) {
      test('classifies ${scenario.$1.name}', () async {
        final result = await createDriver()
            .createRepository(scenario.$1)
            .load(const FavoriteForumDirectoryQuery());

        expect(result.failureOrNull?.kind, scenario.$2);
        expect(result.failureOrNull?.diagnosticMessage, isNot(contains('<')));
      });
    }
  });
}
