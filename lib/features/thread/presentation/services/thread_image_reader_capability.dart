import 'package:flutter/material.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/presentation/widgets/image_retry_placeholder.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/domain/export/reader_image_export.dart';
import 'package:y300/features/reader_shared/presentation/continuous_image/continuous_image_reader_view.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_image_reader_exit_result.dart';

/// 帖子图片阅读器的"专属能力"实现。
///
/// 与漫画相比，帖子图片阅读是"通用阅读"的子集：保留模式切换/缩放/滑块/页码/显示
/// 设置（这些由引擎统一提供），去掉书签/下载/章节/上一话下一话/原帖等 detail 强
/// 相关项——做法是对相应能力返回空/`null`，由引擎据此自动隐藏，而非在引擎里写
/// if-else。图片内容通过共享 session entry 消费预加载结果，同时保留
/// [ReaderSessionImage] 内部的 [CachedLibraryImage] 查询与远端 fallback。
class ThreadImageReaderCapability extends ReaderCapability {
  ThreadImageReaderCapability({
    required this.request,
    required this.imageReferer,
    this.diagnosticRecorder = const NoopContinuousImageDiagnosticRecorder(),
    required String title,
    required String displayLabel,
    required String downloadLabel,
    Future<void> Function(ThreadImageReaderExitResult result)? onBeforeExit,
  }) : _title = title,
       _displayLabel = displayLabel,
       _downloadLabel = downloadLabel,
       _onBeforeExit = onBeforeExit,
       _currentIndex = request.initialIndex,
       _entries = List.unmodifiable(request.group.entries),
       _items = List.unmodifiable(request.continuousImages);

  final ThreadImageOpenRequest request;
  @override
  final ContinuousImageDiagnosticRecorder diagnosticRecorder;
  @override
  final String? imageReferer;
  String _title;
  String _displayLabel;
  String _downloadLabel;
  Future<void> Function(ThreadImageReaderExitResult result)? _onBeforeExit;
  final List<ThreadPostImageEntry> _entries;
  final List<ContinuousImageItem> _items;
  int _currentIndex;
  bool _interactionStarted = false;
  bool _hasNavigated = false;
  bool _retired = false;
  ContinuousImageReaderMode? _mode;
  Future<void>? _exitFuture;
  ThreadImageReaderExitResult? _frozenExitResult;

  void updatePresentation({
    required String title,
    required String displayLabel,
    required String downloadLabel,
    Future<void> Function(ThreadImageReaderExitResult result)? onBeforeExit,
  }) {
    _title = title;
    _displayLabel = displayLabel;
    _downloadLabel = downloadLabel;
    _onBeforeExit = onBeforeExit;
  }

  void noteInteraction() {
    if (_mode == ContinuousImageReaderMode.vertical) return;
    noteScrollInteraction();
  }

  void noteScrollInteraction() {
    _interactionStarted = true;
  }

  void retire() {
    _retired = true;
    if (_exitFuture != null) return;
    _frozenExitResult = null;
    _exitFuture = Future<void>.value();
  }

  @override
  void onScrollProgress({required int index, required double offset}) {
    if (_retired ||
        _exitFuture != null ||
        index < 0 ||
        index >= _items.length) {
      return;
    }
    // Initial layout can report a second short image already in the viewport.
    // Only navigation after an interaction may relocate the originating body.
    if (_interactionStarted && index != _currentIndex) {
      _hasNavigated = true;
    }
    _currentIndex = index;
  }

  @override
  Future<void> onSeek({required int index, required double offset}) async {
    if (_retired ||
        _exitFuture != null ||
        index < 0 ||
        index >= _items.length) {
      return;
    }
    // A confirmed slider seek is navigation even when initial layout already
    // reported this short image as the last one visible in the viewport.
    _hasNavigated = _hasNavigated || index != request.initialIndex;
    _currentIndex = index;
  }

  @override
  ThreadImageReaderExitResult? get exitResult {
    if (_retired) return null;
    if (_exitFuture != null) return _frozenExitResult;
    if (!_hasNavigated ||
        _currentIndex == request.initialIndex ||
        request.group.tid != request.tid ||
        request.group.pid != request.pid ||
        _entries.length != _items.length ||
        _currentIndex < 0 ||
        _currentIndex >= _entries.length) {
      return null;
    }
    final entry = _entries[_currentIndex];
    final item = _items[_currentIndex];
    if (entry.indexInPost != item.index ||
        entry.cacheKey != item.cacheKey ||
        entry.url != item.url) {
      return null;
    }
    return ThreadImageReaderExitResult(
      tid: request.tid,
      pid: request.pid,
      indexInPost: entry.indexInPost,
      cacheKey: entry.cacheKey,
      url: entry.url,
    );
  }

  @override
  Future<void> onExit() {
    final existing = _exitFuture;
    if (existing != null) return existing;
    final result = exitResult;
    final prepare = _onBeforeExit;
    _frozenExitResult = result;
    // Freeze first, then invoke the callback in a microtask so reentrant exit
    // and late position callbacks cannot start another body restoration.
    return _exitFuture = Future<void>.microtask(() async {
      if (_retired || result == null || prepare == null) return;
      try {
        await prepare(result);
      } catch (_) {
        // Return positioning is optional. A failed preparation must not trap
        // the user in the reader; the originating body retains its fallback.
      }
    });
  }

  @override
  ReaderKind get readerKind => ReaderKind.thread;

  @override
  ReaderContent get content {
    return ReaderContent(
      ownerId: 'thread:${request.tid}:post:${request.pid}',
      initialIndex: request.initialIndex,
      // request.continuousImages 已由 ThreadImageReaderContinuousImageAdapter
      // 在打开入口处映射好；显示偏好由共享引擎在布局时统一应用。
      items: _items,
    );
  }

  @override
  ReaderTitleSpec titleFor(ReaderEngineContext context) {
    _mode = context.mode;
    final total = context.totalCount;
    return ReaderTitleSpec(
      title: _title,
      subtitle: total > 0 ? '${context.currentIndex + 1} / $total' : '',
    );
  }

  // 帖子图片阅读器不提供书签/原帖/更多、章节/缓存、上一话下一话、过场卡、阅读
  // 进度落地；位置只通过本次路由返回，不写入长期阅读记录。
  @override
  List<ReaderToolbarAction> bottomActions(ReaderEngineContext context) {
    return [
      ReaderToolbarAction(
        id: 'display',
        icon: Icons.tune,
        label: _displayLabel,
        onPressed: context.actions.openDisplaySettings,
      ),
      ReaderToolbarAction(
        id: 'export-current-image',
        icon: Icons.download_outlined,
        label: _downloadLabel,
        onPressed: context.actions.exportCurrentImage,
      ),
    ];
  }

  @override
  ReaderImageExportMetadata? exportMetadataFor(ContinuousImageItem item) {
    return ReaderImageExportMetadata(
      baseName:
          'Y300-thread-${request.tid}-post-${request.pid}-${item.index + 1}',
      albumName: 'Y300',
    );
  }

  @override
  ImageCacheRequest cacheRequestFor(ContinuousImageItem item) {
    return ImageCacheRequest(
      cacheKey: item.cacheKey,
      sourceUrl: item.url,
      ownerType: ImageCacheOwnerType.thread,
      ownerId: item.ownerId,
      role: ImageCacheRole.threadInline,
      imageIndex: item.index,
      retentionClass: ImageRetentionClass.recentReader,
    );
  }

  @override
  ForumImageLoadSpec? imageLoadSpecFor(ContinuousImageItem item) {
    final uri = Uri.tryParse(item.url.trim());
    if (uri == null) {
      return null;
    }
    final request = cacheRequestFor(item);
    return ForumImageLoadSpec(
      kind: ForumImageKind.threadInline,
      url: uri,
      ownerId: request.ownerId,
      ownerType: ImageCacheOwnerType.thread,
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
    return ReaderSessionImage(
      sessionBinding: spec.sessionBinding,
      cacheRequest: cacheRequestFor(spec.item),
      fit: spec.fit,
      expectedDisplaySize: spec.expectedDisplaySize,
      width: spec.paged ? null : double.infinity,
      imageReferer: imageReferer,
      placeholder: const SizedBox.shrink(),
      // 失败位不自带宽高比：竖向连续模式由 ContinuousImageReaderSlot 按布局提示
      // 预留 minHeight，这里再套比例会顶掉预留高度，滑块 seek 就会落偏。
      errorPlaceholder: ImageRetryPlaceholder(
        onRetry: spec.onRetry,
        retryButtonKey: ValueKey<String>(
          'thread-image-reader-retry-${spec.item.id}',
        ),
      ),
      loadingIndicatorColor: spec.loadingIndicatorColor,
      onImageResolved: spec.onDimensionsResolved,
    );
  }
}
