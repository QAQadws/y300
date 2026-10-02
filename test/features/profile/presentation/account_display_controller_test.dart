import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/preferences/preference_key.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/profile/presentation/account_display_controller.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';

final _auth = StateProvider<Future<AuthSessionViewState>>(
  (_) => Future.value(
    const AuthSessionViewState.signedOut(verificationInconclusive: true),
  ),
);
final _owner = StateProvider<VerifiedProfileOwner?>((_) => null);

void main() {
  test(
    'startup preview survives offline verification but grants no owner',
    () async {
      final preferences = _Preferences('42');
      final verification = Completer<AuthSessionViewState>();
      final container = _container(preferences, verification.future);
      container.listen(accountDisplayControllerProvider, (_, _) {});
      await _flush();
      expect(container.read(accountDisplayControllerProvider), '42');
      expect(container.read(verifiedProfileOwnerProvider), isNull);
      verification.complete(
        const AuthSessionViewState.signedOut(verificationInconclusive: true),
      );
      await _flush();
      expect(container.read(accountDisplayControllerProvider), '42');
      expect(preferences.uid, '42');
      container.read(_auth.notifier).state = Future.value(
        const AuthSessionViewState.signedOut(),
      );
      await _flush();
      expect(container.read(accountDisplayControllerProvider), isNull);
      expect(preferences.uid, isNull);
    },
  );

  test(
    'account changes persist only the last pointer and logout clears it',
    () async {
      final preferences = _Preferences('42');
      final container = _container(
        preferences,
        Future.value(
          const AuthSessionViewState.signedOut(verificationInconclusive: true),
        ),
      );
      container.listen(accountDisplayControllerProvider, (_, _) {});
      await _flush();
      container.read(_owner.notifier).state = (uid: '43', revision: 1);
      await _flush();
      expect(container.read(accountDisplayControllerProvider), '43');
      expect(preferences.uid, '43');
      container.read(_owner.notifier).state = null;
      container.read(_auth.notifier).state = Future.value(
        const AuthSessionViewState.signedOut(),
      );
      await _flush();
      expect(container.read(accountDisplayControllerProvider), isNull);
      expect(preferences.uid, isNull);
    },
  );

  test(
    'late disk read cannot restore the old account after a new login',
    () async {
      final preferences = _Preferences('42')
        ..pendingRead = Completer<String?>();
      final container = _container(
        preferences,
        Future.value(
          const AuthSessionViewState.signedOut(verificationInconclusive: true),
        ),
      );
      container.listen(accountDisplayControllerProvider, (_, _) {});
      await _flush();
      container.read(_owner.notifier).state = (uid: '43', revision: 1);
      await _flush();
      preferences.pendingRead!.complete('42');
      await _flush();
      expect(container.read(accountDisplayControllerProvider), '43');
      expect(preferences.uid, '43');
    },
  );

  test(
    'preference failures never grant identity or throw into presentation',
    () async {
      final preferences = _Preferences(null)..fail = true;
      final container = _container(
        preferences,
        Future.value(
          const AuthSessionViewState.signedOut(verificationInconclusive: true),
        ),
      );
      container.listen(accountDisplayControllerProvider, (_, _) {});
      await _flush();
      expect(container.read(accountDisplayControllerProvider), isNull);
      container.read(_owner.notifier).state = (uid: '42', revision: 1);
      await _flush();
      expect(container.read(accountDisplayControllerProvider), '42');
    },
  );
}

ProviderContainer _container(
  _Preferences preferences,
  Future<AuthSessionViewState> initial,
) {
  final container = ProviderContainer(
    overrides: [
      _auth.overrideWith((_) => initial),
      authSessionControllerProvider.overrideWith(_AuthController.new),
      verifiedProfileOwnerProvider.overrideWith((ref) => ref.watch(_owner)),
      preferencesStoreProvider.overrideWithValue(preferences),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _AuthController extends AuthSessionController {
  @override
  Future<AuthSessionViewState> build() => ref.watch(_auth);
}

class _Preferences implements PreferencesStore {
  _Preferences(this.uid);
  String? uid;
  bool fail = false;
  Completer<String?>? pendingRead;
  @override
  Future<T?> read<T extends Object>(PreferenceKey<T> key) async {
    if (fail) throw StateError('synthetic storage failure');
    return (pendingRead != null ? await pendingRead!.future : uid) as T?;
  }

  @override
  Future<void> write<T extends Object>(PreferenceKey<T> key, T value) async {
    if (fail) throw StateError('synthetic storage failure');
    uid = value as String;
  }

  @override
  Future<void> remove<T extends Object>(PreferenceKey<T> key) async {
    if (fail) throw StateError('synthetic storage failure');
    uid = null;
  }

  @override
  Future<bool> contains<T extends Object>(PreferenceKey<T> key) async =>
      uid != null;
}
