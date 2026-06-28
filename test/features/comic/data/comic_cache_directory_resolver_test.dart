import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/app_storage_keys.dart';
import 'package:y300/features/comic/data/providers/comic_cache_directory_provider.dart';

void main() {
  test('resolver uses custom cache directory when configured', () async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      AppStorageKeys.comicCacheDirectory: '/tmp/y300-custom-cache',
    });

    const resolver = ComicCacheDirectoryResolver();
    final resolved = await resolver.resolve();

    expect(
      resolved,
      p.join('/tmp/y300-custom-cache', ComicCacheDirectoryResolver.cacheFolderName),
    );
    expect(await Directory(resolved).exists(), isTrue);
  });
}
