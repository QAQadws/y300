import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_models.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/domain/export/reader_image_export.dart';
import 'package:y300/features/reader_shared/domain/image_session/reader_image_session.dart';
import 'package:y300/features/reader_shared/presentation/continuous_image/continuous_image_reader_view.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_tail_surface.dart';
import 'package:y300/features/reader_shared/presentation/services/reader_image_session_store.dart';

enum ReaderKind { generic, thread, comic }

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

/// 引擎暴露给能力的可调用动作。
///
/// 让能力在构造工具栏动作时复用引擎内置的显示设置、模式切换与导出动作，而由能力
/// 自己决定把它们放在工具栏的哪个位置、配什么图标——漫画与帖子的工具栏布局因此
/// 可以不同，引擎不必硬编码任何一栏。
abstract interface class ReaderEngineActions {
  void openDisplaySettings();

  void cycleReaderMode();

  /// 保留给需要显式选择模式的通用阅读器入口。
  void openModeSheet();

  void exportCurrentImage();
}

/// 引擎向能力提供方暴露的只读上下文快照。
///
/// 让能力实现据此构造标题/动作，而无需反向依赖引擎内部状态。
class ReaderEngineContext {
  const ReaderEngineContext({
    required this.currentIndex,
    required this.totalCount,
    required this.mode,
    required this.actions,
  });

  final int currentIndex;
  final int totalCount;
  final ContinuousImageReaderMode mode;

  /// 引擎内置动作句柄（显示设置、模式切换和图片导出）。
  final ReaderEngineActions actions;
}

/// One image that belongs to an adjacent reader owner.
///
/// This is deliberately a load specification rather than a business image
/// model. The shared engine can schedule it without knowing whether the next
/// owner is a comic episode, a thread, or another image sequence.
class ReaderAdjacentPreloadImage {
  const ReaderAdjacentPreloadImage({
    required this.itemId,
    required this.imageIndex,
    required this.spec,
  });

  final String itemId;
  final int imageIndex;
  final ForumImageLoadSpec spec;
}

/// A bounded lookahead plan for the next reader owner.
///
/// The preload coordinator applies the shared decoded/disk window policy to
/// this list. The producing capability remains responsible for resolving the
/// next owner and mapping its images to cache specifications.
class ReaderAdjacentPreloadPlan {
  const ReaderAdjacentPreloadPlan({
    required this.ownerId,
    required this.images,
  });

  final String ownerId;
  final List<ReaderAdjacentPreloadImage> images;
}

/// 引擎构造单张图片时透传给能力的参数。
///
/// 缩放包装与高度槽由引擎统一负责，能力只产出"图片内容本体"（缓存图片 +
/// 占位/错误态），从而漫画可保留 [LibraryCachedImage] + 重试回调，帖子图片可用
/// [CachedLibraryImage] + request，互不干扰。
class ReaderImageBuildSpec {
  const ReaderImageBuildSpec({
    required this.item,
    required this.index,
    required this.paged,
    required this.fit,
    required this.sessionBinding,
    required this.expectedDisplaySize,
    required this.onRetry,
  });

  final ContinuousImageItem item;
  final int index;

  /// 横向单页模式为 true，垂直连续模式为 false。
  final bool paged;
  final BoxFit fit;
  final ReaderImageSessionBinding sessionBinding;
  final Size expectedDisplaySize;
  final VoidCallback onRetry;
}

/// 一台具体阅读器的"专属能力"。[ImageReaderEngine] 只认这个抽象。
///
/// 设计目标：把"通用阅读壳"（滚动锚定、缩放、overlay、滑块、页码、显示设置）
/// 与"业务专属能力"（章节、书签、缓存、下载、原帖跳转、阅读进度落地）解耦。
/// 帖子图片阅读器对大多数方法返回空/`null`，UI 据此自动瘦身——去掉 detail 强
/// 相关项靠"能力为空"，而非引擎内 if-else。
abstract class ReaderCapability {
  ReaderKind get readerKind => ReaderKind.generic;

  /// 阅读内容来源。
  ReaderContent get content;

  /// 阅读器诊断记录器。默认 no-op，业务方可在诊断模式下覆写。
  ContinuousImageDiagnosticRecorder get diagnosticRecorder =>
      const NoopContinuousImageDiagnosticRecorder();

  /// 图片请求头构建器（鉴权/Referer）。
  ImageRequestHeaderBuilder? get imageHeaderBuilder;

  /// Optional non-blocking business metadata writer for prepared images.
  ReaderImagePreparationSink? get imagePreparationSink => null;

  /// Export metadata for the current image. Returning null disables the shared
  /// export action without making the engine aware of business types.
  ReaderImageExportMetadata? exportMetadataFor(ContinuousImageItem item) =>
      null;

  /// 顶部标题/副标题。
  ReaderTitleSpec titleFor(ReaderEngineContext context);

  /// 构造单张图片的内容本体（不含缩放包装/高度槽，由引擎统一负责）。
  Widget buildImageContent(BuildContext context, ReaderImageBuildSpec spec);

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

  /// Optional neutral content after the image sequence. Returning null keeps
  /// the engine's legacy image-only behavior byte-for-byte at the UI level.
  ReaderTailSurface? get tailSurface => null;

  /// Builds a lookahead plan for content after [tailSurface].
  ///
  /// The shared reader schedules the returned specs through its existing
  /// session preload coordinator. A capability may do asynchronous repository
  /// work here, but it must not mutate reader position or download state.
  Future<ReaderAdjacentPreloadPlan?> buildAdjacentPreloadPlan() async => null;

  /// 内容区顶部提示条（漫画：离线/错误提示；帖子图片：null）。
  String? topHint(ReaderEngineContext context) => null;

  /// 退出阅读器时回传给上一页的结果（漫画：阅读进度/已读集合；帖子图片：null）。
  Object? get exitResult => null;

  /// 进入垂直模式时的初始滚动偏移（漫画用于恢复阅读进度）；null 表示从顶部开始。
  double? get initialVerticalScrollOffset => null;

  /// 某张图片进入可见区域时回调（漫画用于落地阅读进度；帖子图片可空实现）。
  void onImageVisible(int index) {}

  /// 滚动进度变化回调（同上）。
  void onScrollProgress({required int index, required double offset}) {}

  /// 用户通过滑块/翻章主动跳转到某索引后的回调（已落到目标位置）。
  ///
  /// 默认转交 [onScrollProgress]；漫画覆写以调用其 `jumpToImageIndex`，把"主动
  /// seek"与"滚动中进度上报"区分开（前者需要立即持久化目标页）。
  Future<void> onSeek({required int index, required double offset}) async {
    onScrollProgress(index: index, offset: offset);
  }

  /// 退出阅读器时回调（漫画用于 flush 阅读进度；帖子图片可空实现）。
  Future<void> onExit() async {}

  /// 为某连续图片项构造缓存请求（供解码预热与图片加载）。
  ImageCacheRequest cacheRequestFor(ContinuousImageItem item);

  /// Existing business-local path used to seed a new shared reader session.
  String? initialLocalPathFor(ContinuousImageItem item) => null;

  /// 为阅读会话预热构造统一图片请求。
  ///
  /// 默认实现从旧的 [cacheRequestFor] 映射，业务阅读器可以覆写以保留更精确的
  /// kind / owner / retention 语义。
  ForumImageLoadSpec? imageLoadSpecFor(ContinuousImageItem item) {
    final request = cacheRequestFor(item);
    final uri = Uri.tryParse(request.sourceUrl.trim());
    if (uri == null) {
      return null;
    }
    return ForumImageLoadSpec(
      kind: _kindForRole(request.role),
      url: uri,
      ownerId: request.ownerId,
      ownerType: request.ownerType,
      episodeId: request.episodeId,
      imageIndex: request.imageIndex ?? item.index,
      cacheKey: request.cacheKey,
      retentionClass: request.retentionClass,
      htmlWidth: item.knownWidth?.toDouble(),
      htmlHeight: item.knownHeight?.toDouble(),
      protected: request.protected,
      allowReaderOpen: true,
    );
  }

  ForumImageKind _kindForRole(ImageCacheRole role) {
    switch (role) {
      case ImageCacheRole.comicPage:
        return ForumImageKind.comicReaderPage;
      case ImageCacheRole.threadAttachment:
        return ForumImageKind.threadAttachment;
      case ImageCacheRole.blogInline:
        return ForumImageKind.blogInline;
      case ImageCacheRole.remoteSmiley:
        return ForumImageKind.remoteSmiley;
      case ImageCacheRole.avatar:
        return ForumImageKind.avatar;
      case ImageCacheRole.forumHeadImage:
        return ForumImageKind.forumHeadImage;
      case ImageCacheRole.forumIcon:
        return ForumImageKind.forumIcon;
      case ImageCacheRole.cover:
        return ForumImageKind.cover;
      case ImageCacheRole.customCover:
        return ForumImageKind.customCover;
      case ImageCacheRole.threadInline:
      case ImageCacheRole.novelInline:
        return ForumImageKind.threadInline;
    }
  }
}
