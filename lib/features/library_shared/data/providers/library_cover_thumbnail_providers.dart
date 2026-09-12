import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:y300/features/cache/data/providers/cache_mutation_provider.dart';
import 'package:y300/features/library_shared/data/services/library_cover_thumbnail_cache.dart';

/// A leaf provider: no dependency on original covers, network or image manager.
final libraryCoverThumbnailCacheProvider = Provider<LibraryCoverThumbnailCache>(
  (ref) {
    final cache = LibraryCoverThumbnailCache(
      rootPath: () async {
        final base = await getTemporaryDirectory();
        final root = io.Directory(
          p.join(base.path, 'y300_cover_thumbnails', 'v1'),
        );
        await root.create(recursive: true);
        return root.path;
      },
      mutationReporter: ref.watch(cacheMutationBusProvider),
    );
    ref.onDispose(() => unawaited(cache.dispose()));
    return cache;
  },
);
