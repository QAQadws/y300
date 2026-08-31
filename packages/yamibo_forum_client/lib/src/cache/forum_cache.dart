/// Authentication partition used by cached HTML documents.
enum ForumDocumentRequestProfile {
  /// Anonymous request partition.
  anonymous('anonymous'),

  /// Authenticated request partition.
  loggedIn('logged_in');

  const ForumDocumentRequestProfile(this.id);

  /// Stable value used in cache keys.
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

  /// Cache key.
  final String cacheKey;

  /// Owner type.
  final String ownerType;

  /// Owner id.
  final String ownerId;

  /// Source uri.
  final Uri sourceUri;

  /// Request profile.
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

  /// Descriptor.
  final ForumDocumentDescriptor descriptor;

  /// Response or request body in the declared representation.
  final String body;

  /// Content type.
  final String? contentType;

  /// HTTP status code when safely available.
  final int? statusCode;

  /// Fetched at.
  final DateTime fetchedAt;

  /// Updated at.
  final DateTime updatedAt;

  /// Last accessed at.
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

  /// Cache key.
  final String cacheKey;

  /// Owner type.
  final String ownerType;

  /// Owner id.
  final String ownerId;

  /// Snapshot type.
  final String snapshotType;

  /// Source document key.
  final String? sourceDocumentKey;
}

/// Freshness and retention policy for a parsed snapshot.
final class ForumSnapshotPolicy {
  /// Creates a snapshot policy.
  const ForumSnapshotPolicy({
    required this.freshFor,
    required this.keepStaleFor,
  });

  /// Fresh for.
  final Duration freshFor;

  /// Keep stale for.
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

  /// Descriptor.
  final ForumSnapshotDescriptor descriptor;

  /// Codec version.
  final int codecVersion;

  /// Parser version.
  final int parserVersion;

  /// Value.
  final T value;

  /// Created at.
  final DateTime createdAt;

  /// Updated at.
  final DateTime updatedAt;

  /// Last accessed at.
  final DateTime? lastAccessedAt;

  /// Stale at.
  final DateTime? staleAt;

  /// Expires at.
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
