import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/reader_image_cache_lifecycle.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';

class ThreadReaderImageSourceBuilder {
  const ThreadReaderImageSourceBuilder({
    required ForumImageSourcePipeline imageSourcePipeline,
  }) : _imageSourcePipeline = imageSourcePipeline;

  final ForumImageSourcePipeline _imageSourcePipeline;

  List<ReaderImageSource> buildFromPost({
    required ThreadPost post,
    required String tid,
  }) {
    final ownerId = tid.trim().isEmpty ? 'unknown' : tid.trim();
    final sources = _imageSourcePipeline.collectFromPost(post);
    return [
      for (var index = 0; index < sources.length; index++)
        _toReaderImageSource(
          source: sources[index],
          tid: ownerId,
          index: index,
        ),
    ];
  }

  ReaderImageSource _toReaderImageSource({
    required ForumImageSource source,
    required String tid,
    required int index,
  }) {
    final role = source.origin == ForumImageSourceOrigin.attachment
        ? ImageCacheRole.threadAttachment
        : ImageCacheRole.threadInline;
    return ReaderImageSource(
      url: source.normalizedUrl,
      cacheKey: role == ImageCacheRole.threadAttachment
          ? ImageCacheKeys.threadAttachment(source.normalizedUrl)
          : ImageCacheKeys.threadInline(source.normalizedUrl),
      ownerType: ImageCacheOwnerType.thread,
      ownerId: tid,
      role: role,
      retentionClass: ImageRetentionClass.ephemeral,
      index: index,
    );
  }
}

final threadReaderImageSourceBuilderProvider =
    Provider<ThreadReaderImageSourceBuilder>((ref) {
      return ThreadReaderImageSourceBuilder(
        imageSourcePipeline: ref.watch(forumImageSourcePipelineProvider),
      );
    });
