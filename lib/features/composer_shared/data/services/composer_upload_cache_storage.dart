import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path_provider/path_provider.dart';

/// 维护"由 composer 上传流程产生的本地缓存图片"的删除责任。
///
/// 仅删除位于 composer 自己管理的目录下的文件，避免误删用户相册原图。
abstract class ComposerUploadCacheStorage {
  Future<bool> deleteCachePathIfOwned(String? cachePath);
}

/// Optional capability for implementations that can retain and query
/// composer-owned copies. Keeping it separate avoids breaking lightweight
/// deletion-only fakes and adapters.
abstract interface class ComposerUploadCacheRetentionStorage {
  Future<String?> retainUploadedCopy({
    required String sourcePath,
    required String localId,
    required String fileName,
  });

  bool cachePathExists(String? cachePath);
}

extension ComposerUploadCacheRetention on ComposerUploadCacheStorage {
  Future<String?> retainUploadedCopy({
    required String sourcePath,
    required String localId,
    required String fileName,
  }) {
    final storage = this;
    if (storage is ComposerUploadCacheRetentionStorage) {
      return (storage as ComposerUploadCacheRetentionStorage)
          .retainUploadedCopy(
            sourcePath: sourcePath,
            localId: localId,
            fileName: fileName,
          );
    }
    return Future<String?>.value();
  }

  bool cachePathExists(String? cachePath) {
    final storage = this;
    return storage is ComposerUploadCacheRetentionStorage &&
        (storage as ComposerUploadCacheRetentionStorage).cachePathExists(
          cachePath,
        );
  }
}

class NoopComposerUploadCacheStorage implements ComposerUploadCacheStorage {
  const NoopComposerUploadCacheStorage();

  @override
  Future<bool> deleteCachePathIfOwned(String? cachePath) async {
    return false;
  }
}

class LocalComposerUploadCacheStorage
    implements ComposerUploadCacheStorage, ComposerUploadCacheRetentionStorage {
  LocalComposerUploadCacheStorage({
    FileSystem fileSystem = const LocalFileSystem(),
    Future<String> Function()? cacheRootPath,
  }) : _fileSystem = fileSystem,
       _cacheRootPath = cacheRootPath ?? _defaultCacheRootPath;

  final FileSystem _fileSystem;
  final Future<String> Function() _cacheRootPath;

  @override
  Future<String?> retainUploadedCopy({
    required String sourcePath,
    required String localId,
    required String fileName,
  }) async {
    final normalizedSource = sourcePath.trim();
    if (normalizedSource.isEmpty) {
      return null;
    }
    final source = _fileSystem.file(normalizedSource);
    if (!source.existsSync()) {
      return null;
    }
    final rootPath = await _cacheRootPath();
    final pathContext = _fileSystem.path;
    final safeLocalId = _safeSegment(localId, fallback: 'upload');
    final safeFileName = _safeFileName(fileName);
    final directory = _fileSystem.directory(
      pathContext.join(rootPath, safeLocalId),
    );
    await directory.create(recursive: true);
    final targetPath = pathContext.join(directory.path, safeFileName);
    final normalizedTarget = pathContext.normalize(
      pathContext.absolute(targetPath),
    );
    final normalizedSourceAbsolute = pathContext.normalize(
      pathContext.absolute(source.path),
    );
    if (normalizedSourceAbsolute == normalizedTarget) {
      return normalizedTarget;
    }

    final temporary = _fileSystem.file(
      '$normalizedTarget.part-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await source.copy(temporary.path);
      final target = _fileSystem.file(normalizedTarget);
      if (target.existsSync()) {
        await target.delete();
      }
      await temporary.rename(normalizedTarget);
      return normalizedTarget;
    } finally {
      if (temporary.existsSync()) {
        await temporary.delete();
      }
    }
  }

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

  @override
  bool cachePathExists(String? cachePath) {
    final path = cachePath?.trim();
    if (path == null || path.isEmpty) {
      return false;
    }
    return _fileSystem.file(path).existsSync();
  }

  bool _isOwnedByRoot(String rootPath, String candidatePath) {
    final pathContext = _fileSystem.path;
    final root = pathContext.normalize(pathContext.absolute(rootPath));
    final candidate = pathContext.normalize(
      pathContext.absolute(candidatePath),
    );
    if (candidate == root) {
      return false;
    }
    return candidate.startsWith('$root${pathContext.separator}');
  }

  String _safeSegment(String value, {required String fallback}) {
    final normalized = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (normalized.isEmpty || normalized == '.' || normalized == '..') {
      return fallback;
    }
    return normalized;
  }

  String _safeFileName(String value) {
    final pathContext = _fileSystem.path;
    final baseName = pathContext.basename(value.trim());
    final extension = pathContext.extension(baseName).toLowerCase();
    final safeExtension = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)
        ? extension
        : '.image';
    return 'preview$safeExtension';
  }

  // 旧实现使用 `${tmp}/reply_uploads` 作为根目录；保留同名以兼容已经存在
  // 的本地缓存文件，否则升级后老草稿引用的图片会变成"非本路径下"而无法清理。
  static Future<String> _defaultCacheRootPath() async {
    final temporaryDirectory = await getTemporaryDirectory();
    return '${temporaryDirectory.path}/reply_uploads';
  }
}
