import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';
import 'package:y300/features/cache/data/services/image_cache_file_access.dart';

/// App-indexed files are evicted by the shared byte budget and retention rules.
/// Fallback downloads and resized copies that have no App record still use the
/// lower-level count/age policy, with a one-day grace for newly published files.
final class AppImageCacheInfoRepository implements CacheInfoRepository {
  AppImageCacheInfoRepository({
    required CacheInfoRepository delegate,
    required ImageCacheRepository imageRepository,
    required ImageCacheFileAccess fileAccess,
    required String cacheDirectoryPath,
    required Future<void> Function(String key) removeFile,
    DateTime Function()? now,
  }) : _delegate = delegate,
       _imageRepository = imageRepository,
       _fileAccess = fileAccess,
       _cacheDirectoryPath = cacheDirectoryPath,
       _removeFile = removeFile,
       _now = now ?? DateTime.now;

  final CacheInfoRepository _delegate;
  final ImageCacheRepository _imageRepository;
  final ImageCacheFileAccess _fileAccess;
  final String _cacheDirectoryPath;
  final Future<void> Function(String key) _removeFile;
  final DateTime Function() _now;
  Future<void>? _activeCleanup;
  int _capacity = 200;
  bool _closed = false;

  @override
  Future<List<CacheObject>> getObjectsOverCapacity(int capacity) async {
    _capacity = capacity;
    return const [];
  }

  @override
  Future<List<CacheObject>> getOldObjects(Duration maxAge) async {
    if (_closed) return const [];
    // CacheStore does not await its individual file deletions. Own this small
    // unindexed cleanup so the access lease lasts through the actual unlink.
    final active = _activeCleanup;
    if (active != null) {
      await active;
      return const [];
    }
    late final Future<void> task;
    task = _cleanup(maxAge)
        .catchError((Object _) {
          // Maintenance is best-effort: an unavailable App index never authorizes
          // deleting its files and must not break normal cache reads/downloads.
        })
        .whenComplete(() {
          if (identical(_activeCleanup, task)) _activeCleanup = null;
        });
    _activeCleanup = task;
    await task;
    return const [];
  }

  Future<void> _cleanup(Duration maxAge) async {
    // Loading the complete metadata set avoids the upstream SQLite query's
    // 100-item prefix repeatedly containing only App-owned files.
    final objects = await _delegate.getAllObjects();
    final paths = await _indexedPaths(objects.map((object) => object.key));
    final unowned =
        objects.where((object) => !_owns(object, paths[object.key])).toList()
          ..sort((left, right) => _touched(left).compareTo(_touched(right)));
    final now = _now();
    final oldest = now.subtract(maxAge);
    final fresh = now.subtract(const Duration(days: 1));
    final excess = unowned.length - _capacity;
    var attempted = 0;
    for (var index = 0; index < unowned.length; index++) {
      if (_closed) return;
      final candidate = unowned[index];
      final touched = _touched(candidate);
      if (!touched.isBefore(oldest) &&
          !(index < excess && touched.isBefore(fresh))) {
        continue;
      }
      // Keep each maintenance pass bounded even when an old installation has
      // many orphaned metadata rows; protected prefixes do not consume this.
      if (attempted >= 100) break;
      try {
        final acquired = await _fileAccess.deleteIfIdle(
          candidate.key,
          () async {
            if (_closed) return;
            final current = await _delegate.get(candidate.key);
            if (current == null ||
                current.id != candidate.id ||
                current.relativePath != candidate.relativePath ||
                current.touched != candidate.touched) {
              return;
            }
            final record = await _imageRepository.getByKey(candidate.key);
            if (_closed || _owns(current, record?.localPath)) return;
            await _removeFile(candidate.key);
          },
        );
        if (acquired) attempted++;
      } catch (_) {
        // A failed unlink is still an I/O attempt, but must not starve later
        // orphans on every pass. The access guard releases the key on failure.
        attempted++;
      }
    }
  }

  Future<Map<String, String>> _indexedPaths(Iterable<String> keys) async {
    final repository = _imageRepository;
    if (repository is ImageCachePathLookup) {
      return (repository as ImageCachePathLookup).lookupLocalPaths(keys);
    }
    final paths = <String, String>{};
    for (final key in keys) {
      final path = (await repository.getByKey(key))?.localPath;
      if (path != null) paths[key] = path;
    }
    return paths;
  }

  bool _owns(CacheObject object, String? path) =>
      path != null &&
      path.isNotEmpty &&
      p.equals(path, p.join(_cacheDirectoryPath, object.relativePath));

  DateTime _touched(CacheObject object) =>
      object.touched ?? DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<bool> exists() => _delegate.exists();

  @override
  Future<bool> open() => _delegate.open();

  @override
  Future<dynamic> updateOrInsert(CacheObject object) =>
      _delegate.updateOrInsert(object);

  @override
  Future<CacheObject> insert(
    CacheObject object, {
    bool setTouchedToNow = true,
  }) => _delegate.insert(object, setTouchedToNow: setTouchedToNow);

  @override
  Future<CacheObject?> get(String key) => _delegate.get(key);

  @override
  Future<int> delete(int id) => _delegate.delete(id);

  @override
  Future<int> deleteAll(Iterable<int> ids) => _delegate.deleteAll(ids);

  @override
  Future<int> update(CacheObject object, {bool setTouchedToNow = true}) =>
      _delegate.update(object, setTouchedToNow: setTouchedToNow);

  @override
  Future<List<CacheObject>> getAllObjects() => _delegate.getAllObjects();

  @override
  Future<bool> close() async {
    _closed = true;
    await _activeCleanup;
    return _delegate.close();
  }

  @override
  Future<void> deleteDataFile() => _delegate.deleteDataFile();
}
