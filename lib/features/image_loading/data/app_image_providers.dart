import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/image_loading/data/app_image_cache_manager.dart';

/// 应用唯一的图片缓存 Facade。
///
/// 复用 `imageCacheManagerProvider` 暴露的同一个 `flutter_cache_manager` 实例，
/// 让缓存层（[AppImage]/预取器）与资产层（`DefaultImageCacheService`）读写同一
/// 批磁盘文件，避免重复落盘。底层 cacheManager 异步解析目录，因此这里也是
/// FutureProvider。
final appImageCacheManagerProvider = FutureProvider<AppImageCacheManager>((
  ref,
) async {
  final cacheManager = await ref.watch(imageCacheManagerProvider.future);
  return CacheManagerAppImageCacheManager(cacheManager);
});
