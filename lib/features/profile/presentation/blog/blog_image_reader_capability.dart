import 'package:flutter/material.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/presentation/widgets/image_retry_placeholder.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/profile/presentation/blog/blog_image_reader_request.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/domain/export/reader_image_export.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';

/// Blog ownership stays separate from thread and comic download semantics.
final class BlogImageReaderCapability extends ReaderCapability {
  BlogImageReaderCapability({
    required this.request,
    required this.imageReferer,
    required this.title,
    required this.displayLabel,
    required this.exportLabel,
  });

  final BlogImageReaderRequest request;
  @override
  final String imageReferer;
  final String title;
  final String displayLabel;
  final String exportLabel;

  @override
  ReaderContent get content => ReaderContent(
    ownerId: request.items.first.ownerId,
    items: request.items,
    initialIndex: request.initialIndex,
  );

  @override
  ReaderTitleSpec titleFor(ReaderEngineContext context) => ReaderTitleSpec(
    title: title,
    subtitle: '${context.currentIndex + 1} / ${context.totalCount}',
  );

  @override
  List<ReaderToolbarAction> bottomActions(ReaderEngineContext context) => [
    ReaderToolbarAction(
      id: 'display',
      icon: Icons.tune,
      label: displayLabel,
      onPressed: context.actions.openDisplaySettings,
    ),
    ReaderToolbarAction(
      id: 'export-current-image',
      icon: Icons.download_outlined,
      label: exportLabel,
      onPressed: context.actions.exportCurrentImage,
    ),
  ];

  @override
  ImageCacheRequest cacheRequestFor(ContinuousImageItem item) =>
      request.requests[item.index];

  @override
  ReaderImageExportMetadata? exportMetadataFor(ContinuousImageItem item) =>
      ReaderImageExportMetadata(
        baseName:
            'Y300-blog-${cacheRequestFor(item).ownerId}-${item.index + 1}',
        albumName: 'Y300',
      );

  @override
  Widget buildImageContent(BuildContext context, ReaderImageBuildSpec spec) =>
      ReaderSessionImage(
        sessionBinding: spec.sessionBinding,
        cacheRequest: cacheRequestFor(spec.item),
        fit: spec.fit,
        expectedDisplaySize: spec.expectedDisplaySize,
        width: spec.paged ? null : double.infinity,
        imageReferer: imageReferer,
        placeholder: const SizedBox.shrink(),
        errorPlaceholder: ImageRetryPlaceholder(onRetry: spec.onRetry),
        loadingIndicatorColor: spec.loadingIndicatorColor,
        onImageResolved: spec.onDimensionsResolved,
      );
}
