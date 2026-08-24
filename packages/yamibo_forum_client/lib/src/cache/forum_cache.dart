/// Authentication partition used by cached HTML documents.
enum ForumDocumentRequestProfile {
  anonymous('anonymous'),
  loggedIn('logged_in');

  const ForumDocumentRequestProfile(this.id);
  final String id;
}

/// Stable identity of one source document cache entry.
final class ForumDocumentDescriptor {
  /// Creates a document descriptor.
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

/// Cached source document used by HTML-first fallback.
final class ForumCachedDocument {
  /// Creates a cached document value.
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

/// Persistent source-document cache port.
abstract interface class ForumDocumentStore {
  /// Reads the document matching [descriptor].
  Future<ForumCachedDocument?> get(ForumDocumentDescriptor descriptor);

  /// Atomically stores [document].
  Future<void> put(ForumCachedDocument document);

  /// Updates access metadata without replacing the document body.
  Future<void> touch(ForumDocumentDescriptor descriptor, DateTime accessedAt);
}

/// Stable identity of one parsed snapshot cache entry.
final class ForumSnapshotDescriptor {
  /// Creates a snapshot descriptor.
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

/// Freshness and retention policy for a parsed snapshot.
final class ForumSnapshotPolicy {
  /// Creates a snapshot policy.
  const ForumSnapshotPolicy({
    required this.freshFor,
    required this.keepStaleFor,
  });

  final Duration freshFor;
  final Duration keepStaleFor;
}

/// Versioned codec for source-neutral parsed snapshots.
abstract interface class ForumSnapshotCodec<T> {
  /// Stable snapshot family identifier.
  String get snapshotType;

  /// Storage representation version.
  int get codecVersion;

  /// Parser behavior version used to create the snapshot.
  int get parserVersion;

  /// Encodes [value] into JSON-compatible data.
  Object? encode(T value);

  /// Decodes JSON-compatible snapshot data.
  T decode(Object? json);

  /// Whether this codec can read the supplied stored versions.
  bool canDecodeVersion({
    required int codecVersion,
    required int parserVersion,
  }) =>
      codecVersion == this.codecVersion && parserVersion == this.parserVersion;
}

/// Typed parsed snapshot and its cache metadata.
final class ForumCachedSnapshot<T> {
  /// Creates a cached snapshot.
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

  /// Whether the snapshot is still within its fresh period.
  bool isFresh(DateTime now) => staleAt == null || now.isBefore(staleAt!);

  /// Whether the snapshot is beyond its stale retention period.
  bool isExpired(DateTime now) =>
      expiresAt != null && !now.isBefore(expiresAt!);
}

/// Persistent parsed-snapshot cache port.
abstract interface class ForumSnapshotStore {
  /// Reads and decodes a compatible snapshot.
  Future<ForumCachedSnapshot<T>?> get<T>(
    ForumSnapshotDescriptor descriptor,
    ForumSnapshotCodec<T> codec,
  );

  /// Encodes and atomically stores a snapshot.
  Future<void> put<T>(
    ForumSnapshotDescriptor descriptor,
    T value,
    ForumSnapshotCodec<T> codec, {
    required ForumSnapshotPolicy policy,
  });

  /// Updates access metadata without replacing the snapshot payload.
  Future<void> touch(ForumSnapshotDescriptor descriptor, DateTime accessedAt);
}

/// Ephemeral document store for tests and short-lived tools.
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

/// Ephemeral snapshot store for tests and short-lived tools.
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
