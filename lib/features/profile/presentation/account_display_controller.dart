import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/config/technical_storage_keys.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/core/preferences/preference_key.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';

/// This pointer is deliberately separate from authenticated session ownership.
final accountDisplayControllerProvider =
    NotifierProvider<AccountDisplayController, String?>(
      AccountDisplayController.new,
    );

class AccountDisplayController extends Notifier<String?> {
  int _generation = 0;
  Future<void> _writes = Future.value();
  static final storageKey = PreferenceKey<String>(
    '${TechnicalStorageKeys.accountDisplayUidV1Prefix}${Uri.parse(AppConfig.siteBaseUrl).origin}',
  );

  @override
  String? build() {
    ref.listen(authSessionControllerProvider, (_, _) => _reconcile());
    ref.listen(verifiedProfileOwnerProvider, (_, _) => _reconcile());
    final generation = _generation;
    unawaited(
      Future<void>.microtask(() async {
        try {
          final uid = await ref.read(preferencesStoreProvider).read(storageKey);
          if (ref.mounted &&
              generation == _generation &&
              uid != null &&
              RegExp(r'^[1-9]\d*$').hasMatch(uid)) {
            state = uid;
          }
        } on Object {
          // A missing or unavailable local preview must not affect authentication.
        }
        if (ref.mounted) _reconcile();
      }),
    );
    return null;
  }

  void _reconcile() {
    final auth = ref.read(authSessionControllerProvider).asData?.value;
    final owner = ref.read(verifiedProfileOwnerProvider);
    if (owner != null) {
      _set(owner.uid);
      return;
    }
    if (auth == null || auth.verificationInconclusive) return;
    if (auth.isLoggingOut || !auth.isLoggedIn) {
      clear();
      return;
    }
    final snapshot = ref.read(yamiboSessionStoreProvider).readCurrent();
    final revision = ref.read(profileSessionRevisionProvider).asData?.value;
    if ((snapshot != null &&
            (!snapshot.isLoggedIn || snapshot.uid != auth.uid)) ||
        (snapshot == null && revision != null && revision > 0)) {
      clear();
    } else if (state != null && state != auth.uid) {
      // Hide the previous account while the new verified owner is being built.
      clear();
    }
  }

  void clear() => _set(null);

  void _set(String? uid) {
    final generation = ++_generation;
    state = uid;
    final store = ref.read(preferencesStoreProvider);
    // Serialize persistence so an older login cannot finish after logout.
    _writes = _writes.then((_) async {
      if (!ref.mounted || generation != _generation) return;
      try {
        if (uid == null) {
          await store.remove(storageKey);
        } else {
          await store.write(storageKey, uid);
        }
      } on Object {
        // Session-local state remains authoritative if persistence is unavailable.
      }
    });
  }
}
