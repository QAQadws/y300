import 'dart:async';

import 'package:y300/core/network/yamibo/yamibo_session_store.dart';

/// Every local browser belongs to its opening identity, including guest routes.
/// Confirming an anonymous session is safe; a different actor expires it forever.
final class ForumWebViewSessionOwner {
  ForumWebViewSessionOwner({
    required YamiboSessionStore sessions,
    required void Function() onExpired,
  }) {
    (bool, String) identity() {
      final current = sessions.readCurrent();
      return current?.isLoggedIn == true ? (true, current!.uid) : (false, '');
    }

    final openingIdentity = identity();
    _subscription = sessions.identityChanges.listen((_) {
      if (!isCurrent || identity() == openingIdentity) return;
      _expired = true;
      onExpired();
    });
  }

  late final StreamSubscription<void> _subscription;
  bool _expired = false;
  bool _disposed = false;

  bool get isCurrent => !_expired && !_disposed;

  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
  }
}
