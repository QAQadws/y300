import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/profile/domain/models/current_user_profile_models.dart';
import 'package:y300/features/profile/domain/repositories/current_user_profile_repository.dart';

enum CurrentUserProfileContractScenario {
  populated,
  missingOptionalFields,
  anonymous,
  missingSpace,
  identityMismatch,
  nameMismatch,
  malformedNumber,
  networkFailure,
  timeout,
  cancelled,
  unauthorized,
  serverFailure,
  businessFailure,
}

final class CurrentUserProfileRepositoryContractDriver {
  const CurrentUserProfileRepositoryContractDriver({
    required this.name,
    required this.createRepository,
  });

  final String name;
  final CurrentUserProfileRepository Function(
    CurrentUserProfileContractScenario scenario,
  )
  createRepository;
}

void runCurrentUserProfileRepositoryContractSuite(
  CurrentUserProfileRepositoryContractDriver Function() createDriver,
) {
  final name = createDriver().name;
  group('CurrentUserProfileRepository contract: $name', () {
    test(
      'returns authenticated identity, optional fields and metadata',
      () async {
        final result = await createDriver()
            .createRepository(CurrentUserProfileContractScenario.populated)
            .load(const CurrentUserProfileQuery());

        final success =
            result
                as DataReadSuccess<
                  CurrentUserProfileData,
                  CurrentUserProfileReadCapabilities
                >;
        expect(success.data.identity.userId, '42');
        expect(success.data.identity.displayName, 'Alice');
        expect(success.data.creditTotal, 12);
        expect(success.data.postCount, 34);
        expect(success.data.threadCount, 5);
        expect(
          success.capabilities.supports(
            CurrentUserProfileCapability.stableUserIdentity,
          ),
          isTrue,
        );
        expect(
          success.capabilities.supports(CurrentUserProfileCapability.postCount),
          isTrue,
        );
        expect(success.metadata.origin, DataReadOrigin.network);
        expect(success.metadata.freshness, DataReadFreshness.current);
      },
    );

    test('keeps absent optional fields null and fail-closed', () async {
      final result = await createDriver()
          .createRepository(
            CurrentUserProfileContractScenario.missingOptionalFields,
          )
          .load(const CurrentUserProfileQuery());
      final success =
          result
              as DataReadSuccess<
                CurrentUserProfileData,
                CurrentUserProfileReadCapabilities
              >;

      expect(success.data.avatarUrl, isNull);
      expect(success.data.groupId, isNull);
      expect(success.data.creditTotal, isNull);
      expect(
        success.capabilities.supports(
          CurrentUserProfileCapability.avatarReference,
        ),
        isFalse,
      );
      expect(
        success.capabilities.supports(CurrentUserProfileCapability.creditTotal),
        isFalse,
      );
    });

    test('maps anonymous identity to unauthorized', () async {
      final result = await createDriver()
          .createRepository(CurrentUserProfileContractScenario.anonymous)
          .load(const CurrentUserProfileQuery());

      expect(result.failureOrNull?.kind, DataReadFailureKind.unauthorized);
    });

    for (final scenario in const <CurrentUserProfileContractScenario>[
      CurrentUserProfileContractScenario.missingSpace,
      CurrentUserProfileContractScenario.identityMismatch,
      CurrentUserProfileContractScenario.nameMismatch,
      CurrentUserProfileContractScenario.malformedNumber,
    ]) {
      test('fails closed for ${scenario.name}', () async {
        final result = await createDriver()
            .createRepository(scenario)
            .load(const CurrentUserProfileQuery());

        expect(result.failureOrNull?.kind, DataReadFailureKind.parse);
      });
    }

    for (final entry
        in const <(CurrentUserProfileContractScenario, DataReadFailureKind)>[
          (
            CurrentUserProfileContractScenario.networkFailure,
            DataReadFailureKind.network,
          ),
          (
            CurrentUserProfileContractScenario.timeout,
            DataReadFailureKind.timeout,
          ),
          (
            CurrentUserProfileContractScenario.cancelled,
            DataReadFailureKind.cancelled,
          ),
          (
            CurrentUserProfileContractScenario.unauthorized,
            DataReadFailureKind.unauthorized,
          ),
          (
            CurrentUserProfileContractScenario.serverFailure,
            DataReadFailureKind.server,
          ),
          (
            CurrentUserProfileContractScenario.businessFailure,
            DataReadFailureKind.business,
          ),
        ]) {
      test('classifies ${entry.$1.name}', () async {
        final result = await createDriver()
            .createRepository(entry.$1)
            .load(const CurrentUserProfileQuery());

        expect(result.failureOrNull?.kind, entry.$2);
        expect(result.failureOrNull?.diagnosticMessage, isNot(contains('<')));
      });
    }
  });
}
