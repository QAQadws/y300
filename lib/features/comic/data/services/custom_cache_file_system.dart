import 'package:file/file.dart' hide FileSystem;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;

/// File system adapter for flutter_cache_manager that writes files into a
/// provided absolute directory path.
class CustomPathFileSystem implements FileSystem {
  CustomPathFileSystem({
    required String basePath,
    required this.cacheKey,
  }) : _directoryFuture = _createDirectory(basePath, cacheKey);

  final String cacheKey;
  final Future<Directory> _directoryFuture;

  static Future<Directory> _createDirectory(String basePath, String cacheKey) async {
    final path = p.join(basePath, cacheKey);
    const fs = LocalFileSystem();
    final directory = fs.directory(path);
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<File> createFile(String name) async {
    final directory = await _directoryFuture;
    if (!(await directory.exists())) {
      await directory.create(recursive: true);
    }
    return directory.childFile(name);
  }
}
