import 'dart:io' as io;

import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';
import 'package:y300/features/storage/domain/storage_root_access_gate.dart';

class DownloadStorageAccountingAdapter implements StorageAccountingAdapter {
  const DownloadStorageAccountingAdapter({
    required DownloadStorageService storageService,
    required StorageRootAccessGate storageRootAccessGate,
  }) : _storageService = storageService,
       _storageRootAccessGate = storageRootAccessGate;

  final DownloadStorageService _storageService;
  final StorageRootAccessGate _storageRootAccessGate;

  @override
  StorageBucket get bucket => StorageBucket.download;

  @override
  Future<StorageUsageSection> calculateUsage() {
    return _storageRootAccessGate.runWithAccess(_calculateUsage);
  }

  Future<StorageUsageSection> _calculateUsage() async {
    final root = await _storageService.prepareRoot();
    final comics = await _directoryBytes(io.Directory(root.comicsPath));
    final novels = await _directoryBytes(io.Directory(root.novelsPath));
    final favorites = await _fileBytes(io.File(root.favoritesJsonPath));
    final total = comics + novels + favorites;
    return StorageUsageSection(
      bucket: bucket,
      labelRef: StorageUsageLabelRef(
        kind: StorageUsageLabelKind.bucket,
        code: bucket.id,
      ),
      bytes: total,
      clearable: false,
      slices: [
        if (comics > 0)
          StorageUsageSlice(
            id: 'download:comics',
            labelRef: const StorageUsageLabelRef(
              kind: StorageUsageLabelKind.downloadKind,
              code: 'comics',
            ),
            bytes: comics,
            protected: true,
          ),
        if (novels > 0)
          StorageUsageSlice(
            id: 'download:novels',
            labelRef: const StorageUsageLabelRef(
              kind: StorageUsageLabelKind.downloadKind,
              code: 'novels',
            ),
            bytes: novels,
            protected: true,
          ),
        if (favorites > 0)
          StorageUsageSlice(
            id: 'download:favorites_snapshot',
            labelRef: const StorageUsageLabelRef(
              kind: StorageUsageLabelKind.downloadKind,
              code: 'favorites_snapshot',
            ),
            bytes: favorites,
            protected: true,
          ),
      ],
    );
  }
}

Future<int> _directoryBytes(io.Directory directory) async {
  if (!await directory.exists()) {
    return 0;
  }
  var total = 0;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is io.File) {
      total += await _fileBytes(entity);
    }
  }
  return total;
}

Future<int> _fileBytes(io.File file) async {
  if (!await file.exists()) {
    return 0;
  }
  return file.length();
}
