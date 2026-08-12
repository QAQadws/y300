import 'dart:io' as io;

import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';

class UnavailableLibraryCoverStore implements LibraryCoverStore {
  const UnavailableLibraryCoverStore();

  @override
  Future<int> calculateUsageBytes() async => 0;

  @override
  Future<void> deleteAsset(String assetId) async {}

  @override
  Future<void> deleteOlderRevisions(LibraryCoverAssetRef asset) async {}

  @override
  Future<io.File> ensureAvailable(LibraryCoverAssetRef asset) {
    throw StateError('Library cover Store is unavailable in this test');
  }

  @override
  Future<io.File> fileFor(LibraryCoverAssetRef asset) {
    throw StateError('Library cover Store is unavailable in this test');
  }

  @override
  Future<void> installLocalFile({
    required LibraryCoverAssetRef asset,
    required String sourcePath,
  }) {
    throw StateError('Library cover Store is unavailable in this test');
  }

  @override
  Future<void> invalidate(LibraryCoverAssetRef asset) async {}
}
