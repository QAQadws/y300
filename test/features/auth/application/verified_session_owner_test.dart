import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/auth/application/auth_session_controller.dart';
import 'package:y300/features/auth/application/verified_session_owner.dart';

const _signedIn = AuthSessionViewState(
  isLoggedIn: true,
  uid: '101',
  username: 'member',
  isLoggingOut: false,
);

void main() {
  test('cached store identity never grants an unverified owner', () {
    final snapshot = _snapshot('101');
    final unverified = <AsyncValue<AuthSessionViewState>>[
      const AsyncLoading(),
      AsyncError(StateError('verification_failed'), StackTrace.current),
      const AsyncData(AuthSessionViewState.signedOut()),
      const AsyncData(
        AuthSessionViewState.signedOut(verificationInconclusive: true),
      ),
      AsyncData(_signedIn.copyWith(isLoggingOut: true)),
    ];

    for (final auth in unverified) {
      expect(
        verifiedSessionOwner(auth, const AsyncData(0), snapshot),
        isNull,
        reason: 'Only a verified, active authentication grants an owner.',
      );
    }
  });

  test('owner requires a valid positive user identity', () {
    for (final uid in ['', '0', '-1', 'member']) {
      expect(
        verifiedSessionOwner(
          AsyncData(_signedIn.copyWith(uid: uid)),
          const AsyncData(0),
          _snapshot(uid),
        ),
        isNull,
        reason: 'Invalid account identity: $uid',
      );
    }
  });

  test('verified authentication waits for the session revision', () {
    for (final revision in <AsyncValue<int>>[
      const AsyncLoading(),
      AsyncError(StateError('revision_failed'), StackTrace.current),
    ]) {
      expect(
        verifiedSessionOwner(
          const AsyncData(_signedIn),
          revision,
          _snapshot('101'),
        ),
        isNull,
      );
    }
  });

  test('store confirmation must belong to the authenticated account', () {
    for (final snapshot in [
      _snapshot('202'),
      _snapshot('101', isLoggedIn: false),
    ]) {
      expect(
        verifiedSessionOwner(
          const AsyncData(_signedIn),
          const AsyncData(3),
          snapshot,
        ),
        isNull,
      );
    }
    expect(
      verifiedSessionOwner(
        AsyncData(_signedIn.copyWith(uid: ' 101 ')),
        const AsyncData(3),
        _snapshot(' 101 '),
      ),
      (uid: '101', revision: 3),
    );
  });

  test('empty initial store differs from a cleared session store', () {
    expect(
      verifiedSessionOwner(
        const AsyncData(_signedIn),
        const AsyncData(0),
        null,
      ),
      (uid: '101', revision: 0),
    );
    expect(
      verifiedSessionOwner(
        const AsyncData(_signedIn),
        const AsyncData(1),
        null,
      ),
      isNull,
    );
  });

  test(
    'same UID relogin creates a new owner but formhash renewal does not',
    () async {
      final sessions = YamiboSessionStore()..saveExtracted(_snapshot('101'));
      final container = _container(sessions);
      container.listen(verifiedSessionOwnerProvider, (_, _) {});
      await container.read(authSessionControllerProvider.future);
      await container.read(sessionRevisionProvider.future);
      await container.pump();

      final original = container.read(verifiedSessionOwnerProvider);
      expect(original, isNotNull);

      sessions.saveExtracted(_snapshot('101', formhash: 'renewed'));
      await container.pump();
      expect(container.read(verifiedSessionOwnerProvider), original);

      // The old auth projection may remain until its own refresh completes.
      sessions.clear();
      await container.pump();
      expect(container.read(verifiedSessionOwnerProvider), isNull);

      sessions.saveExtracted(_snapshot('101'));
      await container.pump();
      final reopened = container.read(verifiedSessionOwnerProvider);
      expect(reopened?.uid, original!.uid);
      expect(reopened?.revision, greaterThan(original.revision));
      expect(reopened, isNot(original));
    },
  );

  test(
    'first anonymous store confirmation revokes a startup API owner',
    () async {
      final sessions = YamiboSessionStore();
      final container = _container(sessions);
      container.listen(verifiedSessionOwnerProvider, (_, _) {});
      await container.read(authSessionControllerProvider.future);
      await container.read(sessionRevisionProvider.future);
      await container.pump();
      expect(container.read(verifiedSessionOwnerProvider), (
        uid: '101',
        revision: 0,
      ));

      sessions.saveExtracted(_snapshot('0', isLoggedIn: false));
      await container.pump();
      expect(container.read(verifiedSessionOwnerProvider), isNull);

      sessions.saveExtracted(_snapshot('101'));
      await container.pump();
      final confirmed = container.read(verifiedSessionOwnerProvider);
      expect(confirmed?.uid, '101');
      expect(confirmed?.revision, greaterThan(0));
    },
  );
}

ProviderContainer _container(YamiboSessionStore sessions) {
  final container = ProviderContainer(
    overrides: [
      yamiboSessionStoreProvider.overrideWithValue(sessions),
      authSessionControllerProvider.overrideWith(_SignedInAuthController.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _SignedInAuthController extends AuthSessionController {
  @override
  Future<AuthSessionViewState> build() async => _signedIn;
}

YamiboSessionSnapshot _snapshot(
  String uid, {
  bool isLoggedIn = true,
  String formhash = 'proof',
}) => YamiboSessionSnapshot(
  isLoggedIn: isLoggedIn,
  uid: uid,
  username: isLoggedIn ? 'member' : '',
  formhash: formhash,
  updatedAt: DateTime.utc(2026, 10, 4),
  source: 'test',
);
