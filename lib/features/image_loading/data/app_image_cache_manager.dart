import 'dart:io' show File;

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:y300/features/image_loading/domain/app_image_source.dart';

/// 缓存层的磁盘图片缓存底座（Facade）。
///
/// 把 `flutter_cache_manager` 封装在背后，对外只暴露“按 cacheKey 存取文件”的
/// 最小能力。**缓存层不认识 owner/role/protected**——那是资产层的职责。
///
/// 设计意图：
/// - [AppImage] 的网络分支由 `CachedNetworkImage` 直接驱动下载+缓存，无需本类；
///   本类主要服务于 Phase 2 的预取器（提前把图下到磁盘）与资产层登记外部文件。
/// - 复用与 `DefaultImageCacheService` 同一个 [BaseCacheManager] 实例，
///   保证两者读写同一批磁盘文件，不再各自落盘。
abstract class AppImageCacheManager {
  /// 底层 `flutter_cache_manager` 实例。
  ///
  /// 仅供需要直接对接缓存库的展示路径使用（如 `CachedNetworkImageProvider`
  /// 需要传入同一个 cacheManager 以共享磁盘缓存）。业务代码应优先用下面的
  /// 语义化方法，而非直接操作它。
  BaseCacheManager get rawCacheManager;

  /// 取本地缓存文件；未命中返回 null，**不触发下载**。
  Future<File?> getFileFromCache(String cacheKey);

  /// 下载并写入缓存，返回本地文件。失败抛异常，由调用方兜底（占位/网络直显）。
  Future<File> downloadToCache(NetworkAppImageSource source);

  /// 把一个外部文件登记进缓存（同一 cacheKey 不重复落盘）。
  Future<void> putExternalFile({
    required String cacheKey,
    required String url,
    required File file,
  });
}

/// 基于 `flutter_cache_manager` 的默认实现。
class CacheManagerAppImageCacheManager implements AppImageCacheManager {
  const CacheManagerAppImageCacheManager(this._cacheManager);

  final BaseCacheManager _cacheManager;

  @override
  BaseCacheManager get rawCacheManager => _cacheManager;

  @override
  Future<File?> getFileFromCache(String cacheKey) async {
    final info = await _cacheManager.getFileFromCache(cacheKey);
    return info?.file;
  }

  @override
  Future<File> downloadToCache(NetworkAppImageSource source) async {
    final info = await _cacheManager.downloadFile(
      source.resolvedUrl,
      key: source.cacheKey,
      authHeaders: source.referer == null
          ? null
          : <String, String>{'Referer': source.referer!},
    );
    return info.file;
  }

  @override
  Future<void> putExternalFile({
    required String cacheKey,
    required String url,
    required File file,
  }) async {
    final bytes = await file.readAsBytes();
    final extension = _extensionFromPath(file.path);
    await _cacheManager.putFile(
      url,
      bytes,
      key: cacheKey,
      fileExtension: extension,
    );
  }

  String _extensionFromPath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) {
      return 'jpg';
    }
    return path.substring(dot + 1);
  }
}
