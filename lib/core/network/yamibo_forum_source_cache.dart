import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:y300/core/network/yamibo_forum_home_cache_owner.dart';
import 'package:y300/core/network/yamibo_forum_source.dart';

/// Decorates existing cache ports without changing on-disk payload codecs.
final class Y300ScopedForumDocumentStore implements ForumDocumentStore {
  const Y300ScopedForumDocumentStore(
    this.delegate,
    this.scope, {
    this.homeCacheOwners,
  });

  final ForumDocumentStore delegate;
  final Y300ForumSourceScope scope;
  final Y300ForumHomeCacheOwnerStore? homeCacheOwners;

  bool get _canAccess => scope.isCurrent && scope.hasVerifiedIdentity;

  @override
  Future<ForumCachedDocument?> get(ForumDocumentDescriptor descriptor) async {
    final owner = await _restoreHomeOwner(
      descriptor.ownerType,
      descriptor.ownerId,
      descriptor.cacheKey,
      scope,
      homeCacheOwners,
    );
    if (!_canRead(descriptor.cacheKey, scope) && owner == null) return null;
    var cached = await delegate.get(
      _descriptor(descriptor, cacheAccountId: owner?.accountId),
    );
    if (cached == null && _legacyAnonymous(descriptor.cacheKey, scope)) {
      cached = await delegate.get(descriptor);
    }
    if (!scope.isCurrent ||
        (owner != null
            ? !owner.isCurrent
            : !_canRead(descriptor.cacheKey, scope)) ||
        cached == null) {
      return null;
    }
    return _document(cached, descriptor);
  }

  @override
  Future<void> put(ForumCachedDocument document) async {
    if (!_canAccess || !_matchesAudience(document.descriptor.cacheKey, scope)) {
      return;
    }
    await delegate.put(_document(document, _descriptor(document.descriptor)));
  }

  @override
  Future<void> touch(
    ForumDocumentDescriptor descriptor,
    DateTime accessedAt,
  ) async {
    if (!_canRead(descriptor.cacheKey, scope)) return;
    await delegate.touch(_descriptor(descriptor), accessedAt);
    if (_canRead(descriptor.cacheKey, scope) &&
        _legacyAnonymous(descriptor.cacheKey, scope)) {
      await delegate.touch(descriptor, accessedAt);
    }
  }

  ForumDocumentDescriptor _descriptor(
    ForumDocumentDescriptor value, {
    String? cacheAccountId,
  }) => ForumDocumentDescriptor(
    cacheKey: _scopedKey(value.cacheKey, scope, cacheAccountId: cacheAccountId),
    ownerType: value.ownerType,
    ownerId: value.ownerId,
    sourceUri: value.sourceUri,
    requestProfile: value.requestProfile,
  );
}

final class Y300ScopedForumSnapshotStore implements ForumSnapshotStore {
  const Y300ScopedForumSnapshotStore(
    this.delegate,
    this.scope, {
    this.homeCacheOwners,
  });

  final ForumSnapshotStore delegate;
  final Y300ForumSourceScope scope;
  final Y300ForumHomeCacheOwnerStore? homeCacheOwners;

  bool get _canAccess => scope.isCurrent && scope.hasVerifiedIdentity;

  @override
  Future<ForumCachedSnapshot<T>?> get<T>(
    ForumSnapshotDescriptor descriptor,
    ForumSnapshotCodec<T> codec,
  ) async {
    final owner = await _restoreHomeOwner(
      descriptor.ownerType,
      descriptor.ownerId,
      descriptor.cacheKey,
      scope,
      homeCacheOwners,
    );
    if (!_canRead(descriptor.cacheKey, scope) && owner == null) return null;
    var cached = await delegate.get(
      _descriptor(descriptor, cacheAccountId: owner?.accountId),
      codec,
    );
    if (cached == null && _legacyAnonymous(descriptor.cacheKey, scope)) {
      cached = await delegate.get(descriptor, codec);
    }
    if (!scope.isCurrent ||
        (owner != null
            ? !owner.isCurrent
            : !_canRead(descriptor.cacheKey, scope)) ||
        cached == null) {
      return null;
    }
    return ForumCachedSnapshot<T>(
      descriptor: descriptor,
      codecVersion: cached.codecVersion,
      parserVersion: cached.parserVersion,
      value: cached.value,
      createdAt: cached.createdAt,
      updatedAt: cached.updatedAt,
      lastAccessedAt: cached.lastAccessedAt,
      staleAt: cached.staleAt,
      expiresAt: cached.expiresAt,
    );
  }

  @override
  Future<void> put<T>(
    ForumSnapshotDescriptor descriptor,
    T value,
    ForumSnapshotCodec<T> codec, {
    required ForumSnapshotPolicy policy,
  }) async {
    if (!_canAccess || !_matchesAudience(descriptor.cacheKey, scope)) return;
    await delegate.put(_descriptor(descriptor), value, codec, policy: policy);
  }

  @override
  Future<void> touch(
    ForumSnapshotDescriptor descriptor,
    DateTime accessedAt,
  ) async {
    if (!_canRead(descriptor.cacheKey, scope)) return;
    await delegate.touch(_descriptor(descriptor), accessedAt);
    if (_canRead(descriptor.cacheKey, scope) &&
        _legacyAnonymous(descriptor.cacheKey, scope)) {
      await delegate.touch(descriptor, accessedAt);
    }
  }

  ForumSnapshotDescriptor _descriptor(
    ForumSnapshotDescriptor value, {
    String? cacheAccountId,
  }) => ForumSnapshotDescriptor(
    cacheKey: _scopedKey(value.cacheKey, scope, cacheAccountId: cacheAccountId),
    ownerType: value.ownerType,
    ownerId: value.ownerId,
    snapshotType: value.snapshotType,
    sourceDocumentKey: value.sourceDocumentKey == null
        ? null
        : _scopedKey(
            value.sourceDocumentKey!,
            scope,
            cacheAccountId: cacheAccountId,
          ),
  );
}

// Legacy logged-in entries have no proven UID and must never migrate into a
// verified account. Anonymous parsing entries remain a read-only fallback.
bool _legacyAnonymous(String key, Y300ForumSourceScope scope) =>
    scope.profile.id == Y300ForumSourceProfile.parsing.id &&
    scope.profile.revision == Y300ForumSourceProfile.parsing.revision &&
    (scope.accountId == 'anonymous' || !scope.hasVerifiedIdentity) &&
    key.contains('|anonymous|');

bool _matchesAudience(String key, Y300ForumSourceScope scope) =>
    !key.contains('|logged_in|') || scope.accountId != 'anonymous';

bool _canRead(String key, Y300ForumSourceScope scope) =>
    scope.isCurrent &&
    (scope.hasVerifiedIdentity && _matchesAudience(key, scope) ||
        key.contains('|anonymous|'));

String _scopedKey(
  String key,
  Y300ForumSourceScope scope, {
  String? cacheAccountId,
}) =>
    cacheAccountId == null &&
        !scope.hasVerifiedIdentity &&
        key.contains('|anonymous|')
    ? scope.anonymousCacheKey(key)
    : scope.cacheKey(key, cacheAccountId: cacheAccountId);

bool _isAuthenticatedHome(String ownerType, String ownerId, String key) =>
    ownerType == 'forum' && ownerId == 'home' && key.contains('|logged_in|');

Future<Y300ForumHomeCacheOwner?> _restoreHomeOwner(
  String ownerType,
  String ownerId,
  String key,
  Y300ForumSourceScope scope,
  Y300ForumHomeCacheOwnerStore? owners,
) async {
  if (!scope.isCurrent ||
      scope.hasVerifiedIdentity ||
      !_isAuthenticatedHome(ownerType, ownerId, key)) {
    return null;
  }
  return owners?.restore(isCurrent: () => scope.isCurrent);
}

ForumCachedDocument _document(
  ForumCachedDocument value,
  ForumDocumentDescriptor descriptor,
) => ForumCachedDocument(
  descriptor: descriptor,
  body: value.body,
  fetchedAt: value.fetchedAt,
  updatedAt: value.updatedAt,
  lastAccessedAt: value.lastAccessedAt,
  statusCode: value.statusCode,
  contentType: value.contentType,
);
