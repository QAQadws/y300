import 'package:flutter/material.dart';
import 'package:y300/shared/widgets/shelf/shelf_theme_palette.dart';

/// 通用固定槽位分页头。
///
/// 约定：
/// 1. 头部始终按 4 槽位计算单项宽度，超过 4 项自动横向滚动。
/// 2. 指示器由 PageController 驱动，随页面滑动连续移动。
/// 3. 通过 [tabKeyBuilder]/[indicatorKey] 交给业务侧定制 key，保持测试稳定。
class FixedSlotPagerHeader extends StatefulWidget {
  const FixedSlotPagerHeader({
    super.key,
    required this.pageController,
    required this.tabs,
    required this.selectedIndex,
    required this.onTap,
    required this.indicatorKey,
    required this.tabKeyBuilder,
  });

  final PageController pageController;
  final List<FixedSlotHeaderTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final Key indicatorKey;
  final Key Function(String id) tabKeyBuilder;

  @override
  State<FixedSlotPagerHeader> createState() => _FixedSlotPagerHeaderState();
}

class _FixedSlotPagerHeaderState extends State<FixedSlotPagerHeader> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void didUpdateWidget(covariant FixedSlotPagerHeader oldWidget) {
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
    final theme = Theme.of(context);
    final palette = const ShelfThemePaletteResolver().resolve(theme);
    if (widget.tabs.isEmpty) {
      return Material(
        color: palette.categoryBarBackground,
        child: const SizedBox(height: 56),
      );
    }

    return Material(
      // Header 会覆盖在可滚动书架内容上方，组件自身提供不透明背景，
      // 避免列表模式滚动时下方 item 透出。
      color: palette.categoryBarBackground,
      child: SizedBox(
        height: 56,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slotWidth = constraints.maxWidth / 4;
            final useScrollable = widget.tabs.length > 4;

            return Stack(
              children: [
                if (useScrollable)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: _scrollController,
                    child: Row(
                      children: List.generate(widget.tabs.length, (index) {
                        final tab = widget.tabs[index];
                        final selected = index == widget.selectedIndex;
                        return SizedBox(
                          width: slotWidth,
                          child: InkWell(
                            key: widget.tabKeyBuilder(tab.id),
                            onTap: () => widget.onTap(index),
                            child: Center(
                              child: Text(
                                tab.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                      color: selected
                                          ? palette.categorySelectedBackground
                                          : theme.colorScheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                if (!useScrollable)
                  Row(
                    children: List.generate(4, (slotIndex) {
                      final hasTab = slotIndex < widget.tabs.length;
                      if (!hasTab) {
                        return SizedBox(width: slotWidth);
                      }
                      final tab = widget.tabs[slotIndex];
                      final selected = slotIndex == widget.selectedIndex;
                      return SizedBox(
                        width: slotWidth,
                        child: InkWell(
                          key: widget.tabKeyBuilder(tab.id),
                          onTap: () => widget.onTap(slotIndex),
                          child: Center(
                            child: Text(
                              tab.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                    color: selected
                                        ? palette.categorySelectedBackground
                                        : theme.colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                AnimatedBuilder(
                  animation: Listenable.merge(<Listenable>[widget.pageController, _scrollController]),
                  builder: (context, child) {
                    final page = widget.pageController.hasClients ? (widget.pageController.page ?? 0) : 0;
                    final clampedPage = page.clamp(0, (widget.tabs.length - 1).toDouble());
                    final scrollOffset = useScrollable && _scrollController.hasClients ? _scrollController.offset : 0;
                    final left = clampedPage * slotWidth - scrollOffset + slotWidth * 0.2;

                    return Positioned(
                      key: widget.indicatorKey,
                      left: left,
                      bottom: 6,
                      child: Container(
                        width: slotWidth * 0.6,
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.categorySelectedBackground,
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
      ),
    );
  }

  void _ensureSelectedVisible() {
    if (!_scrollController.hasClients) {
      return;
    }

    if (widget.tabs.length <= 4) {
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
    final targetStartIndex = (widget.selectedIndex - 1).clamp(0, widget.tabs.length - 4);
    final targetOffset = (targetStartIndex * slotWidth).clamp(0.0, maxOffset).toDouble();

    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }
}

class FixedSlotHeaderTab {
  const FixedSlotHeaderTab({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}
