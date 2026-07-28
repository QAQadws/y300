import 'package:y300/features/comic/domain/services/comic_episode_images_fetch_result.dart';

/// 阅读器拉取单话图片失败的领域异常。
///
/// 由 `_ensureEpisodeImages` 在拿到 [ComicEpisodeImagesFetchFailed] 时抛出，
/// 让 AsyncValue 进入 error 态。UI 侧据此渲染重试入口（仅当 [isRetryable]
/// 为 true 时——`parse` 类失败重试也无意义）。
class ComicEpisodeImagesUnavailable implements Exception {
  const ComicEpisodeImagesUnavailable({required this.reason, this.message});

  final ComicEpisodeImagesFetchFailureReason reason;
  final String? message;

  /// 解析失败重试也是同样结果；其它 reason 都是瞬时的，重试有用。
  bool get isRetryable => reason != ComicEpisodeImagesFetchFailureReason.parse;

  @override
  String toString() {
    final detail = message;
    if (detail == null || detail.isEmpty) {
      return 'ComicEpisodeImagesUnavailable($reason)';
    }
    return 'ComicEpisodeImagesUnavailable($reason: $detail)';
  }
}
