import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
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

/// Captured before decoding; target changes and asset invalidation cancel writes.
class LibraryCoverThumbnailTicket {
  LibraryCoverThumbnailTicket._(this._valid);
  final bool Function() _valid;
  bool get isValid => _valid();
}

/// Persistent shelf derivatives, owned by cover assets, outside cache budgets.
/// Resolution never scans directories or updates filesystem access times.
class LibraryCoverThumbnailStore {
  LibraryCoverThumbnailStore({required Future<String> Function() rootPath})
    : _resolveRoot = rootPath;
  final Future<String> Function() _resolveRoot;
  Future<String>? _root;
  final Map<String, Future<void>> _tails = {};
  final Map<String, int> _epochs = {};
  final Map<String, String> _targets = {};
  final Map<String, int> _retainedRevisions = {};
  final Map<String, Timer> _maintenance = {};
  final Set<void Function()> _invalidationListeners = {};
  final Set<String> _activeTemporaryFiles = {};
  int _temporaryId = 0;
  bool _disposed = false;

  /// Register even on Flutter memory hits, without any filesystem work.
  void registerTarget(LibraryCoverThumbnailKey key) {
    if (_disposed ||
        (_retainedRevisions[key.assetDigest] ?? key.revision) > key.revision ||
        _targets[key.assetDigest] == key.value) {
      return;
    }
    _targets[key.assetDigest] = key.value;
    _retainedRevisions[key.assetDigest] = key.revision;
    _bump(key.assetDigest);
    _maintenance.remove(key.assetDigest)?.cancel();
    _notifyInvalidation();
  }

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
    if (!_targets.containsKey(key.assetDigest)) registerTarget(key);
    final assetEpoch = _epochs[key.assetDigest] ?? 0;
    final entryEpoch = _epochs[key.value] ?? 0;
    return LibraryCoverThumbnailTicket._(
      () =>
          !_disposed &&
          _targets[key.assetDigest] == key.value &&
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
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Maintenance runs after a successful disk frame, never during resolution.
  void scheduleMaintenance(LibraryCoverThumbnailKey key) {
    final captured = ticket(key);
    if (!captured.isValid || _maintenance.containsKey(key.assetDigest)) return;
    _maintenance[key.assetDigest] = Timer(const Duration(seconds: 2), () {
      _maintenance.remove(key.assetDigest);
      unawaited(
        _mutate(
          key.assetDigest,
          () => _pruneOthers(key, captured),
        ).catchError((Object _) {}),
      );
    });
  }

  /// Returns true only if this request actually published its derivative.
  Future<bool> write({
    required LibraryCoverThumbnailKey key,
    required LibraryCoverThumbnailTicket ticket,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty || !ticket.isValid) return false;
    io.File? temporary;
    try {
      final target = await _file(key.value);
      if (!ticket.isValid) return false;
      await target.parent.create(recursive: true);
      temporary = io.File(
        '${target.path}.${DateTime.now().microsecondsSinceEpoch}-${_temporaryId++}.part',
      );
      _activeTemporaryFiles.add(temporary.path);
      await temporary.writeAsBytes(bytes, flush: true);
      return await _mutate(key.assetDigest, () async {
        if (!ticket.isValid) return false;
        final exists = await target.exists();
        if (!ticket.isValid) return false;
        if (exists) {
          await _pruneOthers(key, ticket);
          return false;
        }
        await temporary!.rename(target.path);
        // Invalidation may happen while rename yields. Per-asset serialization
        // prevents this rollback from deleting a newer writer's publication.
        if (!ticket.isValid) {
          await target.delete();
          return false;
        }
        try {
          await _pruneOthers(key, ticket);
        } catch (_) {
          scheduleMaintenance(key);
        }
        return ticket.isValid;
      });
    } catch (_) {
      return false;
    } finally {
      if (temporary != null) _activeTemporaryFiles.remove(temporary.path);
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _pruneOthers(
    LibraryCoverThumbnailKey key,
    LibraryCoverThumbnailTicket captured,
  ) async {
    if (!captured.isValid) return;
    final target = await _file(key.value);
    if (!await target.exists() || !captured.isValid) return;
    await for (final entity in target.parent.list(followLinks: false)) {
      if (!captured.isValid) return;
      if (entity is! io.File ||
          entity.path == target.path ||
          _activeTemporaryFiles.contains(entity.path)) {
        continue;
      }
      if (_ownedName.hasMatch(p.basename(entity.path))) await entity.delete();
    }
  }

  Future<void> remove(LibraryCoverThumbnailKey key) {
    _bump(key.value);
    _notifyInvalidation();
    return _mutate(key.assetDigest, () async {
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
      if ((_retainedRevisions[digest] ?? retainRevision) > retainRevision) {
        return Future<void>.value();
      }
      _retainedRevisions[digest] = retainRevision;
    }
    _notifyInvalidation();
    _maintenance.remove(digest)?.cancel();
    return _mutate(digest, () async {
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
        if (_ownedName.hasMatch(name)) {
          await entity.delete();
        }
      }
    });
  }

  void _bump(String key) => _epochs[key] = (_epochs[key] ?? 0) + 1;

  Future<T> _mutate<T>(String digest, Future<T> Function() action) {
    final operation = (_tails[digest] ?? Future<void>.value()).then(
      (_) => action(),
    );
    final tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[digest] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tails[digest], tail)) _tails.remove(digest);
      }),
    );
    return operation;
  }

  static final _entryName = RegExp(
    r'^[0-9a-f]{64}/r[0-9]+-[0-9]+x[0-9]+\.png$',
  );
  static final _ownedName = RegExp(
    r'^r[0-9]+-[0-9]+x[0-9]+\.png(?:\.[0-9-]+\.part)?$',
  );

  Future<io.File> _file(String value) async {
    if (!_entryName.hasMatch(value)) {
      throw ArgumentError('Invalid thumbnail key');
    }
    return io.File(p.joinAll(<String>[await _rootPath(), ...value.split('/')]));
  }

  Future<int> calculateUsageBytes() async {
    final root = io.Directory(await _rootPath());
    if (!await root.exists()) return 0;
    var bytes = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! io.File ||
          !_entryName.hasMatch(
            p.relative(entity.path, from: root.path).replaceAll(r'\', '/'),
          )) {
        continue;
      }
      try {
        final stat = await entity.stat();
        if (stat.type == io.FileSystemEntityType.file) bytes += stat.size;
      } on io.FileSystemException {
        /* Concurrent asset purge. */
      }
    }
    return bytes;
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final timer in _maintenance.values) {
      timer.cancel();
    }
    _maintenance.clear();
    _notifyInvalidation();
    _invalidationListeners.clear();
    await Future.wait(_tails.values.toList());
  }
}
