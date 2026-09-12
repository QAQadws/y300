import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/cache/domain/models/cache_capacity_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';

/// A derived image identity, deliberately independent of URLs and local paths.
class LibraryCoverThumbnailKey {
  LibraryCoverThumbnailKey({
    required LibraryCoverAssetRef asset,
    required this.width,
    required this.height,
  }) : assetDigest = sha256.convert(utf8.encode(asset.assetId)).toString(),
       revision = asset.revision;

  final String assetDigest;
  final int revision;
  final int width;
  final int height;

  String get value => '$assetDigest/r$revision-${width}x$height.png';
}

/// Captured before decoding, so a concurrent clear also cancels future writes.
class LibraryCoverThumbnailTicket {
  LibraryCoverThumbnailTicket._(this._valid);
  final bool Function() _valid;
  bool get isValid => _valid();
}

/// Regenerable disk thumbnails. The original asset store never lives here.
/// No index database, directory scan, or access-time write is on the read path.
class LibraryCoverThumbnailCache implements CacheBudgetParticipant {
  LibraryCoverThumbnailCache({
    required Future<String> Function() rootPath,
    CacheMutationReporter mutationReporter = const NoopCacheMutationReporter(),
    DateTime Function()? now,
  }) : _resolveRoot = rootPath,
       _reporter = mutationReporter,
       _now = now ?? DateTime.now;

  final Future<String> Function() _resolveRoot;
  final CacheMutationReporter _reporter;
  final DateTime Function() _now;
  Future<String>? _root;
  Future<void> _mutationTail = Future<void>.value();
  final Map<String, int> _epochs = <String, int>{};
  final Map<String, int> _retainedRevisions = <String, int>{};
  final Map<String, DateTime> _accesses = <String, DateTime>{};
  final Set<void Function()> _invalidationListeners = <void Function()>{};
  final Set<String> _activeTemporaryFiles = <String>{};
  Timer? _accessTimer;
  int _generation = 0;
  int _temporaryId = 0;
  bool _disposed = false;

  @override
  String get participantId => 'library_cover_thumbnails';

  void addInvalidationListener(void Function() listener) =>
      _invalidationListeners.add(listener);

  void removeInvalidationListener(void Function() listener) =>
      _invalidationListeners.remove(listener);

  void _notifyInvalidation() {
    for (final listener in _invalidationListeners.toList(growable: false)) {
      listener();
    }
  }

  Future<String> _rootPath() async {
    final existing = _root;
    if (existing != null) return existing;
    final future = _resolveRoot();
    _root = future;
    try {
      return await future;
    } catch (_) {
      if (identical(_root, future)) _root = null;
      rethrow;
    }
  }

  LibraryCoverThumbnailTicket ticket(LibraryCoverThumbnailKey key) {
    final generation = _generation;
    final assetEpoch = _epochs[key.assetDigest] ?? 0;
    final entryEpoch = _epochs[key.value] ?? 0;
    return LibraryCoverThumbnailTicket._(
      () =>
          !_disposed &&
          generation == _generation &&
          assetEpoch == (_epochs[key.assetDigest] ?? 0) &&
          entryEpoch == (_epochs[key.value] ?? 0) &&
          (!_retainedRevisions.containsKey(key.assetDigest) ||
              _retainedRevisions[key.assetDigest] == key.revision),
    );
  }

  Future<io.File?> lookup(LibraryCoverThumbnailKey key) async {
    if (_disposed) return null;
    final readTicket = ticket(key);
    try {
      final file = await _file(key.value);
      final stat = await file.stat();
      if (!readTicket.isValid || stat.type != io.FileSystemEntityType.file) {
        return null;
      }
      // Empty files must reach the same repair path as other corrupt images;
      // treating them as misses leaves them blocking every subsequent write.
      _accesses[key.value] = _now();
      _accessTimer ??= Timer(const Duration(seconds: 2), () {
        _accessTimer = null;
        unawaited(flushAccesses());
      });
      if (_accesses.length >= 64) unawaited(flushAccesses());
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<void> write({
    required LibraryCoverThumbnailKey key,
    required LibraryCoverThumbnailTicket ticket,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty || !ticket.isValid) return;
    io.File? temporary;
    try {
      final target = await _file(key.value);
      if (!ticket.isValid) return;
      await target.parent.create(recursive: true);
      temporary = io.File('${target.path}.${_temporaryId++}.part');
      _activeTemporaryFiles.add(temporary.path);
      await temporary.writeAsBytes(bytes, flush: true);
      await _mutate(() async {
        if (!ticket.isValid || await target.exists()) return;
        await temporary!.rename(target.path);
        try {
          _reporter.reportMutation(CacheNamespace.image);
        } catch (_) {
          // Budget notification is not part of a successful thumbnail write.
        }
      });
    } catch (_) {
      // A derivative must never make the original image fail to display.
    } finally {
      if (temporary != null) _activeTemporaryFiles.remove(temporary.path);
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> remove(LibraryCoverThumbnailKey key) {
    _bump(key.value);
    _notifyInvalidation();
    _accesses.remove(key.value);
    return _mutate(() async {
      final file = await _file(key.value);
      if (await file.exists()) await file.delete();
    });
  }

  Future<void> invalidateAsset(String assetId, {int? retainRevision}) {
    final digest = sha256.convert(utf8.encode(assetId)).toString();
    if (retainRevision == null) {
      _bump(digest);
      _retainedRevisions.remove(digest);
    } else {
      _retainedRevisions[digest] = retainRevision;
    }
    _notifyInvalidation();
    _accesses.removeWhere((key, _) => key.startsWith('$digest/'));
    return _mutate(() async {
      final directory = io.Directory(p.join(await _rootPath(), digest));
      if (!await directory.exists()) return;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! io.File) continue;
        // The writer owns open temporary files and removes them in finally.
        if (_activeTemporaryFiles.contains(entity.path)) continue;
        final name = p.basename(entity.path);
        if (retainRevision != null && name.startsWith('r$retainRevision-')) {
          continue;
        }
        if (_fileName.hasMatch(name) || name.endsWith('.part')) {
          await entity.delete();
        }
      }
    });
  }

  void _bump(String key) => _epochs[key] = (_epochs[key] ?? 0) + 1;

  Future<void> flushAccesses() async {
    _accessTimer?.cancel();
    _accessTimer = null;
    if (_accesses.isEmpty) return;
    final batch = Map<String, DateTime>.from(_accesses);
    _accesses.clear();
    await _mutate(() async {
      for (final entry in batch.entries) {
        try {
          final file = await _file(entry.key);
          if (await file.exists()) await file.setLastModified(entry.value);
        } catch (_) {
          // Approximate LRU bookkeeping never blocks or invalidates a hit.
        }
      }
    });
  }

  Future<T> _mutate<T>(Future<T> Function() action) {
    final operation = _mutationTail.then((_) => action());
    _mutationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  static final _entryName = RegExp(
    r'^[0-9a-f]{64}/r[0-9]+-[0-9]+x[0-9]+\.png$',
  );
  static final _fileName = RegExp(r'^r[0-9]+-[0-9]+x[0-9]+\.png$');

  Future<io.File> _file(String value) async {
    if (!_entryName.hasMatch(value)) {
      throw ArgumentError('Invalid thumbnail key');
    }
    return io.File(p.joinAll(<String>[await _rootPath(), ...value.split('/')]));
  }

  @override
  Future<List<CacheEvictionCandidate>> loadEvictionCandidates() async {
    await flushAccesses();
    final root = io.Directory(await _rootPath());
    if (!await root.exists()) return const <CacheEvictionCandidate>[];
    final entries = <CacheEvictionCandidate>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! io.File) continue;
      final relative = p
          .relative(entity.path, from: root.path)
          .replaceAll(r'\', '/');
      if (!_entryName.hasMatch(relative)) continue;
      try {
        final stat = await entity.stat();
        if (stat.type != io.FileSystemEntityType.file) continue;
        entries.add(
          CacheEvictionCandidate(
            participantId: participantId,
            cacheKey: relative,
            bytes: stat.size,
            lastAccessedAt: stat.modified,
            priority: CacheEvictionPriority.regularImage,
          ),
        );
      } on io.FileSystemException {
        // A concurrent purge may remove an entry during enumeration.
      }
    }
    return entries;
  }

  @override
  Future<CacheParticipantUsage> loadUsage() async {
    final entries = await loadEvictionCandidates();
    final bytes = entries.fold<int>(0, (sum, entry) => sum + entry.bytes);
    return CacheParticipantUsage(clearableBytes: bytes, budgetedBytes: bytes);
  }

  @override
  Future<bool> deleteCandidate(CacheEvictionCandidate candidate) async {
    if (candidate.participantId != participantId ||
        !_entryName.hasMatch(candidate.cacheKey)) {
      return false;
    }
    _bump(candidate.cacheKey);
    _notifyInvalidation();
    _accesses.remove(candidate.cacheKey);
    return _mutate(() async {
      final file = await _file(candidate.cacheKey);
      if (!await file.exists()) return false;
      await file.delete();
      return true;
    });
  }

  @override
  Future<CacheParticipantClearResult> clearRegular() {
    _generation++;
    _notifyInvalidation();
    _accesses.clear();
    return _mutate(() async {
      final root = io.Directory(await _rootPath());
      if (!await root.exists()) return CacheParticipantClearResult.empty;
      var count = 0;
      var bytes = 0;
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! io.File) continue;
        if (_activeTemporaryFiles.contains(entity.path)) continue;
        final relative = p
            .relative(entity.path, from: root.path)
            .replaceAll(r'\', '/');
        if (!_entryName.hasMatch(relative) && !relative.endsWith('.part')) {
          continue;
        }
        final stat = await entity.stat();
        if (stat.type != io.FileSystemEntityType.file) continue;
        await entity.delete();
        count++;
        bytes += stat.size;
      }
      return CacheParticipantClearResult(
        deletedEntries: count,
        deletedBytes: bytes,
      );
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    _notifyInvalidation();
    _invalidationListeners.clear();
    await flushAccesses();
  }
}
