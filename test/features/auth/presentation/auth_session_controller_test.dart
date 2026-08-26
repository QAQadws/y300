import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/auth/data/providers/auth_contract_providers.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';

void main() {
  test('inconclusive refresh preserves a previously proved identity', () async {
    final sessions = _SequenceSessionRepository(<ForumSessionResult>[
      const ForumSessionAuthenticated(
        ForumSessionIdentity(userId: '42', username: 'reader'),
      ),
      const ForumSessionInconclusive(
        DataCommandFailure(
          kind: DataCommandFailureKind.timeout,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'profile_timeout',
          diagnosticMessage: 'profile_timeout',
        ),
      ),
    ]);
    final container = ProviderContainer(
      overrides: [
        forumSessionRepositoryProvider.overrideWithValue(sessions),
        forumLogoutCommandProvider.overrideWithValue(
          const _OutcomeUnknownLogout(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final initial = await container.read(authSessionControllerProvider.future);
    expect(initial.isLoggedIn, isTrue);

    await container.read(authSessionControllerProvider.notifier).refresh();
    final refreshed = await container.read(
      authSessionControllerProvider.future,
    );

    expect(refreshed.isLoggedIn, isTrue);
    expect(refreshed.uid, '42');
    expect(refreshed.username, 'reader');
  });

  test('inconclusive logout keeps the current authenticated state', () async {
    final container = ProviderContainer(
      overrides: [
        forumSessionRepositoryProvider.overrideWithValue(
          _SequenceSessionRepository(<ForumSessionResult>[
            const ForumSessionAuthenticated(
              ForumSessionIdentity(userId: '42', username: 'reader'),
            ),
          ]),
        ),
        forumLogoutCommandProvider.overrideWithValue(
          const _OutcomeUnknownLogout(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.future);

    final applied = await container
        .read(authSessionControllerProvider.notifier)
        .logout();
    final state = await container.read(authSessionControllerProvider.future);

    expect(applied, isFalse);
    expect(state.isLoggedIn, isTrue);
    expect(state.isLoggingOut, isFalse);
    expect(state.logoutFailure, isA<DataCommandFailure>());
  });
}

final class _SequenceSessionRepository implements ForumSessionRepository {
  _SequenceSessionRepository(this._results);

  final List<ForumSessionResult> _results;

  @override
  Future<ForumSessionResult> resolve([
    ForumSessionRequest request = const ForumSessionRequest(),
  ]) async => _results.removeAt(0);
}

final class _OutcomeUnknownLogout implements ForumLogoutCommand {
  const _OutcomeUnknownLogout();

  @override
  Future<DataCommandResult<ForumLogoutReceipt>> execute([
    ForumLogoutRequest request = const ForumLogoutRequest(),
  ]) async => const DataCommandOutcomeUnknown<ForumLogoutReceipt>(
    DataCommandFailure(
      kind: DataCommandFailureKind.timeout,
      retryPolicy: DataCommandRetryPolicy.explicitOnly,
      code: 'logout_timeout',
      diagnosticMessage: 'logout_timeout',
    ),
  );
}
