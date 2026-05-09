import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/app_storage_keys.dart';

/// Resolves the image cache root used by the stage-04 cache service.
///
/// The old comic cache directory preference is still honored so existing users
/// do not unexpectedly move their cache.  New code should treat this as a
/// generic image cache root rather than a comic-only directory.
class ImageCacheDirectoryResolver {
  const ImageCacheDirectoryResolver();

  static const String imageCacheFolderName = 'y300_image_cache';
  static const String protectedFolderName = 'protected';

  Future<String> resolveImageCacheRoot() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(AppStorageKeys.comicCacheDirectory)?.trim();
    final basePath = custom == null || custom.isEmpty
        ? (await getTemporaryDirectory()).path
        : custom;
    final directory = io.Directory(p.join(basePath, imageCacheFolderName));
    await _prepareDirectory(directory);
    return directory.path;
  }

  Future<String> resolveProtectedDirectory() async {
    final root = await resolveImageCacheRoot();
    final directory = io.Directory(p.join(root, protectedFolderName));
    await _prepareDirectory(directory);
    return directory.path;
  }

  Future<void> _prepareDirectory(io.Directory directory) async {
    await directory.create(recursive: true);
    final marker = io.File(p.join(directory.path, '.nomedia'));
    if (!await marker.exists()) {
      await marker.writeAsString('');
    }
  }
}
