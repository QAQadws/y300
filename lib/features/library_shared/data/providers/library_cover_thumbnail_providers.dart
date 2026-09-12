import 'dart:async';

import 'package:y300/features/library_shared/data/services/library_cover_legacy_thumbnail_cleanup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:y300/features/library_shared/data/services/library_cover_thumbnail_store.dart';

/// A leaf provider: no dependency on original covers, network or image manager.
final libraryCoverThumbnailStoreProvider = Provider<LibraryCoverThumbnailStore>(
  (ref) {
    final cache = LibraryCoverThumbnailStore(
      rootPath: () async {
        final base = await getApplicationSupportDirectory();
        return p.join(base.path, 'library_covers', 'thumbnails', 'v1');
      },
    );
    ref.onDispose(() => unawaited(cache.dispose()));
    return cache;
  },
);

final libraryCoverLegacyThumbnailCleanupProvider =
    Provider<LibraryCoverLegacyThumbnailCleanup>((ref) {
      final service = LibraryCoverLegacyThumbnailCleanup(
        rootPath: () async => p.join(
          (await getTemporaryDirectory()).path,
          'y300_cover_thumbnails',
          'v1',
        ),
      );
      ref.onDispose(service.dispose);
      return service;
    });
