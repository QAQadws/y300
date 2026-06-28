import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path_provider/path_provider.dart';

/// 维护"由 composer 上传流程产生的本地缓存图片"的删除责任。
///
/// 仅删除位于 composer 自己管理的目录下的文件，避免误删用户相册原图。
abstract class ComposerUploadCacheStorage {
  Future<bool> deleteCachePathIfOwned(String? cachePath);
}

class NoopComposerUploadCacheStorage implements ComposerUploadCacheStorage {
  const NoopComposerUploadCacheStorage();

  @override
  Future<bool> deleteCachePathIfOwned(String? cachePath) async {
    return false;
  }
}

class LocalComposerUploadCacheStorage implements ComposerUploadCacheStorage {
  LocalComposerUploadCacheStorage({
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

  // 旧实现使用 `${tmp}/reply_uploads` 作为根目录；保留同名以兼容已经存在
  // 的本地缓存文件，否则升级后老草稿引用的图片会变成"非本路径下"而无法清理。
  static Future<String> _defaultCacheRootPath() async {
    final temporaryDirectory = await getTemporaryDirectory();
    return '${temporaryDirectory.path}/reply_uploads';
  }
}
