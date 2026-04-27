import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/data/forum_repository.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';
import 'package:y300/features/forum/presentation/forum_home_state.dart';

final forumHomeControllerProvider =
    AsyncNotifierProvider.autoDispose<ForumHomeController, ForumHomeViewData>(
      ForumHomeController.new,
    );

/// 论坛首页状态控制器：负责拉取数据和映射为 UI 模型
class ForumHomeController extends AsyncNotifier<ForumHomeViewData> {
  @override
  Future<ForumHomeViewData> build() async {
    return _fetchForumHome();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchForumHome);
  }

  Future<ForumHomeViewData> _fetchForumHome() async {
    final repository = ref.read(forumRepositoryProvider);
    final result = await repository.getForumIndex();

    return result.when(
      success: (data) => ForumHomeViewData(sections: _mapSections(data)),
      failure: (error) => throw ForumHomeException(error.message),
    );
  }

  List<ForumSection> _mapSections(ForumIndexData data) {
    final forumByFid = <String, ForumItem>{
      for (final item in data.forums) item.fid: item,
    };

    final sections = <ForumSection>[];

    // Discuz 的 catlist 中 forums 字段是 fid 列表，这里做一次稳定映射
    for (final category in data.categories) {
      final items = <ForumItem>[];
      for (final fid in category.forums) {
        final mapped = forumByFid[fid];
        if (mapped != null) {
          items.add(mapped);
        }
      }

      if (items.isNotEmpty) {
        sections.add(ForumSection(title: category.name, items: items));
      }
    }

    // 后端若给出未分组 forum，这里归并到“未分类”防止数据丢失
    final categorizedFids = sections
        .expand((section) => section.items)
        .map((item) => item.fid)
        .toSet();

    final uncategorized = data.forums
        .where((forum) => !categorizedFids.contains(forum.fid))
        .toList();

    if (uncategorized.isNotEmpty) {
      sections.add(ForumSection(title: '未分类', items: uncategorized));
    }

    return sections;
  }
}

class ForumHomeException implements Exception {
  ForumHomeException(this.message);

  final String message;

  @override
  String toString() => message;
}
