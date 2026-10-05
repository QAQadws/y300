import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';

typedef Y300ForumSourcePlanFactory =
    ForumClientSourcePlan Function(YamiboForumClientBuilder builder);

/// A boot-time source composition, kept out of feature and page code.
final class Y300ForumSourceProfile {
  const Y300ForumSourceProfile({
    required this.id,
    required this.revision,
    this.createOverrides,
  });

  static const parsing = Y300ForumSourceProfile(id: 'parsing', revision: 1);

  final String id;
  final int revision;
  final Y300ForumSourcePlanFactory? createOverrides;

  YamiboForumClient build(YamiboForumClientBuilder builder) =>
      builder.buildStandardClient(
        sourceOverrides:
            createOverrides?.call(builder) ?? const ForumClientSourcePlan(),
      );
}

/// Only implemented profiles may be selected. Unknown IDs fail closed.
final class Y300ForumSourceCatalog {
  Y300ForumSourceCatalog(Iterable<Y300ForumSourceProfile> profiles) {
    for (final profile in profiles) {
      if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(profile.id) ||
          profile.revision < 1 ||
          _profiles.containsKey(profile.id)) {
        throw ArgumentError('invalid_forum_source_catalog');
      }
      _profiles[profile.id] = profile;
    }
    if (_profiles.isEmpty) throw ArgumentError('invalid_forum_source_catalog');
  }

  final Map<String, Y300ForumSourceProfile> _profiles = {};

  Y300ForumSourceProfile resolve(String id) =>
      _profiles[id] ?? (throw StateError('forum_source_not_available:$id'));
}

final yamiboForumSourceCatalogProvider = Provider<Y300ForumSourceCatalog>(
  (ref) => Y300ForumSourceCatalog(const [Y300ForumSourceProfile.parsing]),
);

/// A future persisted selection is resolved here at startup. Saving it must
/// not invalidate this provider during a running process.
final yamiboForumSourceProfileProvider = Provider<Y300ForumSourceProfile>(
  (ref) => ref.watch(yamiboForumSourceCatalogProvider).resolve('parsing'),
);

/// Identity of a request flow and the cache partition it may access.
final class Y300ForumSourceScope {
  Y300ForumSourceScope._({
    required this.profile,
    required this.accountId,
    required this.generation,
  });

  final Y300ForumSourceProfile profile;
  final String accountId;
  final int generation;
  final ForumRequestCancellation cancellation = ForumRequestCancellation();

  bool get isCurrent => !cancellation.isCancelled;
  bool get hasVerifiedIdentity => accountId != 'unverified';

  /// Persistent identity excludes the in-process generation; returning to an
  /// account can reuse its own compatible snapshots, never another account's.
  /// The startup read adapter may supply an exact Cookie-bound cache owner;
  /// this does not change this scope's verified identity or write permission.
  String cacheKey(String original, {String? cacheAccountId}) =>
      _cacheKey(original, cacheAccountId ?? accountId);

  /// Explicit public reads can use the anonymous partition before the first
  /// remote session confirmation. This never permits privileged cache writes.
  String anonymousCacheKey(String original) => _cacheKey(original, 'anonymous');

  String _cacheKey(String original, String account) =>
      'forum_source_v1|${profile.id}|${profile.revision}|'
      '${Uri.encodeComponent(account)}|$original';
}

/// Owns the active source for one process and cancels old account flows.
final class Y300ForumSourceRuntime {
  Y300ForumSourceRuntime({
    required this.profile,
    required YamiboSessionStore sessions,
  }) : _sessions = sessions {
    _current = _newScope();
    _subscription = sessions.identityChanges.listen((_) {
      _current.cancellation.cancel();
      _generation++;
      _current = _newScope();
      _changes.add(_current);
    });
  }

  final Y300ForumSourceProfile profile;
  final YamiboSessionStore _sessions;
  final StreamController<Y300ForumSourceScope> _changes =
      StreamController<Y300ForumSourceScope>.broadcast(sync: true);
  late final StreamSubscription<void> _subscription;
  late Y300ForumSourceScope _current;
  int _generation = 0;

  Y300ForumSourceScope get current => _current;
  Stream<Y300ForumSourceScope> get changes => _changes.stream;

  Y300ForumSourceScope _newScope() {
    final identity = _sessions.readCurrent();
    final accountId = identity == null
        ? 'unverified'
        : identity.isLoggedIn && identity.uid.trim().isNotEmpty
        ? identity.uid.trim()
        : 'anonymous';
    return Y300ForumSourceScope._(
      profile: profile,
      accountId: accountId,
      generation: _generation,
    );
  }

  void dispose() {
    _current.cancellation.cancel();
    unawaited(_subscription.cancel());
    unawaited(_changes.close());
  }
}

final yamiboForumSourceRuntimeProvider = Provider<Y300ForumSourceRuntime>((
  ref,
) {
  final runtime = Y300ForumSourceRuntime(
    profile: ref.watch(yamiboForumSourceProfileProvider),
    sessions: ref.watch(yamiboSessionStoreProvider),
  );
  ref.onDispose(runtime.dispose);
  return runtime;
});

final yamiboForumSourceScopeProvider =
    NotifierProvider<Y300ForumSourceScopeController, Y300ForumSourceScope>(
      Y300ForumSourceScopeController.new,
    );

final class Y300ForumSourceScopeController
    extends Notifier<Y300ForumSourceScope> {
  @override
  Y300ForumSourceScope build() {
    final runtime = ref.watch(yamiboForumSourceRuntimeProvider);
    final subscription = runtime.changes.listen((scope) => state = scope);
    ref.onDispose(subscription.cancel);
    return runtime.current;
  }
}
