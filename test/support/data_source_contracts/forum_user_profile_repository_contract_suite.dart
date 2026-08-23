import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/profile/domain/models/forum_user_profile_models.dart';
import 'package:y300/features/profile/domain/repositories/forum_user_profile_repository.dart';

enum ForumUserProfileContractScenario {
  populated,
  missingOptionalFields,
  invalidQuery,
  missingRoot,
  emptyName,
  missingIdentity,
  identityMismatch,
  unlabeledMetric,
  networkFailure,
  timeout,
  cancelled,
  unauthorized,
  serverFailure,
}

final class ForumUserProfileRepositoryContractDriver {
  const ForumUserProfileRepositoryContractDriver({
    required this.name,
    required this.createRepository,
  });

  final String name;
  final ForumUserProfileRepository Function(
    ForumUserProfileContractScenario scenario,
  )
  createRepository;
}

void runForumUserProfileRepositoryContractSuite(
  ForumUserProfileRepositoryContractDriver Function() createDriver,
) {
  final name = createDriver().name;
  group('ForumUserProfileRepository contract: $name', () {
    test('preserves identity and metric/detail DOM order', () async {
      final result = await createDriver()
          .createRepository(ForumUserProfileContractScenario.populated)
          .load(const ForumUserProfileQuery(userId: '509957'));
      final success =
          result
              as DataReadSuccess<
                ForumUserProfileData,
                ForumUserProfileReadCapabilities
              >;

      expect(success.data.identity.userId, '509957');
      expect(success.data.identity.displayName, 'Alice');
      expect(success.data.metrics.map((item) => item.label), ['总积分', '积分']);
      expect(success.data.details.map((item) => item.label), ['UID', '用户组']);
      expect(
        success.capabilities.supports(
          ForumUserProfileCapability.orderedMetrics,
        ),
        isTrue,
      );
      expect(success.metadata.origin, DataReadOrigin.network);
      expect(success.metadata.freshness, DataReadFreshness.current);
    });

    test('keeps optional media and signature absent', () async {
      final result = await createDriver()
          .createRepository(
            ForumUserProfileContractScenario.missingOptionalFields,
          )
          .load(const ForumUserProfileQuery(userId: '509957'));
      final success =
          result
              as DataReadSuccess<
                ForumUserProfileData,
                ForumUserProfileReadCapabilities
              >;

      expect(success.data.avatarUrl, isNull);
      expect(success.data.coverUrl, isNull);
      expect(success.data.signatureHtml, isNull);
      expect(
        success.capabilities.supports(
          ForumUserProfileCapability.signatureMarkup,
        ),
        isFalse,
      );
    });

    test('rejects an invalid query before reading', () async {
      final result = await createDriver()
          .createRepository(ForumUserProfileContractScenario.invalidQuery)
          .load(const ForumUserProfileQuery(userId: ' '));

      expect(result.failureOrNull?.kind, DataReadFailureKind.business);
    });

    for (final scenario in const <ForumUserProfileContractScenario>[
      ForumUserProfileContractScenario.missingRoot,
      ForumUserProfileContractScenario.emptyName,
      ForumUserProfileContractScenario.missingIdentity,
      ForumUserProfileContractScenario.identityMismatch,
      ForumUserProfileContractScenario.unlabeledMetric,
    ]) {
      test('fails closed for ${scenario.name}', () async {
        final result = await createDriver()
            .createRepository(scenario)
            .load(const ForumUserProfileQuery(userId: '509957'));

        expect(result.failureOrNull?.kind, DataReadFailureKind.parse);
      });
    }

    for (final entry
        in const <(ForumUserProfileContractScenario, DataReadFailureKind)>[
          (
            ForumUserProfileContractScenario.networkFailure,
            DataReadFailureKind.network,
          ),
          (
            ForumUserProfileContractScenario.timeout,
            DataReadFailureKind.timeout,
          ),
          (
            ForumUserProfileContractScenario.cancelled,
            DataReadFailureKind.cancelled,
          ),
          (
            ForumUserProfileContractScenario.unauthorized,
            DataReadFailureKind.unauthorized,
          ),
          (
            ForumUserProfileContractScenario.serverFailure,
            DataReadFailureKind.server,
          ),
        ]) {
      test('classifies ${entry.$1.name}', () async {
        final query = entry.$1 == ForumUserProfileContractScenario.unauthorized
            ? const ForumUserProfileQuery(
                userId: '509957',
                view: ForumUserProfileView.self,
              )
            : const ForumUserProfileQuery(userId: '509957');
        final result = await createDriver()
            .createRepository(entry.$1)
            .load(query);

        expect(result.failureOrNull?.kind, entry.$2);
        expect(result.failureOrNull?.diagnosticMessage, isNot(contains('<')));
      });
    }
  });
}
