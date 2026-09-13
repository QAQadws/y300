import 'dart:async';
import 'dart:io' as io;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/data/services/comic_download_metadata_store.dart';
import 'package:y300/features/library_shared/data/services/library_cover_legacy_migrator.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';
import 'package:y300/features/storage/domain/storage_root_access_gate.dart';

/// Conservative, access-time removal of the old downloaded cover duplicate.
/// No directory creation, library scan, or remote request belongs to this task.
class ComicDownloadCoverMaintenance {
  ComicDownloadCoverMaintenance({
    required ComicRepository repository,
    required DownloadStorageService storage,
    required StorageRootAccessGate accessGate,
    required LibraryCoverLegacyMigrator migrator,
    required LibraryCoverStore covers,
    required ComicDownloadMetadataStore metadata,
  }) : _repository = repository,
       _storage = storage,
       _accessGate = accessGate,
       _migrator = migrator,
       _covers = covers,
       _metadata = metadata;
  final ComicRepository _repository;
  final DownloadStorageService _storage;
  final StorageRootAccessGate _accessGate;
  final LibraryCoverLegacyMigrator _migrator;
  final LibraryCoverStore _covers;
  final ComicDownloadMetadataStore _metadata;
  final Map<String, Future<void>> _pending = {};
  bool _disposed = false;

  void schedule(String comicId) {
    unawaited(maintain(comicId));
  }

  Future<void> maintain(String comicId) {
    if (_disposed) return Future<void>.value();
    final existing = _pending[comicId];
    if (existing != null) return existing;
    // A detached task cannot inherit the caller's reentrant access lease: its
    // lifetime extends past the download/read that scheduled it.
    final task = Future<void>(() {
      final gate = _accessGate;
      return gate is IndependentStorageRootAccessGate
          ? (gate as IndependentStorageRootAccessGate).runWithIndependentAccess(
              () => _maintain(comicId),
            )
          : gate.runWithAccess(() => _maintain(comicId));
    }).catchError((Object _) {});
    _pending[comicId] = task;
    unawaited(
      task.then((_) {
        if (identical(_pending[comicId], task)) _pending.remove(comicId);
      }),
    );
    return task;
  }

  Future<void> _maintain(String comicId) async {
    if (_disposed) return;
    final detail = await _repository.getComicDetail(comicId: comicId);
    final locator = _storage;
    if (detail == null || locator is! ComicDownloadDirectoryLocator) return;
    final directory = await (locator as ComicDownloadDirectoryLocator)
        .findExistingComicDirectory(workId: comicId, title: detail.title);
    if (directory == null) return;
    final legacy = io.File(p.join(directory.path, 'cover.jpg'));
    if (!await _regularFile(legacy)) return;
    final before = await legacy.stat();
    if (before.size == 0) return;
    await _migrator.migrateComicAssets(comicId);
    final digest = await sha256.bind(legacy.openRead()).first;
    if (!_unchanged(before, await legacy.stat())) return;
    for (final asset in await _migrator.comicAssets(comicId)) {
      if (_disposed) return;
      final original = await _covers.fileFor(asset);
      if (!await _regularFile(original)) continue;
      final originalBefore = await original.stat();
      if (before.size != originalBefore.size ||
          digest != await sha256.bind(original.openRead()).first) {
        continue;
      }
      if (!_unchanged(originalBefore, await original.stat())) continue;
      await _metadata.run(directory, () async {
        final meta = await _metadata.read(directory);
        if (meta == null ||
            meta['schemaVersion'] != 1 ||
            meta['workId'] != comicId ||
            meta['chapters'] is! List) {
          return;
        }
        final updated = <String, Object?>{...meta};
        for (final field in ['coverFile', 'customCoverFile']) {
          if (updated[field] == 'cover.jpg') updated[field] = null;
        }
        if (_references(updated, legacy.path)) return;
        await _migrator.withUnreferencedComicAsset(
          comicId: comicId,
          asset: asset,
          path: legacy.path,
          action: () async {
            if (_disposed ||
                !await _regularFile(legacy) ||
                !await _regularFile(original) ||
                !_unchanged(before, await legacy.stat()) ||
                !_unchanged(originalBefore, await original.stat())) {
              return;
            }
            if (meta['coverFile'] != updated['coverFile'] ||
                meta['customCoverFile'] != updated['customCoverFile']) {
              await _metadata.write(directory, updated);
            }
            if (!_disposed &&
                await _regularFile(legacy) &&
                await _regularFile(original) &&
                _unchanged(before, await legacy.stat()) &&
                _unchanged(originalBefore, await original.stat())) {
              await legacy.delete();
            }
          },
        );
      });
      return;
    }
  }

  bool _references(Object? value, String path) {
    if (value is String) {
      return value == 'cover.jpg' ||
          p.equals(p.normalize(value), p.normalize(path));
    }
    if (value is Map) {
      return value.values.any((item) => _references(item, path));
    }
    if (value is List) return value.any((item) => _references(item, path));
    return false;
  }

  Future<bool> _regularFile(io.File file) async =>
      await io.FileSystemEntity.type(file.path, followLinks: false) ==
      io.FileSystemEntityType.file;
  bool _unchanged(io.FileStat a, io.FileStat b) =>
      b.type == io.FileSystemEntityType.file &&
      a.size == b.size &&
      a.modified == b.modified &&
      a.changed == b.changed;
  void dispose() {
    _disposed = true;
  }
}
