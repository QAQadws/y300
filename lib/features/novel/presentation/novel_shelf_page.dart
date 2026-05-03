import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/presentation/controllers/novel_shelf_controller.dart';
import 'package:y300/features/novel/presentation/novel_detail_page.dart';
import 'package:y300/features/novel/presentation/widgets/novel_shelf_card.dart';

class NovelShelfPage extends ConsumerWidget {
  const NovelShelfPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(novelShelfControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('小说书架'),
        actions: [
          IconButton(
            key: const Key('novel-shelf-add-button'),
            tooltip: '手动添加',
            icon: const Icon(Icons.add),
            onPressed: () => _showAddDialog(context, ref),
          ),
          IconButton(
            key: const Key('novel-shelf-refresh-button'),
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(novelShelfControllerProvider.notifier).refresh(),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('加载小说书架失败：$error', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.read(novelShelfControllerProvider.notifier).refresh(),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (viewState) {
          return Column(
            children: [
              _FidFilters(
                selectedFid: viewState.selectedFid,
                onSelected: (fid) => ref.read(novelShelfControllerProvider.notifier).selectFid(fid),
              ),
              if (viewState.hint != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      viewState.hint!,
                      key: const Key('novel-shelf-hint'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              Expanded(
                child: viewState.items.isEmpty
                    ? const Center(child: Text('暂无小说，点击右上角 + 手动添加 tid'))
                    : GridView.builder(
                        key: const Key('novel-shelf-grid'),
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 2 / 3,
                        ),
                        itemCount: viewState.items.length,
                        itemBuilder: (context, index) {
                          final item = viewState.items[index];
                          return NovelShelfCard(
                            item: item,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => NovelDetailPage(novelId: item.novelId),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final fidController = TextEditingController(text: NovelShelfController.fidLiterature);
    final tidController = TextEditingController();

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('手动添加小说'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('novel-add-fid-input'),
                controller: fidController,
                decoration: const InputDecoration(labelText: 'fid（49/55）'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('novel-add-tid-input'),
                controller: tidController,
                decoration: const InputDecoration(labelText: 'tid'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('添加并刷新'),
            ),
          ],
        );
      },
    );

    if (accepted != true) {
      return;
    }

    final fid = fidController.text.trim();
    final tid = tidController.text.trim();
    if (fid.isEmpty || tid.isEmpty) {
      return;
    }

    await ref.read(novelShelfControllerProvider.notifier).addByTid(fid: fid, tid: tid);
  }
}

class _FidFilters extends StatelessWidget {
  const _FidFilters({
    required this.selectedFid,
    required this.onSelected,
  });

  final String selectedFid;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            key: const Key('novel-filter-all'),
            label: const Text('全部'),
            selected: selectedFid == NovelShelfController.fidAll,
            onSelected: (_) => onSelected(NovelShelfController.fidAll),
          ),
          ChoiceChip(
            key: const Key('novel-filter-49'),
            label: const Text('文学区(49)'),
            selected: selectedFid == NovelShelfController.fidLiterature,
            onSelected: (_) => onSelected(NovelShelfController.fidLiterature),
          ),
          ChoiceChip(
            key: const Key('novel-filter-55'),
            label: const Text('轻小说(55)'),
            selected: selectedFid == NovelShelfController.fidLightNovel,
            onSelected: (_) => onSelected(NovelShelfController.fidLightNovel),
          ),
        ],
      ),
    );
  }
}
