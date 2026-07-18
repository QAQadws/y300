import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves the image cache under the platform-managed temporary directory.
/// User-selected storage only controls downloads and never redirects caches.
class ImageCacheDirectoryResolver {
  const ImageCacheDirectoryResolver();

  static const String imageCacheFolderName = 'y300_image_cache';
  static const String protectedFolderName = 'protected';

  Future<String> resolveImageCacheRoot() async {
    final basePath = (await getTemporaryDirectory()).path;
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
