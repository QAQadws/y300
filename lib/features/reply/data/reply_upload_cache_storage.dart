import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path_provider/path_provider.dart';

abstract class ReplyUploadCacheStorage {
  Future<bool> deleteCachePathIfOwned(String? cachePath);
}

class NoopReplyUploadCacheStorage implements ReplyUploadCacheStorage {
  const NoopReplyUploadCacheStorage();

  @override
  Future<bool> deleteCachePathIfOwned(String? cachePath) async {
    return false;
  }
}

class LocalReplyUploadCacheStorage implements ReplyUploadCacheStorage {
  LocalReplyUploadCacheStorage({
    FileSystem fileSystem = const LocalFileSystem(),
    Future<String> Function()? cacheRootPath,
  })  : _fileSystem = fileSystem,
        _cacheRootPath = cacheRootPath ?? _defaultCacheRootPath;

  final FileSystem _fileSystem;
  final Future<String> Function() _cacheRootPath;

  @override
  Future<bool> deleteCachePathIfOwned(String? cachePath) async {
    final path = cachePath?.trim();
    if (path == null || path.isEmpty) {
      return false;
    }

    final root = await _cacheRootPath();
    if (!_isOwnedByRoot(root, path)) {
      return false;
    }

    final file = _fileSystem.file(path);
    if (!file.existsSync()) {
      return false;
    }
    await file.delete();
    return true;
  }

  bool _isOwnedByRoot(String rootPath, String candidatePath) {
    final pathContext = _fileSystem.path;
    final root = pathContext.normalize(pathContext.absolute(rootPath));
    final candidate = pathContext.normalize(pathContext.absolute(candidatePath));
    if (candidate == root) {
      return false;
    }
    return candidate.startsWith('$root${pathContext.separator}');
  }

  static Future<String> _defaultCacheRootPath() async {
    final temporaryDirectory = await getTemporaryDirectory();
    return '${temporaryDirectory.path}/reply_uploads';
  }
}
