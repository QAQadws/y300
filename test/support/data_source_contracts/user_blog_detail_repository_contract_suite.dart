import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/profile/domain/models/user_blog_models.dart';
import 'package:y300/features/profile/domain/repositories/user_blog_detail_repository.dart';

enum UserBlogDetailContractScenario {
  populated,
  missingOptionalFields,
  commentsUnavailable,
  invalidQuery,
  missingRoot,
  identityMismatch,
  ownerMismatch,
  emptyCommentIdentity,
  duplicateCommentIdentity,
  malformedStatistic,
  networkFailure,
  timeout,
  cancelled,
  unauthorized,
  serverFailure,
}

final class UserBlogDetailRepositoryContractDriver {
  const UserBlogDetailRepositoryContractDriver({
    required this.name,
    required this.createRepository,
  });

  final String name;
  final UserBlogDetailRepository Function(
    UserBlogDetailContractScenario scenario,
  )
  createRepository;
}

void runUserBlogDetailRepositoryContractSuite(
  UserBlogDetailRepositoryContractDriver Function() createDriver,
) {
  final name = createDriver().name;
  group('UserBlogDetailRepository contract: $name', () {
    const query = UserBlogDetailQuery(ownerUserId: '101', blogId: '11');

    test('preserves composite identity and comment order', () async {
      final result = await createDriver()
          .createRepository(UserBlogDetailContractScenario.populated)
          .load(query);
      final success =
          result
              as DataReadSuccess<
                UserBlogDetailData,
                UserBlogDetailReadCapabilities
              >;

      expect(success.data.ownerUserId, '101');
      expect(success.data.blogId, '11');
      expect(success.data.comments.map((item) => item.commentId), [
        '201',
        '202',
      ]);
      expect(success.data.viewCount, 7);
      expect(success.data.commentCount, 2);
      expect(success.data.commentsOpen, isTrue);
      expect(
        success.capabilities.supports(
          UserBlogDetailCapability.stableCommentIdentity,
        ),
        isTrue,
      );
      expect(success.metadata.origin, DataReadOrigin.network);
      expect(success.metadata.freshness, DataReadFreshness.current);
    });

    test(
      'keeps absent optional fields and comment availability null',
      () async {
        final result = await createDriver()
            .createRepository(
              UserBlogDetailContractScenario.missingOptionalFields,
            )
            .load(query);
        final success =
            result
                as DataReadSuccess<
                  UserBlogDetailData,
                  UserBlogDetailReadCapabilities
                >;

        expect(success.data.avatarUrl, isNull);
        expect(success.data.publishedAtText, isNull);
        expect(success.data.viewCount, isNull);
        expect(success.data.commentCount, isNull);
        expect(success.data.commentsOpen, isNull);
        expect(
          success.capabilities.supports(
            UserBlogDetailCapability.commentingAvailability,
          ),
          isFalse,
        );
      },
    );

    test('does not infer closed comments from a missing form', () async {
      final result = await createDriver()
          .createRepository(UserBlogDetailContractScenario.commentsUnavailable)
          .load(query);

      expect(result.dataOrNull!.commentsOpen, isNull);
    });

    test('rejects an invalid query before reading', () async {
      final result = await createDriver()
          .createRepository(UserBlogDetailContractScenario.invalidQuery)
          .load(const UserBlogDetailQuery(ownerUserId: '', blogId: ''));

      expect(result.failureOrNull?.kind, DataReadFailureKind.business);
    });

    for (final scenario in const <UserBlogDetailContractScenario>[
      UserBlogDetailContractScenario.missingRoot,
      UserBlogDetailContractScenario.identityMismatch,
      UserBlogDetailContractScenario.ownerMismatch,
      UserBlogDetailContractScenario.emptyCommentIdentity,
      UserBlogDetailContractScenario.duplicateCommentIdentity,
      UserBlogDetailContractScenario.malformedStatistic,
    ]) {
      test('fails closed for ${scenario.name}', () async {
        final result = await createDriver()
            .createRepository(scenario)
            .load(query);

        expect(result.failureOrNull?.kind, DataReadFailureKind.parse);
      });
    }

    for (final entry
        in const <(UserBlogDetailContractScenario, DataReadFailureKind)>[
          (
            UserBlogDetailContractScenario.networkFailure,
            DataReadFailureKind.network,
          ),
          (UserBlogDetailContractScenario.timeout, DataReadFailureKind.timeout),
          (
            UserBlogDetailContractScenario.cancelled,
            DataReadFailureKind.cancelled,
          ),
          (
            UserBlogDetailContractScenario.unauthorized,
            DataReadFailureKind.unauthorized,
          ),
          (
            UserBlogDetailContractScenario.serverFailure,
            DataReadFailureKind.server,
          ),
        ]) {
      test('classifies ${entry.$1.name}', () async {
        final result = await createDriver()
            .createRepository(entry.$1)
            .load(query);

        expect(result.failureOrNull?.kind, entry.$2);
        expect(result.failureOrNull?.diagnosticMessage, isNot(contains('<')));
      });
    }
  });
}
