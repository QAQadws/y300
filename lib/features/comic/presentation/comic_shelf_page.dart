import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/presentation/controllers/comic_shelf_controller.dart';

class ComicShelfPage extends ConsumerWidget {
  const ComicShelfPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(comicShelfControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('阶段3暂未接入搜索能力')),
              );
            },
          ),
          PopupMenuButton<String>(
            tooltip: '菜单',
            onSelected: (value) async {
              final controller = ref.read(comicShelfControllerProvider.notifier);
              if (value == 'add-category') {
                final name = await _showCategoryNameDialog(context, title: '新建分类');
                if (name != null && name.isNotEmpty) {
                  await controller.createCategory(name);
                }
                return;
              }

              if (value == 'grid-2' || value == 'grid-3' || value == 'grid-4') {
                await controller.updateGridColumnCount(int.parse(value.split('-').last));
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'add-category',
                child: Text('新建分类'),
              ),
              PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'grid-2',
                child: Text('每行 2 列'),
              ),
              PopupMenuItem<String>(
                value: 'grid-3',
                child: Text('每行 3 列'),
              ),
              PopupMenuItem<String>(
                value: 'grid-4',
                child: Text('每行 4 列'),
              ),
            ],
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
                Text('加载书架失败：$error', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('comic-shelf-retry-button'),
                  onPressed: () => ref.read(comicShelfControllerProvider.notifier).refresh(),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (viewState) {
          return Column(
            children: [
              _CategoryBar(
                categories: viewState.categories,
                selectedCategoryId: viewState.selectedCategoryId,
                onSelected: (id) => ref.read(comicShelfControllerProvider.notifier).selectCategory(id),
                onRename: (category) async {
                  final name = await _showCategoryNameDialog(
                    context,
                    title: '重命名分类',
                    initialValue: category.name,
                  );
                  if (name != null && name.isNotEmpty) {
                    await ref
                        .read(comicShelfControllerProvider.notifier)
                        .renameCategory(categoryId: category.categoryId, newName: name);
                  }
                },
                onDelete: (categoryId) async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('删除分类'),
                      content: const Text('删除后该分类漫画会移动到默认分类，是否继续？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(dialogContext).pop(true),
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true && context.mounted) {
                    await ref.read(comicShelfControllerProvider.notifier).deleteCategory(categoryId);
                  }
                },
              ),
              Expanded(
                child: viewState.items.isEmpty
                    ? const Center(
                        child: Text('书架还是空的，去帖子详情把喜欢的漫画加入书架吧'),
                      )
                    : GridView.builder(
                        key: const Key('comic-shelf-grid'),
                        padding: const EdgeInsets.all(12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: viewState.gridColumnCount,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 2 / 3,
                        ),
                        itemCount: viewState.items.length,
                        itemBuilder: (context, index) {
                          final item = viewState.items[index];
                          return _ComicGridTile(
                            item: item,
                            categories: viewState.categories,
                            onMoveToCategory: (toCategoryId) {
                              return ref.read(comicShelfControllerProvider.notifier).moveComicToCategory(
                                    comicId: item.comicId,
                                    fromCategoryId: item.categoryId,
                                    toCategoryId: toCategoryId,
                                  );
                            },
                            onReplaceCover: (coverUrl) {
                              return ref.read(comicShelfControllerProvider.notifier).updateCustomCover(
                                    comicId: item.comicId,
                                    coverUrl: coverUrl,
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

  Future<String?> _showCategoryNameDialog(
    BuildContext context, {
    required String title,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '请输入分类名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelected,
    required this.onRename,
    required this.onDelete,
  });

  final List<ComicShelfCategory> categories;
  final String selectedCategoryId;
  final ValueChanged<String> onSelected;
  final ValueChanged<ComicShelfCategory> onRename;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        key: const Key('comic-category-bar'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final category = categories[index];
          return InputChip(
            selected: category.categoryId == selectedCategoryId,
            label: Text(category.name),
            onPressed: () => onSelected(category.categoryId),
            onDeleted: category.isDefault ? null : () => onDelete(category.categoryId),
            deleteIcon: category.isDefault ? null : const Icon(Icons.delete_outline),
            avatar: category.isDefault
                ? null
                : PopupMenuButton<String>(
                    tooltip: '分类操作',
                    onSelected: (value) {
                      if (value == 'rename') {
                        onRename(category);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem<String>(
                        value: 'rename',
                        child: Text('重命名'),
                      ),
                    ],
                    child: const Icon(Icons.more_horiz, size: 18),
                  ),
          );
        },
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemCount: categories.length,
      ),
    );
  }
}

class _ComicGridTile extends StatelessWidget {
  const _ComicGridTile({
    required this.item,
    required this.categories,
    required this.onMoveToCategory,
    required this.onReplaceCover,
  });

  final ComicShelfItem item;
  final List<ComicShelfCategory> categories;
  final Future<void> Function(String toCategoryId) onMoveToCategory;
  final Future<void> Function(String? coverUrl) onReplaceCover;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () async {
        await showModalBottomSheet<void>(
          context: context,
          builder: (sheetContext) {
            return SafeArea(
              child: Wrap(
                children: [
                  ListTile(
                    title: const Text('替换封面 URL'),
                    subtitle: const Text('输入可访问的图片链接'),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      final controller = TextEditingController(text: item.coverImageUrl ?? '');
                      final cover = await showDialog<String>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('替换封面'),
                          content: TextField(
                            controller: controller,
                            decoration: const InputDecoration(hintText: 'https://example.com/cover.jpg'),
                            keyboardType: TextInputType.url,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(dialogContext).pop(),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(dialogContext).pop(''),
                              child: const Text('恢复默认'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
                              child: const Text('保存'),
                            ),
                          ],
                        ),
                      );

                      if (cover != null) {
                        await onReplaceCover(cover.isEmpty ? null : cover);
                      }
                    },
                  ),
                  ExpansionTile(
                    title: const Text('移动到分类'),
                    children: categories
                        .where((category) => category.categoryId != item.categoryId)
                        .map(
                          (category) => ListTile(
                            title: Text(category.name),
                            onTap: () async {
                              Navigator.of(sheetContext).pop();
                              await onMoveToCategory(category.categoryId);
                            },
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ),
            );
          },
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: item.coverImageUrl == null
                  ? const Icon(Icons.image_not_supported_outlined)
                  : Image.network(
                      item.coverImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.broken_image_outlined);
                      },
                    ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00000000),
                      Color(0xA6000000),
                      Color(0xCC000000),
                    ],
                  ),
                ),
                child: _TwoLineEllipsisText(
                  item.title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TwoLineEllipsisText extends StatelessWidget {
  const _TwoLineEllipsisText(
    this.text, {
    this.style,
  });

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final defaultStyle = DefaultTextStyle.of(context).style;
        final effectiveStyle = style ?? defaultStyle;

        final painter = TextPainter(
          text: TextSpan(text: text, style: effectiveStyle),
          textDirection: Directionality.of(context),
          maxLines: 2,
          ellipsis: '···',
        )..layout(maxWidth: constraints.maxWidth);

        final displayText = painter.didExceedMaxLines
            ? _truncateToTwoLines(
                source: text,
                maxWidth: constraints.maxWidth,
                style: effectiveStyle,
                textDirection: Directionality.of(context),
              )
            : text;

        return Text(
          displayText,
          maxLines: 2,
          overflow: TextOverflow.clip,
          style: effectiveStyle,
        );
      },
    );
  }

  String _truncateToTwoLines({
    required String source,
    required double maxWidth,
    required TextStyle style,
    required TextDirection textDirection,
  }) {
    if (source.isEmpty) {
      return source;
    }

    var low = 0;
    var high = source.length;
    var best = '';

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final candidate = '${source.substring(0, mid)}···';
      final painter = TextPainter(
        text: TextSpan(text: candidate, style: style),
        textDirection: textDirection,
        maxLines: 2,
      )..layout(maxWidth: maxWidth);

      if (painter.didExceedMaxLines) {
        high = mid - 1;
      } else {
        best = candidate;
        low = mid + 1;
      }
    }

    return best.isEmpty ? '···' : best;
  }
}

