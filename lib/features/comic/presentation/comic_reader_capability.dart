import 'dart:async';

import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/comic/presentation/controllers/comic_reader_controller.dart';
import 'package:y300/features/comic/presentation/services/comic_reader_continuous_image_adapter.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/domain/export/reader_image_export.dart';
import 'package:y300/features/reader_shared/domain/image_session/reader_image_session.dart';
import 'package:y300/features/reader_shared/domain/reader_preferences/reader_preferences.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';

/// 漫画阅读器的"专属能力"实现。
///
/// 把书签 / 原帖 / 更多 / 章节 / 缓存 / 上一话下一话 / 下一章过场卡 / 阅读进度落地
/// 全部收进本类，引擎只消费通用阅读壳。每次 build 用最新 viewState + 回调重建一个
/// 轻量实例（无内部可变状态），因此构造开销可忽略。
///
/// 设计：本类只"声明"能力（标题、动作、内容、回调），具体业务动作委托给上层注入
/// 的回调（`onShow*`/`onOpen*`），从而不持有 BuildContext，便于复用与测试。
class ComicReaderCapability extends ReaderCapability {
  ComicReaderCapability({
    required this.viewState,
    required this.preferences,
    required this.imageHeaderBuilder,
    required this.controller,
    required this.onShowMoreActions,
    required this.onShowChapterList,
    required this.onOpenSourceThread,
    required this.onToggleBookmark,
    required this.onOpenAdjacentEpisode,
    required this.buildNextChapterTransition,
    required this.exitResult,
    this.commentTailSurface,
    this.onLastImageVisible,
    this.diagnosticRecorder = const NoopContinuousImageDiagnosticRecorder(),
  });

  final ComicReaderViewState viewState;
  final ReaderPreferences preferences;
  @override
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ComicReaderController controller;
  @override
  final ContinuousImageDiagnosticRecorder diagnosticRecorder;

  @override
  ReaderKind get readerKind => ReaderKind.comic;

  @override
  ReaderImagePreparationSink get imagePreparationSink =>
      _ComicReaderImagePreparationSink(controller);

  final VoidCallback onShowMoreActions;
  final VoidCallback onShowChapterList;
  final VoidCallback onOpenSourceThread;
  final VoidCallback onToggleBookmark;
  final void Function({required bool previous}) onOpenAdjacentEpisode;
  final WidgetBuilder buildNextChapterTransition;
  final ReaderTailSurface? commentTailSurface;
  final VoidCallback? onLastImageVisible;

  @override
  ReaderTailSurface? get tailSurface => commentTailSurface;

  @override
  final Object? exitResult;

  static const ComicReaderContinuousImageAdapter _adapter =
      ComicReaderContinuousImageAdapter();

  @override
  ReaderContent get content {
    return ReaderContent(
      ownerId: viewState.episodeId,
      initialIndex: viewState.currentImageIndex,
      items: _adapter.mapImages(
        episodeId: viewState.episodeId,
        images: viewState.images,
        pageSpacing: preferences.pageSpacing,
      ),
    );
  }

  @override
  double? get initialVerticalScrollOffset =>
      viewState.lastScrollOffset > 0 ? viewState.lastScrollOffset : null;

  @override
  ReaderTitleSpec titleFor(ReaderEngineContext context) {
    return ReaderTitleSpec(
      title: viewState.comicTitle,
      subtitle: viewState.episodeTitle,
    );
  }

  @override
  String? topHint(ReaderEngineContext context) => viewState.hint;

  @override
  List<ReaderToolbarAction> topActions(ReaderEngineContext context) {
    return [
      ReaderToolbarAction(
        id: 'bookmark',
        icon: viewState.isBookmarked ? Icons.bookmark : Icons.bookmark_border,
        label: viewState.isBookmarked ? '取消书签' : '添加书签',
        onPressed: onToggleBookmark,
      ),
      ReaderToolbarAction(
        id: 'open-thread',
        icon: Icons.open_in_new,
        label: '打开原帖',
        onPressed: onOpenSourceThread,
      ),
      ReaderToolbarAction(
        id: 'more',
        icon: Icons.more_vert,
        label: '更多',
        onPressed: onShowMoreActions,
      ),
    ];
  }

  @override
  List<ReaderToolbarAction> bottomActions(ReaderEngineContext context) {
    return [
      ReaderToolbarAction(
        id: 'mode',
        icon: _modeIcon(preferences.readerMode),
        label: _modeLabel(preferences.readerMode),
        dismissMenu: false,
        onPressed: context.actions.cycleReaderMode,
      ),
      ReaderToolbarAction(
        id: 'catalog',
        icon: Icons.format_list_bulleted,
        label: '章节',
        onPressed: onShowChapterList,
      ),
      ReaderToolbarAction(
        id: 'display',
        icon: Icons.tune,
        label: '显示',
        onPressed: context.actions.openDisplaySettings,
      ),
      ReaderToolbarAction(
        id: 'export-current-image',
        icon: Icons.download_outlined,
        label: '下载当前图片',
        onPressed: context.actions.exportCurrentImage,
      ),
    ];
  }

  @override
  ReaderImageExportMetadata? exportMetadataFor(ContinuousImageItem item) {
    return ReaderImageExportMetadata(
      baseName:
          '${viewState.comicTitle}-${viewState.episodeTitle}-${item.index + 1}',
      albumName: 'Y300',
    );
  }

  @override
  ReaderChapterNavSpec? chapterNav(ReaderEngineContext context) {
    return ReaderChapterNavSpec(
      hasPrevious: viewState.hasPreviousEpisode,
      hasNext: viewState.hasNextEpisode,
      onPrevious: () => onOpenAdjacentEpisode(previous: true),
      onNext: () => onOpenAdjacentEpisode(previous: false),
      previousTooltip: viewState.hasPreviousEpisode ? '上一话' : '已是第一话',
      nextTooltip: viewState.hasNextEpisode ? '下一话' : '已是最后一话',
    );
  }

  @override
  WidgetBuilder? verticalTrailingBuilder(ReaderEngineContext context) {
    return buildNextChapterTransition;
  }

  @override
  void onImageVisible(int index) {
    unawaited(controller.onImageVisible(index));
    if (preferences.readerMode != ReaderModePreference.vertical &&
        index == viewState.images.length - 1) {
      onLastImageVisible?.call();
    }
  }

  @override
  void onScrollProgress({required int index, required double offset}) {
    controller.onScrollProgress(currentIndex: index, scrollOffset: offset);
  }

  @override
  Future<void> onSeek({required int index, required double offset}) {
    // 主动 seek（滑块/翻章）需要立即把目标页持久化，区别于滚动中的进度上报。
    return controller.jumpToImageIndex(index, scrollOffset: offset);
  }

  @override
  Future<void> onExit() => controller.onExitReader();

  @override
  ImageCacheRequest cacheRequestFor(ContinuousImageItem item) {
    final cacheKey = item.cacheKey.isNotEmpty
        ? item.cacheKey
        : ImageCacheKeys.comicPage(
            comicId: viewState.comicId,
            episodeId: viewState.episodeId,
            imageIndex: item.index,
          );
    return ImageCacheRequest(
      cacheKey: cacheKey,
      sourceUrl: item.url,
      ownerType: ImageCacheOwnerType.comic,
      ownerId: viewState.comicId,
      role: ImageCacheRole.comicPage,
      episodeId: viewState.episodeId,
      imageIndex: item.index,
      retentionClass: ImageRetentionClass.recentReader,
    );
  }

  @override
  String? initialLocalPathFor(ContinuousImageItem item) {
    return _imageForIndex(item.index)?.effectiveLocalPath;
  }

  @override
  ForumImageLoadSpec? imageLoadSpecFor(ContinuousImageItem item) {
    final uri = Uri.tryParse(item.url.trim());
    if (uri == null) {
      return null;
    }
    final request = cacheRequestFor(item);
    return ForumImageLoadSpec(
      kind: ForumImageKind.comicReaderPage,
      url: uri,
      ownerId: viewState.comicId,
      ownerType: ImageCacheOwnerType.comic,
      episodeId: viewState.episodeId,
      imageIndex: item.index,
      cacheKey: request.cacheKey,
      retentionClass: ImageRetentionClass.recentReader,
      htmlWidth: item.knownWidth?.toDouble(),
      htmlHeight: item.knownHeight?.toDouble(),
      allowReaderOpen: true,
    );
  }

  @override
  Widget buildImageContent(BuildContext context, ReaderImageBuildSpec spec) {
    final image = _imageForIndex(spec.index);
    if (image == null) {
      return const SizedBox.shrink();
    }
    final imageUrl = image.imageUrl;
    return ReaderSessionImage(
      sessionBinding: spec.sessionBinding,
      cacheRequest: cacheRequestFor(spec.item),
      fit: spec.fit,
      expectedDisplaySize: spec.expectedDisplaySize,
      width: spec.paged ? null : double.infinity,
      placeholder: _ComicReaderImageLoadingPlaceholder(
        paged: spec.paged,
        imageIndex: spec.index,
      ),
      errorPlaceholder: _ComicReaderImageErrorPlaceholder(
        imageUrl: imageUrl,
        paged: spec.paged,
        onRetry: spec.onRetry,
      ),
      headerBuilder: imageHeaderBuilder,
      onImageResolved: (size) => controller.onImageResolved(
        imageIndex: spec.index,
        imageUrl: imageUrl,
        width: size.width.round(),
        height: size.height.round(),
      ),
      onImageFailed: () => controller.onImageDisplayFailed(
        imageIndex: spec.index,
        imageUrl: imageUrl,
      ),
    );
  }

  ComicReaderImageState? _imageForIndex(int index) {
    if (index < 0 || index >= viewState.images.length) {
      return null;
    }
    return viewState.images[index];
  }

  IconData _modeIcon(ReaderModePreference mode) {
    switch (mode) {
      case ReaderModePreference.vertical:
        return Icons.view_stream_outlined;
      case ReaderModePreference.ltr:
        return Icons.swipe_left_outlined;
      case ReaderModePreference.rtl:
        return Icons.swipe_right_outlined;
    }
  }

  String _modeLabel(ReaderModePreference mode) {
    switch (mode) {
      case ReaderModePreference.vertical:
        return '垂直';
      case ReaderModePreference.ltr:
        return '左到右';
      case ReaderModePreference.rtl:
        return '右到左';
    }
  }
}

class _ComicReaderImagePreparationSink implements ReaderImagePreparationSink {
  const _ComicReaderImagePreparationSink(this.controller);

  final ComicReaderController controller;

  @override
  Future<void> record(ReaderImagePreparationRecord record) {
    return controller.recordPreparedReaderImage(record);
  }
}

class _ComicReaderImageLoadingPlaceholder extends StatelessWidget {
  const _ComicReaderImageLoadingPlaceholder({
    required this.paged,
    required this.imageIndex,
  });

  final bool paged;
  final int imageIndex;

  @override
  Widget build(BuildContext context) {
    final content = _ComicReaderLoadingIndicator(
      key: ValueKey<String>('comic-reader-image-loading-$imageIndex'),
      text: '图片加载中',
    );
    if (paged) {
      return Center(child: content);
    }
    final chromePalette = const ReaderChromePaletteResolver().resolve(
      Theme.of(context),
    );
    return ColoredBox(
      color: chromePalette.imageLoadingPlaceholderBackground,
      child: Center(child: content),
    );
  }
}

class _ComicReaderLoadingIndicator extends StatelessWidget {
  const _ComicReaderLoadingIndicator({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
        const SizedBox(height: 10),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ComicReaderImageErrorPlaceholder extends StatelessWidget {
  const _ComicReaderImageErrorPlaceholder({
    required this.imageUrl,
    required this.paged,
    required this.onRetry,
  });

  final String imageUrl;
  final bool paged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: paged ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('图片加载失败'),
        const SizedBox(height: 8),
        OutlinedButton(
          key: ValueKey<String>('comic-reader-retry-$imageUrl'),
          onPressed: onRetry,
          child: const Text('重试'),
        ),
      ],
    );
    if (paged) {
      return Center(child: content);
    }
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: content,
      ),
    );
  }
}
