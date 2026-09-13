import 'package:y300/features/library_shared/data/services/library_cover_thumbnail_store.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_thumbnail_providers.dart';
import 'package:y300/features/library_shared/presentation/images/library_cover_load_trace.dart';

void main() {
  String source(String path) => File(path).readAsStringSync(encoding: utf8);

  test(
    'thumbnail assembly is a leaf independent of network and original stores',
    () {
      final file = source(
        'lib/features/library_shared/data/providers/library_cover_thumbnail_providers.dart',
      );
      final bus = source(
        'lib/features/cache/data/providers/cache_mutation_provider.dart',
      );
      for (final forbidden in [
        'image_cache_providers.dart',
        'library_cover_providers.dart',
        'core/network/',
        'sqflite',
        'cache_mutation_provider.dart',
      ]) {
        expect(file, isNot(contains(forbidden)));
        expect(bus, isNot(contains(forbidden)));
      }
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Construction alone must not invoke a platform directory, network or DB.
      expect(
        container.read(libraryCoverThumbnailStoreProvider),
        isA<LibraryCoverThumbnailStore>(),
      );
    },
  );

  test('thumbnail generation cannot open or decode original files again', () {
    final writer = source(
      'lib/features/library_shared/presentation/images/library_cover_thumbnail_writer.dart',
    );
    for (final forbidden in [
      'instantiateImageCodec(',
      'fromFilePath(',
      '.resolve(',
      'dart:io',
    ]) {
      expect(writer, isNot(contains(forbidden)));
    }
    expect(writer, contains('image.clone()'));
    expect(writer, contains('ui.ImageByteFormat.png'));
  });

  test('cover trace is opt-in and does not receive source metadata', () {
    expect(LibraryCoverLoadTrace.enabled, isFalse);
    final trace = source(
      'lib/features/library_shared/presentation/images/library_cover_load_trace.dart',
    );
    for (final forbidden in [
      'sourceUrl',
      'assetId',
      'localPath',
      'referer',
      'Cookie',
      'username',
    ]) {
      expect(trace, isNot(contains(forbidden)));
    }
    expect(trace, contains('!kReleaseMode'));
    expect(trace, contains('Y300_COVER_TRACE'));
  });
}
