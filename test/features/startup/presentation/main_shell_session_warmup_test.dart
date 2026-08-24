import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/startup/presentation/main_shell_page.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

void main() {
  test(
    'session warmup reads the source-neutral current profile contract',
    () async {
      final repository = _RecordingProfileRepository();
      final container = ProviderContainer(
        overrides: [
          yamiboForumClientProvider.overrideWithValue(_client(repository)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(mainShellYamiboSessionWarmupProvider).call();

      expect(repository.calls, 1);
      expect(repository.lastPolicy, CacheLoadPolicy.networkFirst);
    },
  );

  test('session warmup remains best effort when the contract throws', () async {
    final repository = _RecordingProfileRepository(shouldThrow: true);
    final container = ProviderContainer(
      overrides: [
        yamiboForumClientProvider.overrideWithValue(_client(repository)),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(mainShellYamiboSessionWarmupProvider).call(),
      completes,
    );
    expect(repository.calls, 1);
  });
}

YamiboForumClient _client(CurrentUserProfileRepository repository) {
  return YamiboForumClient(
    config: ForumClientConfig(
      siteOrigin: Uri.parse('https://bbs.example.invalid'),
    ),
    network: _UnusedNetwork(),
    sourcePlan: ForumClientSourcePlan(currentUserProfile: repository),
  );
}

final class _RecordingProfileRepository
    implements CurrentUserProfileRepository {
  _RecordingProfileRepository({this.shouldThrow = false});

  final bool shouldThrow;
  int calls = 0;
  CacheLoadPolicy? lastPolicy;

  @override
  CurrentUserProfileSourceCapabilities get capabilities =>
      CurrentUserProfileSourceCapabilities(
        values: DataCapabilitySet.from(
          unsupported: CurrentUserProfileCapability.values,
        ),
      );

  @override
  Future<
    DataReadResult<CurrentUserProfileData, CurrentUserProfileReadCapabilities>
  >
  load(
    CurrentUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    calls += 1;
    lastPolicy = cachePolicy;
    if (shouldThrow) throw StateError('fixture_failure');
    return const DataReadFailure(
      kind: DataReadFailureKind.network,
      code: 'fixture_network',
      diagnosticMessage: 'fixture_network',
    );
  }
}

final class _UnusedNetwork implements ForumClientNetwork {
  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async => const ForumTransportError(
    ForumTransportFailure(
      kind: ForumTransportFailureKind.unknown,
      code: 'unused',
    ),
  );
}
