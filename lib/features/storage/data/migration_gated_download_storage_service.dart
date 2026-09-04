import 'dart:io' as io;

import 'package:y300/features/storage/domain/download_storage_models.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';
import 'package:y300/features/storage/domain/storage_root_access_gate.dart';

final class MigrationGatedDownloadStorageService
    implements DownloadStorageService {
  const MigrationGatedDownloadStorageService({
    required DownloadStorageService delegate,
    required StorageRootAccessGate accessGate,
  }) : _delegate = delegate,
       _accessGate = accessGate;

  final DownloadStorageService _delegate;
  final StorageRootAccessGate _accessGate;

  @override
  Future<DownloadStorageRoot> prepareRoot() {
    return _accessGate.runWithAccess(_delegate.prepareRoot);
  }

  @override
  Future<io.Directory> prepareComicDirectory({
    required String workId,
    required String title,
  }) {
    return _accessGate.runWithAccess(
      () => _delegate.prepareComicDirectory(workId: workId, title: title),
    );
  }

  @override
  Future<bool> deleteComicDownloads({required String workId}) {
    return _accessGate.runWithAccess(
      () => _delegate.deleteComicDownloads(workId: workId),
    );
  }

  @override
  Future<bool> deleteNovelDownloads({required String novelId}) {
    return _accessGate.runWithAccess(
      () => _delegate.deleteNovelDownloads(novelId: novelId),
    );
  }

  @override
  String safeFileName(String value, {String fallback = 'untitled'}) {
    return _delegate.safeFileName(value, fallback: fallback);
  }

  @override
  String numberedFileName({
    required int index,
    required String title,
    required String extension,
  }) {
    return _delegate.numberedFileName(
      index: index,
      title: title,
      extension: extension,
    );
  }

  @override
  Future<void> writeJsonAtomically(io.File file, Object? value) {
    return _accessGate.runWithAccess(
      () => _delegate.writeJsonAtomically(file, value),
    );
  }

  @override
  Future<void> writeFavoritesSnapshot(Map<String, Object?> json) {
    return _accessGate.runWithAccess(
      () => _delegate.writeFavoritesSnapshot(json),
    );
  }

  @override
  Future<DownloadedComicEpisode?> findDownloadedComicEpisode({
    required String workId,
    required String title,
    required String episodeId,
  }) {
    return _accessGate.runWithAccess(
      () => _delegate.findDownloadedComicEpisode(
        workId: workId,
        title: title,
        episodeId: episodeId,
      ),
    );
  }
}
