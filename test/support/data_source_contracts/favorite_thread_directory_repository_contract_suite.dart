import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/favorites/domain/models/favorite_directory_models.dart';
import 'package:y300/features/favorites/domain/repositories/favorite_directory_repositories.dart';

enum FavoriteThreadDirectoryContractScenario {
  populated,
  empty,
  missingOptionalFields,
  zeroTimestamp,
  invalidQuery,
  missingList,
  emptyIdentity,
  emptyTitle,
  duplicateIdentity,
  duplicateRemoteIdentity,
  malformedNumber,
  malformedTimestamp,
  networkFailure,
  timeout,
  cancelled,
  unauthorized,
  businessFailure,
  serverFailure,
}

final class FavoriteThreadDirectoryRepositoryContractDriver {
  const FavoriteThreadDirectoryRepositoryContractDriver({
    required this.name,
    required this.createRepository,
  });

  final String name;
  final FavoriteThreadDirectoryRepository Function(
    FavoriteThreadDirectoryContractScenario scenario,
  )
  createRepository;
}

void runFavoriteThreadDirectoryRepositoryContractSuite(
  FavoriteThreadDirectoryRepositoryContractDriver Function() createDriver,
) {
  final suiteName = createDriver().name;
  group('FavoriteThreadDirectoryRepository contract: $suiteName', () {
    test('preserves order, UTC timestamp and exact pagination', () async {
      final result = await createDriver()
          .createRepository(FavoriteThreadDirectoryContractScenario.populated)
          .load(const FavoriteThreadDirectoryQuery(page: 1));

      expect(result.isSuccess, isTrue);
      final success =
          result
              as DataReadSuccess<
                FavoriteThreadDirectoryData,
                FavoriteThreadDirectoryReadCapabilities
              >;
      expect(success.data.items.map((item) => item.tid), <String>[
        '100',
        '200',
      ]);
      expect(success.data.items.first.remoteFavoriteId, 'fav-100');
      expect(success.data.items.first.replyCount, 3);
      expect(success.data.items.first.favoritedAt?.isUtc, isTrue);
      expect(success.data.pagination.currentPage, 1);
      expect(success.data.pagination.pageSize, 2);
      expect(success.data.pagination.totalItems, 3);
      expect(success.data.pagination.totalPages, 2);
      expect(success.data.pagination.hasPrevious, isFalse);
      expect(success.data.pagination.hasNext, isTrue);
      expect(
        success.capabilities.paginationPrecision,
        PaginationPrecision.exact,
      );
      expect(
        success.capabilities.supports(
          FavoriteThreadDirectoryCapability.totalItemCount,
        ),
        isTrue,
      );
      expect(success.metadata.origin, DataReadOrigin.network);
      expect(success.metadata.freshness, DataReadFreshness.current);
    });

    test('returns an explicitly empty list as success', () async {
      final result = await createDriver()
          .createRepository(FavoriteThreadDirectoryContractScenario.empty)
          .load(const FavoriteThreadDirectoryQuery());

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.items, isEmpty);
      expect(result.dataOrNull!.pagination.totalItems, 0);
    });

    test('keeps missing optional fields and timestamp sentinel null', () async {
      final missing = await createDriver()
          .createRepository(
            FavoriteThreadDirectoryContractScenario.missingOptionalFields,
          )
          .load(const FavoriteThreadDirectoryQuery());
      final sentinel = await createDriver()
          .createRepository(
            FavoriteThreadDirectoryContractScenario.zeroTimestamp,
          )
          .load(const FavoriteThreadDirectoryQuery());

      expect(missing.isSuccess, isTrue);
      expect(missing.dataOrNull!.items.single.remoteFavoriteId, isNull);
      expect(missing.dataOrNull!.items.single.replyCount, isNull);
      expect(missing.dataOrNull!.items.single.favoritedAt, isNull);
      expect(sentinel.isSuccess, isTrue);
      expect(sentinel.dataOrNull!.items.single.favoritedAt, isNull);
    });

    test('rejects an invalid page before reading', () async {
      final result = await createDriver()
          .createRepository(
            FavoriteThreadDirectoryContractScenario.invalidQuery,
          )
          .load(const FavoriteThreadDirectoryQuery(page: 0));

      expect(result.failureOrNull?.kind, DataReadFailureKind.business);
    });

    for (final scenario in const <FavoriteThreadDirectoryContractScenario>[
      FavoriteThreadDirectoryContractScenario.missingList,
      FavoriteThreadDirectoryContractScenario.emptyIdentity,
      FavoriteThreadDirectoryContractScenario.emptyTitle,
      FavoriteThreadDirectoryContractScenario.duplicateIdentity,
      FavoriteThreadDirectoryContractScenario.duplicateRemoteIdentity,
      FavoriteThreadDirectoryContractScenario.malformedNumber,
      FavoriteThreadDirectoryContractScenario.malformedTimestamp,
    ]) {
      test('fails closed for ${scenario.name}', () async {
        final result = await createDriver()
            .createRepository(scenario)
            .load(const FavoriteThreadDirectoryQuery());

        expect(result.failureOrNull?.kind, DataReadFailureKind.parse);
      });
    }

    for (final scenario
        in const <
          (FavoriteThreadDirectoryContractScenario, DataReadFailureKind)
        >[
          (
            FavoriteThreadDirectoryContractScenario.networkFailure,
            DataReadFailureKind.network,
          ),
          (
            FavoriteThreadDirectoryContractScenario.timeout,
            DataReadFailureKind.timeout,
          ),
          (
            FavoriteThreadDirectoryContractScenario.cancelled,
            DataReadFailureKind.cancelled,
          ),
          (
            FavoriteThreadDirectoryContractScenario.unauthorized,
            DataReadFailureKind.unauthorized,
          ),
          (
            FavoriteThreadDirectoryContractScenario.businessFailure,
            DataReadFailureKind.business,
          ),
          (
            FavoriteThreadDirectoryContractScenario.serverFailure,
            DataReadFailureKind.server,
          ),
        ]) {
      test('classifies ${scenario.$1.name}', () async {
        final result = await createDriver()
            .createRepository(scenario.$1)
            .load(const FavoriteThreadDirectoryQuery());

        expect(result.failureOrNull?.kind, scenario.$2);
        expect(result.failureOrNull?.diagnosticMessage, isNot(contains('<')));
      });
    }
  });
}
