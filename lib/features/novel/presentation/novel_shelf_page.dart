import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/controllers/novel_shelf_controller.dart';
import 'package:y300/features/novel/presentation/novel_detail_page.dart';
import 'package:y300/features/novel/presentation/widgets/novel_shelf_card.dart';
import 'package:y300/shared/widgets/shelf/fixed_slot_pager_header.dart';
import 'package:y300/shared/widgets/shelf/shelf_app_bar.dart';
import 'package:y300/shared/widgets/shelf/shelf_pager_strategy.dart';

class NovelShelfPage extends ConsumerStatefulWidget {
  const NovelShelfPage({super.key});

  @override
  ConsumerState<NovelShelfPage> createState() => _NovelShelfPageState();
}

class _NovelShelfPageState extends ConsumerState<NovelShelfPage> {
  static const ShelfPagerStrategy<NovelShelfCategory> _pagerStrategy = ShelfPagerStrategy<NovelShelfCategory>(
    idOf: _categoryIdOf,
    labelOf: _categoryLabelOf,
  );

  static String _categoryIdOf(NovelShelfCategory category) => category.categoryId;
  static String _categoryLabelOf(NovelShelfCategory category) => category.name;

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
    final state = ref.watch(novelShelfControllerProvider);

    return Scaffold(
      appBar: ShelfAppBar(
        title: '小说书架',
        onSearchTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请在论坛帖子中点击“加入小说书架”')), 
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
            value: 'refresh',
            child: Text('刷新'),
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
          final headerTabs = _pagerStrategy.buildTabs(viewState.categories);
          final selectedIndex = _pagerStrategy.resolveSelectedIndex(
            tabs: headerTabs,
            selectedId: viewState.selectedCategoryId,
          );

          return Column(
            children: [
              FixedSlotPagerHeader(
                key: const Key('novel-category-header'),
                pageController: _pageController,
                tabs: headerTabs,
                selectedIndex: selectedIndex,
                onTap: (index) {
                  _pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                  );
                },
                indicatorKey: const Key('novel-category-indicator'),
                tabKeyBuilder: (id) => ValueKey<String>('novel-category-tab-$id'),
              ),
              const Divider(height: 1),
              if (viewState.hint != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
                child: PageView.builder(
                  key: const Key('novel-category-page-view'),
                  controller: _pageController,
                  itemCount: viewState.categories.length,
                  onPageChanged: (index) {
                    final category = viewState.categories[index];
                    ref.read(novelShelfControllerProvider.notifier).selectCategory(category.categoryId);
                  },
                  itemBuilder: (context, index) {
                    final category = viewState.categories[index];
                    final visibleItems = viewState.itemsOf(category.categoryId);

                    if (visibleItems.isEmpty) {
                      return const Center(child: Text('书架还是空的，去论坛帖子把喜欢的小说加入书架吧'));
                    }

                    return GridView.builder(
                      key: ValueKey<String>('novel-shelf-grid-${category.categoryId}'),
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 2 / 3,
                      ),
                      itemCount: visibleItems.length,
                      itemBuilder: (context, itemIndex) {
                        final item = visibleItems[itemIndex];
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
    final controller = ref.read(novelShelfControllerProvider.notifier);
    final state = ref.read(novelShelfControllerProvider).value;

    if (value == 'refresh') {
      await controller.refresh();
      return;
    }

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
          content: const Text('删除后该分类小说会移动到默认分类，是否继续？'),
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
