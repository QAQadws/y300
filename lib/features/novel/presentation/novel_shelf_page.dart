import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/library_shared/data/library_state_providers.dart';
import 'package:y300/features/library_shared/presentation/pages/unified_shelf_page.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/novel/presentation/adapters/novel_shelf_adapter.dart';
import 'package:y300/features/novel/presentation/novel_detail_page.dart';

/// 小说书架页（Phase 3）。
///
/// 仅保留模块级依赖注入，通用书架交互完全复用统一页面。
class NovelShelfPage extends ConsumerWidget {
  const NovelShelfPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adapter = NovelShelfAdapter(
      ref.watch(novelRepositoryProvider),
      stateRepository: ref.watch(libraryStateRepositoryProvider),
    );
    return UnifiedShelfPage(
      adapter: adapter,
      imageHeaderBuilder: ref.watch(imageRequestHeaderBuilderProvider),
      onOpenWork: (context, workId) async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => NovelDetailPage(novelId: workId),
          ),
        );
      },
    );
  }
}
