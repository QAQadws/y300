import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/presentation/controllers/comic_shelf_controller.dart';

class ComicShelfPage extends ConsumerStatefulWidget {
  const ComicShelfPage({super.key});

  @override
  ConsumerState<ComicShelfPage> createState() => _ComicShelfPageState();
}

class _ComicShelfPageState extends ConsumerState<ComicShelfPage> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            onSelected: (value) => _handleMenuAction(context, value),
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'add-category',
                child: Text('新建分类'),
              ),
              PopupMenuItem<String>(
                value: 'rename-category',
                child: Text('重命名当前分类'),
              ),
              PopupMenuItem<String>(
                value: 'delete-category',
                child: Text('删除当前分类'),
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
              _CategoryPagerHeader(
                key: const Key('comic-category-header'),
                pageController: _pageController,
                categories: viewState.categories,
                selectedIndex: viewState.selectedIndex,
                onCategoryTap: (index) {
                  _pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                  );
                },
              ),
              const Divider(height: 1),
              Expanded(
                child: PageView.builder(
                  key: const Key('comic-category-page-view'),
                  controller: _pageController,
                  itemCount: viewState.categories.length,
                  onPageChanged: (index) {
                    final category = viewState.categories[index];
                    ref.read(comicShelfControllerProvider.notifier).selectCategory(category.categoryId);
                  },
                  itemBuilder: (context, index) {
                    final category = viewState.categories[index];
                    final items = viewState.itemsOf(category.categoryId);
                    return _CategoryShelfPage(
                      key: ValueKey<String>('comic-category-page-${category.categoryId}'),
                      category: category,
                      items: items,
                      categories: viewState.categories,
                      gridColumnCount: viewState.gridColumnCount,
                      onMoveToCategory: (comicId, fromCategoryId, toCategoryId) {
                        return ref.read(comicShelfControllerProvider.notifier).moveComicToCategory(
                              comicId: comicId,
                              fromCategoryId: fromCategoryId,
                              toCategoryId: toCategoryId,
                            );
                      },
                      onReplaceCover: (comicId, coverUrl) {
                        return ref.read(comicShelfControllerProvider.notifier).updateCustomCover(
                              comicId: comicId,
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

  Future<void> _handleMenuAction(BuildContext context, String value) async {
    final controller = ref.read(comicShelfControllerProvider.notifier);
    final state = ref.read(comicShelfControllerProvider).value;

    if (value == 'add-category') {
      final name = await _showCategoryNameDialog(context, title: '新建分类');
      if (name != null && name.isNotEmpty) {
        await controller.createCategory(name);
      }
      return;
    }

    if (value == 'rename-category') {
      final category = state?.selectedCategory;
      if (category == null || category.isDefault) {
        _showHint(context, '默认分类不支持重命名');
        return;
      }
      final name = await _showCategoryNameDialog(
        context,
        title: '重命名分类',
        initialValue: category.name,
      );
      if (name != null && name.isNotEmpty) {
        await controller.renameCategory(categoryId: category.categoryId, newName: name);
      }
      return;
    }

    if (value == 'delete-category') {
      final category = state?.selectedCategory;
      if (category == null || category.isDefault) {
        _showHint(context, '默认分类不支持删除');
        return;
      }

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

      if (confirm == true) {
        await controller.deleteCategory(category.categoryId);
      }
      return;
    }

    if (value == 'grid-2' || value == 'grid-3' || value == 'grid-4') {
      await controller.updateGridColumnCount(int.parse(value.split('-').last));
    }
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

  void _showHint(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _CategoryPagerHeader extends StatelessWidget {
  const _CategoryPagerHeader({
    super.key,
    required this.pageController,
    required this.categories,
    required this.selectedIndex,
    required this.onCategoryTap,
  });

  final PageController pageController;
  final List<ComicShelfCategory> categories;
  final int selectedIndex;
  final ValueChanged<int> onCategoryTap;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const SizedBox(height: 56);
    }

    return _FixedSlotCategoryHeader(
      pageController: pageController,
      categories: categories,
      selectedIndex: selectedIndex,
      onCategoryTap: onCategoryTap,
    );
  }
}

/// 固定4槽位分类头：每个分类始终占据 1/4 宽度，超出后横向滚动。
class _FixedSlotCategoryHeader extends StatefulWidget {
  const _FixedSlotCategoryHeader({
    required this.pageController,
    required this.categories,
    required this.selectedIndex,
    required this.onCategoryTap,
  });

  final PageController pageController;
  final List<ComicShelfCategory> categories;
  final int selectedIndex;
  final ValueChanged<int> onCategoryTap;

  @override
  State<_FixedSlotCategoryHeader> createState() => _FixedSlotCategoryHeaderState();
}

class _FixedSlotCategoryHeaderState extends State<_FixedSlotCategoryHeader> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void didUpdateWidget(covariant _FixedSlotCategoryHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSelectedVisible());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slotWidth = constraints.maxWidth / 4;
          final useScrollable = widget.categories.length > 4;

          return Stack(
            children: [
              if (useScrollable)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: _scrollController,
                  child: Row(
                    children: List.generate(
                      widget.categories.length,
                      (index) {
                        final category = widget.categories[index];
                        return SizedBox(
                          width: slotWidth,
                          child: InkWell(
                            key: ValueKey<String>('comic-category-tab-${category.categoryId}'),
                            onTap: () => widget.onCategoryTap(index),
                            child: Center(
                              child: Text(
                                category.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              if (!useScrollable)
                Row(
                  children: List.generate(4, (slotIndex) {
                    final hasCategory = slotIndex < widget.categories.length;
                    if (!hasCategory) {
                      return SizedBox(width: slotWidth);
                    }

                    final category = widget.categories[slotIndex];
                    return SizedBox(
                      width: slotWidth,
                      child: InkWell(
                        key: ValueKey<String>('comic-category-tab-${category.categoryId}'),
                        onTap: () => widget.onCategoryTap(slotIndex),
                        child: Center(
                          child: Text(
                            category.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              AnimatedBuilder(
                animation: Listenable.merge(<Listenable>[
                  widget.pageController,
                  _scrollController,
                ]),
                builder: (context, child) {
                  final page = widget.pageController.hasClients ? (widget.pageController.page ?? 0) : 0;
                  final clampedPage = page.clamp(0, (widget.categories.length - 1).toDouble());
                  final scrollOffset = useScrollable && _scrollController.hasClients ? _scrollController.offset : 0;
                  final left = clampedPage * slotWidth - scrollOffset + slotWidth * 0.2;

                  return Positioned(
                    key: const Key('comic-category-indicator'),
                    left: left,
                    bottom: 6,
                    child: Container(
                      width: slotWidth * 0.6,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _ensureSelectedVisible() {
    if (!_scrollController.hasClients) {
      return;
    }

    // 分类数量不足4个时，固定采用左对齐展示，避免残留滚动偏移导致视觉不对齐。
    if (widget.categories.length <= 4) {
      if (_scrollController.offset != 0) {
        _scrollController.jumpTo(0);
      }
      return;
    }

    final viewportWidth = _scrollController.position.viewportDimension;
    if (viewportWidth <= 0) {
      return;
    }

    final slotWidth = viewportWidth / 4;
    final maxOffset = _scrollController.position.maxScrollExtent;
    final targetStartIndex = (widget.selectedIndex - 1).clamp(0, widget.categories.length - 4);
    final targetOffset = (targetStartIndex * slotWidth).clamp(0.0, maxOffset).toDouble();

    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }
}

class _CategoryShelfPage extends StatelessWidget {
  const _CategoryShelfPage({
    super.key,
    required this.category,
    required this.items,
    required this.categories,
    required this.gridColumnCount,
    required this.onMoveToCategory,
    required this.onReplaceCover,
  });

  final ComicShelfCategory category;
  final List<ComicShelfItem> items;
  final List<ComicShelfCategory> categories;
  final int gridColumnCount;
  final Future<void> Function(String comicId, String fromCategoryId, String toCategoryId) onMoveToCategory;
  final Future<void> Function(String comicId, String? coverUrl) onReplaceCover;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Text('书架还是空的，去帖子详情把喜欢的漫画加入书架吧'),
      );
    }

    return GridView.builder(
      key: ValueKey<String>('comic-shelf-grid-${category.categoryId}'),
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: gridColumnCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2 / 3,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _ComicGridTile(
          item: item,
          categories: categories,
          onMoveToCategory: (toCategoryId) {
            return onMoveToCategory(item.comicId, item.categoryId, toCategoryId);
          },
          onReplaceCover: (coverUrl) {
            return onReplaceCover(item.comicId, coverUrl);
          },
        );
      },
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
