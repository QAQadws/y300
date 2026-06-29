import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/site_url_resolver.dart';

/// 显示控件 [AppImage] 的唯一输入：描述“这是哪张图、怎么取”。
///
/// 它**不携带任何 owner/role/protected 业务语义**——那些属于资产层。
/// 这样显示控件与业务缓存策略彻底解耦（DIP）：UI 只依赖这个抽象，
/// 不感知 flutter_cache_manager / SQLite 等具体实现。
///
/// 采用 sealed + 子类（Strategy）：不同来源各自决定如何取图，而 [AppImage]
/// 只对来源类型做分支，不内联具体取数逻辑。
sealed class AppImageSource {
  const AppImageSource();

  /// 用于磁盘/内存缓存与预取去重的稳定 key。
  ///
  /// 网络源用规范化后的绝对 URL，保证“同一张图同一 key”，避免相对/绝对 URL
  /// 各落一份缓存（对齐缓存方案 §6.3）。
  String get cacheKey;
}

/// 普通可再生网络图：封面、帖子正文图、在线浏览的阅读器图都走这里。
///
/// 这类图属于“缓存层”——丢了可重新下载，按 URL key + LRU 管理，不进资产账本。
class NetworkAppImageSource extends AppImageSource {
  NetworkAppImageSource({
    required String url,
    this.headerBuilder,
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : resolvedUrl = urlResolver.resolve(url.trim()) ?? url.trim();

  /// 规范化后的绝对 URL（相对路径已解析为站点绝对地址）。
  final String resolvedUrl;

  /// 异步请求头构建器（Discuz 图片需要 Referer / Cookie 等）。
  final ImageRequestHeaderBuilder? headerBuilder;

  @override
  String get cacheKey => resolvedUrl;
}

/// 资产层提供的本地文件：用户自定义封面、已下载章节图等。
///
/// 由资产层解析出 [localPath] 后注入，[AppImage] 直接读本地文件展示，
/// 不再触发任何网络请求。
class LocalAssetImageSource extends AppImageSource {
  const LocalAssetImageSource({
    required this.localPath,
    required this.identity,
  });

  final String localPath;

  /// 该本地资产的稳定身份（如 `custom_cover/comic/{id}`），用于 key 去重。
  final String identity;

  @override
  String get cacheKey => identity;
}
