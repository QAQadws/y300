enum ForumDocumentRequestProfile {
  anonymous('anonymous'),
  loggedIn('logged_in');

  const ForumDocumentRequestProfile(this.id);
  final String id;
}

final class ForumDocumentDescriptor {
  const ForumDocumentDescriptor({
    required this.cacheKey,
    required this.ownerType,
    required this.ownerId,
    required this.sourceUri,
    required this.requestProfile,
  });

  final String cacheKey;
  final String ownerType;
  final String ownerId;
  final Uri sourceUri;
  final ForumDocumentRequestProfile requestProfile;
}

final class ForumCachedDocument {
  const ForumCachedDocument({
    required this.descriptor,
    required this.body,
    required this.fetchedAt,
    required this.updatedAt,
    this.contentType,
    this.statusCode,
    this.lastAccessedAt,
  });

  final ForumDocumentDescriptor descriptor;
  final String body;
  final String? contentType;
  final int? statusCode;
  final DateTime fetchedAt;
  final DateTime updatedAt;
  final DateTime? lastAccessedAt;
}

abstract interface class ForumDocumentStore {
  Future<ForumCachedDocument?> get(ForumDocumentDescriptor descriptor);
  Future<void> put(ForumCachedDocument document);
  Future<void> touch(ForumDocumentDescriptor descriptor, DateTime accessedAt);
}

final class ForumSnapshotDescriptor {
  const ForumSnapshotDescriptor({
    required this.cacheKey,
    required this.ownerType,
    required this.ownerId,
    required this.snapshotType,
    this.sourceDocumentKey,
  });

  final String cacheKey;
  final String ownerType;
  final String ownerId;
  final String snapshotType;
  final String? sourceDocumentKey;
}

final class ForumSnapshotPolicy {
  const ForumSnapshotPolicy({
    required this.freshFor,
    required this.keepStaleFor,
  });

  final Duration freshFor;
  final Duration keepStaleFor;
}

abstract interface class ForumSnapshotCodec<T> {
  String get snapshotType;
  int get codecVersion;
  int get parserVersion;
  Object? encode(T value);
  T decode(Object? json);

  bool canDecodeVersion({
    required int codecVersion,
    required int parserVersion,
  }) =>
      codecVersion == this.codecVersion && parserVersion == this.parserVersion;
}

final class ForumCachedSnapshot<T> {
  const ForumCachedSnapshot({
    required this.descriptor,
    required this.codecVersion,
    required this.parserVersion,
    required this.value,
    required this.createdAt,
    required this.updatedAt,
    this.lastAccessedAt,
    this.staleAt,
    this.expiresAt,
  });

  final ForumSnapshotDescriptor descriptor;
  final int codecVersion;
  final int parserVersion;
  final T value;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastAccessedAt;
  final DateTime? staleAt;
  final DateTime? expiresAt;

  bool isFresh(DateTime now) => staleAt == null || now.isBefore(staleAt!);
  bool isExpired(DateTime now) =>
      expiresAt != null && !now.isBefore(expiresAt!);
}

abstract interface class ForumSnapshotStore {
  Future<ForumCachedSnapshot<T>?> get<T>(
    ForumSnapshotDescriptor descriptor,
    ForumSnapshotCodec<T> codec,
  );

  Future<void> put<T>(
    ForumSnapshotDescriptor descriptor,
    T value,
    ForumSnapshotCodec<T> codec, {
    required ForumSnapshotPolicy policy,
  });

  Future<void> touch(ForumSnapshotDescriptor descriptor, DateTime accessedAt);
}

final class MemoryForumDocumentStore implements ForumDocumentStore {
  final Map<String, ForumCachedDocument> _values = {};

  @override
  Future<ForumCachedDocument?> get(ForumDocumentDescriptor descriptor) async =>
      _values[descriptor.cacheKey];

  @override
  Future<void> put(ForumCachedDocument document) async {
    _values[document.descriptor.cacheKey] = document;
  }

  @override
  Future<void> touch(
    ForumDocumentDescriptor descriptor,
    DateTime accessedAt,
  ) async {}
}

final class MemoryForumSnapshotStore implements ForumSnapshotStore {
  final Map<String, ForumCachedSnapshot<Object?>> _values = {};

  @override
  Future<ForumCachedSnapshot<T>?> get<T>(
    ForumSnapshotDescriptor descriptor,
    ForumSnapshotCodec<T> codec,
  ) async {
    final value = _values[descriptor.cacheKey];
    if (value == null ||
        value.descriptor.snapshotType != codec.snapshotType ||
        !codec.canDecodeVersion(
          codecVersion: value.codecVersion,
          parserVersion: value.parserVersion,
        )) {
      return null;
    }
    return ForumCachedSnapshot<T>(
      descriptor: value.descriptor,
      codecVersion: value.codecVersion,
      parserVersion: value.parserVersion,
      value: value.value as T,
      createdAt: value.createdAt,
      updatedAt: value.updatedAt,
      lastAccessedAt: value.lastAccessedAt,
      staleAt: value.staleAt,
      expiresAt: value.expiresAt,
    );
  }

  @override
  Future<void> put<T>(
    ForumSnapshotDescriptor descriptor,
    T value,
    ForumSnapshotCodec<T> codec, {
    required ForumSnapshotPolicy policy,
  }) async {
    final now = DateTime.now();
    _values[descriptor.cacheKey] = ForumCachedSnapshot<Object?>(
      descriptor: descriptor,
      codecVersion: codec.codecVersion,
      parserVersion: codec.parserVersion,
      value: value,
      createdAt: now,
      updatedAt: now,
      staleAt: now.add(policy.freshFor),
      expiresAt: now.add(policy.keepStaleFor),
    );
  }

  @override
  Future<void> touch(
    ForumSnapshotDescriptor descriptor,
    DateTime accessedAt,
  ) async {}
}
