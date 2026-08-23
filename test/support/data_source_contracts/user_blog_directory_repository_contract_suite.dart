import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/profile/domain/models/user_blog_models.dart';
import 'package:y300/features/profile/domain/repositories/user_blog_directory_repository.dart';

enum UserBlogDirectoryContractScenario {
  populated,
  empty,
  missingOptionalFields,
  directionalPagination,
  unknownPagination,
  invalidQuery,
  missingRoot,
  identityMismatch,
  emptyBlogIdentity,
  emptyOwnerIdentity,
  emptyTitle,
  duplicateIdentity,
  malformedPagination,
  networkFailure,
  timeout,
  cancelled,
  unauthorized,
  serverFailure,
}

final class UserBlogDirectoryRepositoryContractDriver {
  const UserBlogDirectoryRepositoryContractDriver({
    required this.name,
    required this.createRepository,
  });

  final String name;
  final UserBlogDirectoryRepository Function(
    UserBlogDirectoryContractScenario scenario,
  )
  createRepository;
}

void runUserBlogDirectoryRepositoryContractSuite(
  UserBlogDirectoryRepositoryContractDriver Function() createDriver,
) {
  final name = createDriver().name;
  group('UserBlogDirectoryRepository contract: $name', () {
    test('preserves identities, source order and exact pagination', () async {
      final result = await createDriver()
          .createRepository(UserBlogDirectoryContractScenario.populated)
          .load(const UserBlogDirectoryQuery.public());
      final success =
          result
              as DataReadSuccess<
                UserBlogDirectoryData,
                UserBlogDirectoryReadCapabilities
              >;

      expect(success.data.scope, UserBlogFeedScope.public);
      expect(success.data.order, UserBlogOrder.latest);
      expect(success.data.items.map((item) => item.blogId), ['11', '12']);
      expect(success.data.items.map((item) => item.ownerUserId), [
        '101',
        '102',
      ]);
      expect(success.data.pagination.currentPage, 1);
      expect(success.data.pagination.totalPages, 3);
      expect(
        success.capabilities.paginationPrecision,
        PaginationPrecision.exact,
      );
      expect(
        success.capabilities.supports(
          UserBlogDirectoryCapability.totalPageCount,
        ),
        isTrue,
      );
      expect(success.metadata.origin, DataReadOrigin.network);
      expect(success.metadata.freshness, DataReadFreshness.current);
    });

    test('accepts an explicitly empty feed', () async {
      final result = await createDriver()
          .createRepository(UserBlogDirectoryContractScenario.empty)
          .load(const UserBlogDirectoryQuery.self());

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.items, isEmpty);
    });

    test('keeps missing optional fields null and unsupported', () async {
      final result = await createDriver()
          .createRepository(
            UserBlogDirectoryContractScenario.missingOptionalFields,
          )
          .load(const UserBlogDirectoryQuery.public());
      final success =
          result
              as DataReadSuccess<
                UserBlogDirectoryData,
                UserBlogDirectoryReadCapabilities
              >;

      expect(success.data.items.single.authorName, isNull);
      expect(success.data.items.single.excerpt, isNull);
      expect(success.data.items.single.avatarUrl, isNull);
      expect(success.data.items.single.publishedAtText, isNull);
      expect(
        success.capabilities.supports(UserBlogDirectoryCapability.author),
        isFalse,
      );
    });

    test(
      'reports directional and unknown pagination without guessing',
      () async {
        final directional = await createDriver()
            .createRepository(
              UserBlogDirectoryContractScenario.directionalPagination,
            )
            .load(const UserBlogDirectoryQuery.public());
        final unknown = await createDriver()
            .createRepository(
              UserBlogDirectoryContractScenario.unknownPagination,
            )
            .load(const UserBlogDirectoryQuery.public());

        final directionalCapabilities = directional.when(
          success: (_, capabilities, _) => capabilities,
          failure: (failure) => throw failure,
        );
        final unknownCapabilities = unknown.when(
          success: (_, capabilities, _) => capabilities,
          failure: (failure) => throw failure,
        );
        expect(
          directionalCapabilities.paginationPrecision,
          PaginationPrecision.directional,
        );
        expect(directional.dataOrNull!.pagination.hasNext, isTrue);
        expect(
          unknownCapabilities.paginationPrecision,
          PaginationPrecision.unknown,
        );
        expect(unknown.dataOrNull!.pagination.hasNext, isNull);
      },
    );

    test('rejects an invalid query', () async {
      final result = await createDriver()
          .createRepository(UserBlogDirectoryContractScenario.invalidQuery)
          .load(
            const UserBlogDirectoryQuery(
              scope: UserBlogFeedScope.self,
              order: UserBlogOrder.latest,
              page: 0,
            ),
          );

      expect(result.failureOrNull?.kind, DataReadFailureKind.business);
    });

    for (final scenario in const <UserBlogDirectoryContractScenario>[
      UserBlogDirectoryContractScenario.missingRoot,
      UserBlogDirectoryContractScenario.identityMismatch,
      UserBlogDirectoryContractScenario.emptyBlogIdentity,
      UserBlogDirectoryContractScenario.emptyOwnerIdentity,
      UserBlogDirectoryContractScenario.emptyTitle,
      UserBlogDirectoryContractScenario.duplicateIdentity,
      UserBlogDirectoryContractScenario.malformedPagination,
    ]) {
      test('fails closed for ${scenario.name}', () async {
        final result = await createDriver()
            .createRepository(scenario)
            .load(const UserBlogDirectoryQuery.public());

        expect(result.failureOrNull?.kind, DataReadFailureKind.parse);
      });
    }

    for (final entry
        in const <(UserBlogDirectoryContractScenario, DataReadFailureKind)>[
          (
            UserBlogDirectoryContractScenario.networkFailure,
            DataReadFailureKind.network,
          ),
          (
            UserBlogDirectoryContractScenario.timeout,
            DataReadFailureKind.timeout,
          ),
          (
            UserBlogDirectoryContractScenario.cancelled,
            DataReadFailureKind.cancelled,
          ),
          (
            UserBlogDirectoryContractScenario.unauthorized,
            DataReadFailureKind.unauthorized,
          ),
          (
            UserBlogDirectoryContractScenario.serverFailure,
            DataReadFailureKind.server,
          ),
        ]) {
      test('classifies ${entry.$1.name}', () async {
        final query = entry.$1 == UserBlogDirectoryContractScenario.unauthorized
            ? const UserBlogDirectoryQuery.self()
            : const UserBlogDirectoryQuery.public();
        final result = await createDriver()
            .createRepository(entry.$1)
            .load(query);

        expect(result.failureOrNull?.kind, entry.$2);
        expect(result.failureOrNull?.diagnosticMessage, isNot(contains('<')));
      });
    }
  });
}
