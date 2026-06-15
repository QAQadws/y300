/// 单话图片拉取的"失败原因"——从核心网络层 `ApiErrorType` 翻译过来的
/// 域内分类，避免 comic 域反向依赖 `lib/core/network/api_result.dart`。
///
/// `parse` 是不可重试的（页面结构变了，再来一遍还是错）；其余都属于
/// 瞬时态，UI 应当提供重试入口。
enum ComicEpisodeImagesFetchFailureReason {
  network,
  auth,
  server,
  parse,
  unknown,
}

/// 单话图片拉取的结果。
///
/// 区分两种过去被混为一谈的情况：
/// 1. **拉成功 + 首楼真没有图**（`ComicEpisodeImagesFetched(imageUrls = [])`），
///    属于合法空态，UI 该显示"无图"提示。
/// 2. **拉失败**（`ComicEpisodeImagesFetchFailed`），含网络抖动 / 登录态过期 /
///    服务 5xx / 解析异常等，UI 该显示错误并提供重试。
///
/// 历史上 `Future<List<String>>` 把两者抹平成空列表，导致瞬时网络错误 → 用户
/// 看到"当前章节没有可阅读图片"假象。
sealed class ComicEpisodeImagesFetchResult {
  const ComicEpisodeImagesFetchResult();

  /// 兼容旧 `fetchEpisodeImagesByTid` 行为：失败时降级为空列表。
  /// 仅供尚未迁移到 sealed 模式的调用方使用。
  List<String> get imageUrlsOrEmpty => switch (this) {
        ComicEpisodeImagesFetched(:final imageUrls) => imageUrls,
        ComicEpisodeImagesFetchFailed() => const <String>[],
      };
}

class ComicEpisodeImagesFetched extends ComicEpisodeImagesFetchResult {
  const ComicEpisodeImagesFetched(this.imageUrls);

  final List<String> imageUrls;
}

class ComicEpisodeImagesFetchFailed extends ComicEpisodeImagesFetchResult {
  const ComicEpisodeImagesFetchFailed({required this.reason, this.message});

  final ComicEpisodeImagesFetchFailureReason reason;
  final String? message;
}
