import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';

/// 帖子图片阅读器的"专属能力"实现。
///
/// 与漫画相比，帖子图片阅读是"通用阅读"的子集：保留模式切换/缩放/滑块/页码/显示
/// 设置（这些由引擎统一提供），去掉书签/下载/章节/上一话下一话/原帖等 detail 强
/// 相关项——做法是对相应能力返回空/`null`，由引擎据此自动隐藏，而非在引擎里写
/// if-else。图片内容用 [CachedLibraryImage]（request 驱动），与漫画的 localPath
/// 驱动互不影响。
class ThreadImageReaderCapability extends ReaderCapability {
  ThreadImageReaderCapability({
    required this.request,
    required this.imageHeaderBuilder,
    this.diagnosticRecorder = const NoopContinuousImageDiagnosticRecorder(),
    this.title = '图片阅读',
  });

  final ThreadImageOpenRequest request;
  @override
  final ContinuousImageDiagnosticRecorder diagnosticRecorder;
  @override
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final String title;

  @override
  ReaderKind get readerKind => ReaderKind.thread;

  @override
  ReaderContent get content {
    return ReaderContent(
      ownerId: 'thread:${request.tid}:post:${request.pid}',
      initialIndex: request.initialIndex,
      // request.continuousImages 已由 ThreadImageReaderContinuousImageAdapter
      // 在打开入口处映射好，这里直接复用，避免二次映射。
      items: request.continuousImages,
    );
  }

  @override
  ReaderTitleSpec titleFor(ReaderEngineContext context) {
    final total = context.totalCount;
    return ReaderTitleSpec(
      title: title,
      subtitle: total > 0 ? '${context.currentIndex + 1} / $total' : '',
    );
  }

  // 帖子图片阅读器不提供书签/原帖/更多、章节/缓存、上一话下一话、过场卡、阅读
  // 进度落地——全部沿用 ReaderCapability 的默认空实现。底部仅保留"显示设置"。
  @override
  List<ReaderToolbarAction> bottomActions(ReaderEngineContext context) {
    return [
      ReaderToolbarAction(
        id: 'display',
        icon: Icons.tune,
        label: '显示',
        onPressed: context.actions.openDisplaySettings,
      ),
    ];
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
    return CachedLibraryImage(
      request: cacheRequestFor(spec.item),
      fit: spec.fit,
      width: spec.paged ? null : double.infinity,
      headerBuilder: imageHeaderBuilder,
      placeholder: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
      errorPlaceholder: const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}
