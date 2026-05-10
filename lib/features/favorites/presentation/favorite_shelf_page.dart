import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/comic/presentation/comic_detail_page.dart';
import 'package:y300/features/favorites/data/favorite_providers.dart';
import 'package:y300/features/favorites/domain/favorite_cache_models.dart';
import 'package:y300/features/library_shared/presentation/pages/unified_shelf_page.dart';
import 'package:y300/features/novel/presentation/novel_detail_page.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

class FavoriteShelfPage extends ConsumerWidget {
  const FavoriteShelfPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adapter = ref.watch(favoriteShelfAdapterProvider);
    final repository = ref.watch(localFavoriteRepositoryProvider);
    return UnifiedShelfPage(
      adapter: adapter,
      imageHeaderBuilder: ref.watch(imageRequestHeaderBuilderProvider),
      onOpenWork: (context, workId) async {
        final target = await repository.getRouteTargetByShelfWorkId(workId);
        if (!context.mounted || target == null) {
          return;
        }

        switch (target.contentKind) {
          case ThreadContentKind.comic:
            final comicId = target.workId;
            if (comicId == null || comicId.trim().isEmpty) {
              await _openThread(context, target);
              return;
            }
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ComicDetailPage(comicId: comicId),
              ),
            );
            break;
          case ThreadContentKind.novel:
            final novelId = target.workId;
            if (novelId == null || novelId.trim().isEmpty) {
              await _openThread(context, target);
              return;
            }
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NovelDetailPage(novelId: novelId),
              ),
            );
            break;
          case ThreadContentKind.unknown:
          case ThreadContentKind.forum:
            await _openThread(context, target);
            break;
        }
      },
    );
  }

  Future<void> _openThread(
    BuildContext context,
    FavoriteRouteTarget target,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadDetailPage(
          tid: target.tid,
          subject: target.title,
        ),
      ),
    );
  }
}
