import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/presentation/adapters/comic_detail_adapter.dart';
import 'package:y300/features/comic/presentation/comic_reader_page.dart';
import 'package:y300/features/library_shared/data/library_state_providers.dart';
import 'package:y300/features/library_shared/presentation/pages/unified_detail_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

/// 漫画详情页（Phase 4）：统一详情页薄壳接入。
class ComicDetailPage extends ConsumerWidget {
  const ComicDetailPage({
    super.key,
    required this.comicId,
  });

  final String comicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adapter = ComicDetailAdapter(
      ref.watch(comicRepositoryProvider),
      stateRepository: ref.watch(libraryStateRepositoryProvider),
    );
    return UnifiedDetailPage(
      adapter: adapter,
      workId: comicId,
      onOpenReader: (context, target) async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ComicReaderPage(
              comicId: target.workId,
              episodeId: target.episodeId,
            ),
          ),
        );
      },
      onOpenThread: (context, target) async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ThreadDetailPage(
              tid: target.tid,
              subject: target.subject ?? '',
            ),
          ),
        );
      },
    );
  }
}
