import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_models.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/continuous_image/continuous_image_reader_view.dart';

/// 阅读内容来源：已由各业务 adapter 映射好的连续图片项 + 初始位置 + owner 标识。
///
/// 引擎只消费 [ContinuousImageItem]，不感知漫画页或帖子图片的业务差异。
class ReaderContent {
  const ReaderContent({
    required this.ownerId,
    required this.items,
    this.initialIndex = 0,
  });

  /// 用于区分连续图片所属实体（章节 id / 帖子楼层），驱动 extent 注册与复位。
  final String ownerId;
  final List<ContinuousImageItem> items;
  final int initialIndex;

  bool get isEmpty => items.isEmpty;
  int get length => items.length;
}

/// 顶部标题/副标题。
class ReaderTitleSpec {
  const ReaderTitleSpec({required this.title, this.subtitle = ''});

  final String title;
  final String subtitle;
}

/// 进度条两端的"翻章"能力。
///
/// 漫画提供上一话/下一话；帖子图片返回 null（引擎据此隐藏翻章按钮）。
class ReaderChapterNavSpec {
  const ReaderChapterNavSpec({
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
    this.previousTooltip = '上一章',
    this.nextTooltip = '下一章',
    this.nextIcon = Icons.skip_next,
  });

  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final String previousTooltip;
  final String nextTooltip;
  final IconData nextIcon;
}

/// 引擎向能力提供方暴露的只读上下文快照。
///
/// 让能力实现据此构造标题/动作，而无需反向依赖引擎内部状态。
class ReaderEngineContext {
  const ReaderEngineContext({
    required this.currentIndex,
    required this.totalCount,
    required this.mode,
  });

  final int currentIndex;
  final int totalCount;
  final ContinuousImageReaderMode mode;
}

/// 一台具体阅读器的"专属能力"。[ImageReaderEngine] 只认这个抽象。
///
/// 设计目标：把"通用阅读壳"（滚动锚定、缩放、overlay、滑块、页码、显示设置）
/// 与"业务专属能力"（章节、书签、缓存、下载、原帖跳转、阅读进度落地）解耦。
/// 帖子图片阅读器对大多数方法返回空/`null`，UI 据此自动瘦身——去掉 detail 强
/// 相关项靠"能力为空"，而非引擎内 if-else。
abstract class ReaderCapability {
  /// 阅读内容来源。
  ReaderContent get content;

  /// 图片请求头构建器（鉴权/Referer）。
  ImageRequestHeaderBuilder? get imageHeaderBuilder;

  /// 顶部标题/副标题。
  ReaderTitleSpec titleFor(ReaderEngineContext context);

  /// 顶部额外动作（漫画：书签/原帖/更多；帖子图片：通常为空或仅"复制链接"）。
  List<ReaderToolbarAction> topActions(ReaderEngineContext context) {
    return const <ReaderToolbarAction>[];
  }

  /// 底部额外动作（漫画：章节/缓存；帖子图片：通常仅"显示设置"）。
  List<ReaderToolbarAction> bottomActions(ReaderEngineContext context) {
    return const <ReaderToolbarAction>[];
  }

  /// 进度条两端的翻章能力；返回 null 表示不显示。
  ReaderChapterNavSpec? chapterNav(ReaderEngineContext context) => null;

  /// 垂直模式列表尾部过场组件（漫画：下一章过场卡；帖子图片：null）。
  WidgetBuilder? verticalTrailingBuilder(ReaderEngineContext context) => null;

  /// 某张图片进入可见区域时回调（漫画用于落地阅读进度；帖子图片可空实现）。
  void onImageVisible(int index) {}

  /// 滚动进度变化回调（同上）。
  void onScrollProgress({required int index, required double offset}) {}

  /// 退出阅读器时回调（漫画用于 flush 阅读进度；帖子图片可空实现）。
  Future<void> onExit() async {}

  /// 为某连续图片项构造缓存请求（供解码预热与图片加载）。
  ImageCacheRequest cacheRequestFor(ContinuousImageItem item);
}
