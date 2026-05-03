import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/presentation/comic_detail_page.dart';
import 'package:y300/features/comic/presentation/controllers/comic_shelf_controller.dart';
import 'package:y300/shared/widgets/shelf/shelf_app_bar.dart';
import 'package:y300/shared/widgets/shelf/fixed_slot_pager_header.dart';
import 'package:y300/shared/widgets/shelf/shelf_pager_strategy.dart';
import 'package:y300/shared/widgets/shelf/shelf_cover_card.dart';

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
      appBar: ShelfAppBar(
        title: '书架',
        onSearchTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('阶段3暂未接入搜索能力')),
          );
        },
        onMenuSelected: (value) => _handleMenuAction(context, value),
        menuItems: const [
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
  static const ShelfPagerStrategy<ComicShelfCategory> _pagerStrategy = ShelfPagerStrategy<ComicShelfCategory>(
    idOf: _categoryIdOf,
    labelOf: _categoryLabelOf,
  );

  static String _categoryIdOf(ComicShelfCategory category) => category.categoryId;
  static String _categoryLabelOf(ComicShelfCategory category) => category.name;

  final PageController pageController;
  final List<ComicShelfCategory> categories;
  final int selectedIndex;
  final ValueChanged<int> onCategoryTap;
  @override
  Widget build(BuildContext context) {
    final tabs = _pagerStrategy.buildTabs(categories);
    return FixedSlotPagerHeader(
      pageController: pageController,
      tabs: tabs,
      selectedIndex: selectedIndex,
      onTap: onCategoryTap,
      indicatorKey: const Key('comic-category-indicator'),
      tabKeyBuilder: (id) => ValueKey<String>('comic-category-tab-$id'),
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
    return ShelfCoverCard(
      title: item.title,
      coverImageUrl: item.coverImageUrl,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ComicDetailPage(comicId: item.comicId),
          ),
        );
      },
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
      placeholderIcon: Icons.image_not_supported_outlined,
      showTwoLineCustomEllipsis: true,
    );
  }
}

