import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/startup/message_attention_network_host_provider.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/auth/application/auth_session_controller.dart';
import 'package:y300/features/auth/application/verified_session_owner.dart';
import 'package:y300/features/messages/application/message_attention_providers.dart';

const _signedIn = AuthSessionViewState(
  isLoggedIn: true,
  uid: '42',
  username: 'synthetic member',
  isLoggingOut: false,
);
const _positive = ForumMessageAttentionObservation(
  viewerUserId: '42',
  source: ForumMessageAttentionSource.mobileHtml,
  combinedHint: ForumMessageAttentionState.present,
);

void main() {
  test('client host construction does not initialize authentication', () {
    var builds = 0;
    final container = ProviderContainer(
      overrides: [
        authSessionControllerProvider.overrideWith(() {
          builds++;
          return _Auth();
        }),
      ],
    );
    addTearDown(container.dispose);
    final host = container.read(messageAttentionNetworkHostProvider);
    expect(builds, 0);
    expect(host.captureRequest(), isNull);
    expect(builds, 0);
  });

  test(
    'verified owner drives state and same-UID relogin rejects old work',
    () async {
      final sessions = YamiboSessionStore()..saveExtracted(_snapshot());
      final container = _container(sessions);
      container.listen(messageAttentionStateProvider, (_, _) {});
      await container.read(authSessionControllerProvider.future);
      await container.read(sessionRevisionProvider.future);
      await container.pump();
      final controller = container.read(messageAttentionControllerProvider);
      final host = container.read(messageAttentionNetworkHostProvider);
      final owner = controller.value.owner!;
      final oldRequest = host.captureRequest()!;
      host.onObservation(_positive, context: oldRequest);
      controller.acknowledgeMore();
      expect(
        container.read(messageAttentionStateProvider).hasAttention,
        isTrue,
      );

      sessions.clear();
      await container.pump();
      expect(container.read(messageAttentionStateProvider).owner, isNull);
      expect(host.captureRequest(), isNull);

      sessions.saveExtracted(_snapshot());
      await container.pump();
      final nextOwner = controller.value.owner!;
      expect(nextOwner.sessionOwner.uid, owner.sessionOwner.uid);
      expect(
        nextOwner.sessionOwner.revision,
        greaterThan(owner.sessionOwner.revision),
      );
      expect(nextOwner.sourceGeneration, greaterThan(owner.sourceGeneration));
      host.onObservation(_positive, context: oldRequest);
      expect(
        container.read(messageAttentionStateProvider).hasAttention,
        isFalse,
      );

      host.onObservation(_positive, context: host.captureRequest()!);
      final state = container.read(messageAttentionStateProvider);
      expect(state.hasUnacknowledgedAttention, isTrue);
      expect(state.attentionEpoch, 1);
      expect(state.acknowledgedMoreEpoch, 0);
    },
  );

  test('logging out revokes the owner before the store is cleared', () async {
    final sessions = YamiboSessionStore()..saveExtracted(_snapshot());
    final container = _container(sessions);
    container.listen(messageAttentionStateProvider, (_, _) {});
    await container.read(authSessionControllerProvider.future);
    await container.read(sessionRevisionProvider.future);
    await container.pump();
    final host = container.read(messageAttentionNetworkHostProvider);
    final context = host.captureRequest()!;
    host.onObservation(_positive, context: context);
    (container.read(authSessionControllerProvider.notifier) as _Auth)
        .startLogout();
    await container.pump();
    expect(sessions.readCurrent()!.isLoggedIn, isTrue);
    expect(container.read(messageAttentionStateProvider).hasAttention, isFalse);
    expect(host.captureRequest(), isNull);
    host.onObservation(_positive, context: context);
    expect(container.read(messageAttentionStateProvider).hasAttention, isFalse);
  });
}

ProviderContainer _container(YamiboSessionStore sessions) {
  final container = ProviderContainer(
    overrides: [
      yamiboSessionStoreProvider.overrideWithValue(sessions),
      authSessionControllerProvider.overrideWith(_Auth.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _Auth extends AuthSessionController {
  @override
  Future<AuthSessionViewState> build() async => _signedIn;

  void startLogout() {
    state = AsyncData(_signedIn.copyWith(isLoggingOut: true));
  }
}

YamiboSessionSnapshot _snapshot() => YamiboSessionSnapshot(
  isLoggedIn: true,
  uid: '42',
  username: 'synthetic member',
  formhash: '',
  updatedAt: DateTime.utc(2026, 10, 11),
  source: 'test',
);
