import 'package:flutter/material.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';
import 'package:y300/features/forum/presentation/forum_display_state.dart';
import 'package:y300/features/forum/presentation/widgets/forum_display_theme.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';
import 'package:y300/shared/widgets/forum_native_surface.dart';

class ForumDisplayContent extends StatefulWidget {
  const ForumDisplayContent({
    super.key,
    required this.state,
    required this.scrollController,
    required this.filterAnchorKey,
    required this.headImageKey,
    required this.onLoadMore,
    required this.onLoadPrevious,
    required this.onSelectPage,
    required this.onOpenFilter,
    required this.onOpenThreadTag,
    required this.onOpenThread,
    required this.onCopyThreadLink,
    required this.onOpenTopEntry,
    required this.onOpenSubForum,
  });

  final ForumDisplayPageState state;
  final ScrollController scrollController;
  final GlobalKey filterAnchorKey;
  final GlobalKey headImageKey;
  final VoidCallback onLoadMore;
  final VoidCallback onLoadPrevious;
  final ValueChanged<int> onSelectPage;
  final ValueChanged<ForumDisplayFilterItem> onOpenFilter;
  final ValueChanged<ForumThreadSummary> onOpenThreadTag;
  final ValueChanged<ForumThreadSummary> onOpenThread;
  final ValueChanged<ForumThreadSummary> onCopyThreadLink;
  final ValueChanged<ForumDisplayTopEntry> onOpenTopEntry;
  final ValueChanged<ForumDisplaySubForum> onOpenSubForum;

  @override
  State<ForumDisplayContent> createState() => _ForumDisplayContentState();
}

class _ForumDisplayContentState extends State<ForumDisplayContent> {
  bool _topEntriesExpanded = false;

  @override
  void didUpdateWidget(covariant ForumDisplayContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_topEntrySignature(oldWidget.state.topEntries) !=
        _topEntrySignature(widget.state.topEntries)) {
      _topEntriesExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ForumDisplayThemePalette.resolve(Theme.of(context));
    final state = widget.state;
    return ColoredBox(
      color: palette.background,
      child: CustomScrollView(
        key: const Key('forum-display-list'),
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (state.headImageUrl?.trim().isNotEmpty == true)
            SliverToBoxAdapter(
              child: _ForumHeadImage(
                key: widget.headImageKey,
                url: state.headImageUrl!.trim(),
                label: state.title,
                palette: palette,
              ),
            ),
          if (state.primaryFilters.isNotEmpty || state.typeFilters.isNotEmpty)
            SliverPersistentHeader(
              pinned: true,
              delegate: _ForumDisplayFilterHeaderDelegate(
                anchorKey: widget.filterAnchorKey,
                primaryItems: state.primaryFilters,
                typeItems: state.typeFilters,
                onSelected: widget.onOpenFilter,
                palette: palette,
              ),
            ),
          if (state.subForums.isNotEmpty)
            SliverToBoxAdapter(
              child: _SubForumList(
                subForums: state.subForums,
                onOpenSubForum: widget.onOpenSubForum,
                palette: palette,
              ),
            ),
          if (state.topEntries.isNotEmpty)
            SliverToBoxAdapter(
              child: _TopEntrySection(
                entries: state.topEntries,
                isExpanded: _topEntriesExpanded,
                onToggle: () {
                  setState(() => _topEntriesExpanded = !_topEntriesExpanded);
                },
                onOpenEntry: widget.onOpenTopEntry,
                palette: palette,
              ),
            ),
          if (state.threads.isEmpty)
            SliverToBoxAdapter(child: _EmptyThreadList(palette: palette))
          else
            SliverToBoxAdapter(
              child: _ThreadListSection(
                signature: _threadListSignature(state),
                threads: state.threads,
                onOpenThread: widget.onOpenThread,
                onOpenThreadTag: widget.onOpenThreadTag,
                onCopyThreadLink: widget.onCopyThreadLink,
                palette: palette,
              ),
            ),
          SliverToBoxAdapter(
            child: _LoadMoreSection(
              currentPage: state.currentPage,
              lastPage: state.lastPage,
              canLoadPrevious: state.currentPage > 1,
              hasMore: state.hasMore,
              isLoadingMore: state.isLoadingMore,
              onLoadPrevious: widget.onLoadPrevious,
              onLoadMore: widget.onLoadMore,
              onSelectPage: widget.onSelectPage,
              palette: palette,
            ),
          ),
        ],
      ),
    );
  }

  String _topEntrySignature(List<ForumDisplayTopEntry> entries) {
    return entries.map((entry) => '${entry.tid}:${entry.url}').join('|');
  }

  String _threadListSignature(ForumDisplayPageState state) {
    final threads = state.threads;
    if (threads.isEmpty) {
      return '${state.currentPage}:empty';
    }
    return [
      state.currentPage,
      threads.length,
      threads.first.tid,
      threads.last.tid,
    ].join(':');
  }
}

class _ForumDisplayFilterHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ForumDisplayFilterHeaderDelegate({
    required this.anchorKey,
    required this.primaryItems,
    required this.typeItems,
    required this.onSelected,
    required this.palette,
  });

  final GlobalKey anchorKey;
  final List<ForumDisplayFilterItem> primaryItems;
  final List<ForumDisplayFilterItem> typeItems;
  final ValueChanged<ForumDisplayFilterItem> onSelected;
  final ForumDisplayThemePalette palette;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  double get _height => 44;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return _ForumDisplayFilterBand(
      anchorKey: anchorKey,
      primaryItems: primaryItems,
      typeItems: typeItems,
      onSelected: onSelected,
      palette: palette,
      overlapsContent: overlapsContent,
    );
  }

  @override
  bool shouldRebuild(covariant _ForumDisplayFilterHeaderDelegate oldDelegate) {
    return primaryItems != oldDelegate.primaryItems ||
        anchorKey != oldDelegate.anchorKey ||
        typeItems != oldDelegate.typeItems ||
        onSelected != oldDelegate.onSelected ||
        palette != oldDelegate.palette;
  }
}

class _ForumDisplayFilterBand extends StatelessWidget {
  const _ForumDisplayFilterBand({
    required this.anchorKey,
    required this.primaryItems,
    required this.typeItems,
    required this.onSelected,
    required this.palette,
    required this.overlapsContent,
  });

  final GlobalKey anchorKey;
  final List<ForumDisplayFilterItem> primaryItems;
  final List<ForumDisplayFilterItem> typeItems;
  final ValueChanged<ForumDisplayFilterItem> onSelected;
  final ForumDisplayThemePalette palette;
  final bool overlapsContent;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: anchorKey,
      child: ColoredBox(
        key: const Key('forum-display-filter-header'),
        color: palette.background,
        child: SizedBox(
          height: 44,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: palette.outlineSoft.withValues(alpha: 0.72),
                ),
              ),
              boxShadow: overlapsContent
                  ? [
                      BoxShadow(
                        color: palette.stateLayer.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    Expanded(
                      child: _FilterStrip(
                        items: primaryItems,
                        onSelected: onSelected,
                        palette: palette,
                      ),
                    ),
                    if (typeItems.isNotEmpty)
                      _TypeFilterMenu(
                        items: typeItems,
                        onSelected: onSelected,
                        palette: palette,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ForumDisplayGroup extends StatelessWidget {
  const _ForumDisplayGroup({
    required this.palette,
    required this.child,
    this.keyOverride,
    this.shadowAlpha = 0.12,
    this.shadowBlurRadius = 12,
    this.shadowOffset = const Offset(0, 4),
  });

  final ForumDisplayThemePalette palette;
  final Widget child;
  final Key? keyOverride;
  final double shadowAlpha;
  final double shadowBlurRadius;
  final Offset shadowOffset;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    final content = DecoratedBox(
      key: keyOverride,
      decoration: BoxDecoration(
        color: palette.surfaceContainer,
        borderRadius: radius,
        border: Border.all(color: palette.outlineSoft),
        boxShadow: [
          BoxShadow(
            color: palette.stateLayer.withValues(alpha: shadowAlpha),
            blurRadius: shadowBlurRadius,
            offset: shadowOffset,
          ),
        ],
      ),
      child: ClipRRect(borderRadius: radius, child: child),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: content,
    );
  }
}

class _SoftDivider extends StatelessWidget {
  const _SoftDivider({required this.palette});

  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 12,
      endIndent: 12,
      color: palette.outlineSoft,
    );
  }
}

class _SeparatedColumn extends StatelessWidget {
  const _SeparatedColumn({
    required this.children,
    required this.palette,
    this.gap = 0,
    this.showDividers = true,
  });

  final List<Widget> children;
  final ForumDisplayThemePalette palette;
  final double gap;
  final bool showDividers;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0 && showDividers) _SoftDivider(palette: palette),
          if (index > 0 && gap > 0) SizedBox(height: gap),
          children[index],
        ],
      ],
    );
  }
}

class ForumDisplayInitialLoading extends StatelessWidget {
  const ForumDisplayInitialLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = ForumDisplayThemePalette.resolve(Theme.of(context));
    return ColoredBox(
      color: palette.background,
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class ForumDisplayErrorView extends StatelessWidget {
  const ForumDisplayErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = ForumDisplayThemePalette.resolve(Theme.of(context));
    return ColoredBox(
      color: palette.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.title),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('forum-display-retry-button'),
                onPressed: onRetry,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForumHeadImage extends StatelessWidget {
  const _ForumHeadImage({
    super.key,
    required this.url,
    required this.label,
    required this.palette,
  });

  final String url;
  final String label;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('forum-display-head-image'),
      color: palette.panel,
      child: Image.network(
        url,
        width: double.infinity,
        fit: BoxFit.fitWidth,
        semanticLabel: label.isEmpty ? '版块顶部图' : '$label 版块顶部图',
        errorBuilder: (context, error, stackTrace) {
          return SizedBox(
            height: 72,
            child: ColoredBox(
              color: palette.disabled,
              child: Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: palette.softText,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({
    required this.items,
    required this.onSelected,
    required this.palette,
  });

  final List<ForumDisplayFilterItem> items;
  final ValueChanged<ForumDisplayFilterItem> onSelected;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          return _FilterChipButton(
            key: Key('forum-display-filter-${item.label}'),
            item: item,
            palette: palette,
            onSelected: onSelected,
          );
        },
      ),
    );
  }
}

class _TypeFilterMenu extends StatefulWidget {
  const _TypeFilterMenu({
    required this.items,
    required this.onSelected,
    required this.palette,
  });

  final List<ForumDisplayFilterItem> items;
  final ValueChanged<ForumDisplayFilterItem> onSelected;
  final ForumDisplayThemePalette palette;

  @override
  State<_TypeFilterMenu> createState() => _TypeFilterMenuState();
}

class _TypeFilterMenuState extends State<_TypeFilterMenu> {
  final LayerLink _layerLink = LayerLink();
  bool _isMenuOpen = false;
  OverlayEntry? _overlayEntry;

  void _setMenuOpen(bool value) {
    if (_isMenuOpen == value) {
      return;
    }
    setState(() => _isMenuOpen = value);
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _toggleMenu() {
    if (_overlayEntry != null) {
      _removeOverlay();
      return;
    }
    _showOverlay();
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return;
    }
    _setMenuOpen(true);
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return _TypeFilterMenuOverlay(
          layerLink: _layerLink,
          anchorSize: renderBox.size,
          items: widget.items,
          selectedItem: _selectedFilterItem(widget.items),
          palette: widget.palette,
          onDismiss: _removeOverlay,
          onSelected: (item) {
            _removeOverlay();
            widget.onSelected(item);
          },
        );
      },
    );
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) {
      _setMenuOpen(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        width: 40,
        height: 44,
        child: Material(
          key: const Key('forum-display-type-filter-menu'),
          color: Colors.transparent,
          child: InkWell(
            onTap: _toggleMenu,
            customBorder: const CircleBorder(),
            child: Center(
              child: _RotatingArrowIcon(
                isExpanded: _isMenuOpen,
                color: widget.palette.softText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeFilterMenuOverlay extends StatelessWidget {
  const _TypeFilterMenuOverlay({
    required this.layerLink,
    required this.anchorSize,
    required this.items,
    required this.selectedItem,
    required this.palette,
    required this.onDismiss,
    required this.onSelected,
  });

  static const double _width = 112;
  static const double _maxHeight = 320;
  static const double _itemHeight = 44;

  final LayerLink layerLink;
  final Size anchorSize;
  final List<ForumDisplayFilterItem> items;
  final ForumDisplayFilterItem? selectedItem;
  final ForumDisplayThemePalette palette;
  final VoidCallback onDismiss;
  final ValueChanged<ForumDisplayFilterItem> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final menuHeight = (items.length * _itemHeight).clamp(0, _maxHeight);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 4),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.scale(
                  alignment: Alignment.topRight,
                  scaleY: value,
                  child: child,
                ),
              );
            },
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: _width,
                  maxWidth: _width,
                  maxHeight: _maxHeight,
                ),
                child: DecoratedBox(
                  key: const Key('forum-display-type-filter-panel'),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: palette.stateLayer.withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: _width,
                      height: menuHeight.toDouble(),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemExtent: _itemHeight,
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final isSelected = item == selectedItem;
                          return InkWell(
                            key: Key('forum-display-type-filter-${item.label}'),
                            onTap: isSelected ? null : () => onSelected(item),
                            child: Center(
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: isSelected
                                      ? palette.selectedForeground
                                      : palette.title,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RotatingArrowIcon extends StatelessWidget {
  const _RotatingArrowIcon({required this.isExpanded, required this.color});

  final bool isExpanded;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: isExpanded ? 0.5 : 0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, turns, child) {
        return RotationTransition(
          turns: AlwaysStoppedAnimation<double>(turns),
          child: child,
        );
      },
      child: Icon(Icons.keyboard_arrow_down, color: color, size: 20),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    super.key,
    required this.item,
    required this.palette,
    required this.onSelected,
  });

  final ForumDisplayFilterItem item;
  final ForumDisplayThemePalette palette;
  final ValueChanged<ForumDisplayFilterItem> onSelected;

  @override
  Widget build(BuildContext context) {
    final isSelected = item.isSelected;
    final radius = BorderRadius.circular(12);
    final indicatorColor = isSelected
        ? palette.selectedForeground
        : Colors.transparent;
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        overlayColor: WidgetStatePropertyAll<Color>(palette.stateLayer),
        onTap: isSelected ? null : () => onSelected(item),
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: isSelected
                          ? palette.selectedForeground
                          : palette.softText,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w400,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    width: isSelected ? 18 : 0,
                    height: 3,
                    decoration: BoxDecoration(
                      color: indicatorColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

ForumDisplayFilterItem? _selectedFilterItem(
  List<ForumDisplayFilterItem> items,
) {
  for (final item in items) {
    if (item.isSelected) {
      return item;
    }
  }
  return null;
}

class _SubForumList extends StatefulWidget {
  const _SubForumList({
    required this.subForums,
    required this.onOpenSubForum,
    required this.palette,
  });

  final List<ForumDisplaySubForum> subForums;
  final ValueChanged<ForumDisplaySubForum> onOpenSubForum;
  final ForumDisplayThemePalette palette;

  @override
  State<_SubForumList> createState() => _SubForumListState();
}

class _SubForumListState extends State<_SubForumList> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return _ForumDisplayGroup(
      palette: widget.palette,
      keyOverride: const Key('forum-display-sub-forums'),
      shadowAlpha: 0.05,
      shadowBlurRadius: 7,
      shadowOffset: const Offset(0, 2),
      child: DecoratedBox(
        decoration: BoxDecoration(color: widget.palette.surfaceContainerLow),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                key: const Key('forum-display-sub-forums-toggle'),
                onTap: () => setState(() => _isExpanded = !_isExpanded),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Row(
                    children: [
                      _RotatingArrowIcon(
                        isExpanded: _isExpanded,
                        color: widget.palette.accent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '子版块',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: widget.palette.title,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_isExpanded) _SoftDivider(palette: widget.palette),
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SizeTransition(
                        sizeFactor: animation,
                        alignment: const Alignment(-1, -1),
                        child: child,
                      ),
                    );
                  },
                  child: _isExpanded
                      ? Column(
                          key: const ValueKey('forum-sub-forums-expanded'),
                          children: [
                            for (final subForum in widget.subForums)
                              _SubForumTile(
                                key: Key(
                                  'forum-display-sub-forum-${subForum.fid}',
                                ),
                                subForum: subForum,
                                onTap: () => widget.onOpenSubForum(subForum),
                                palette: widget.palette,
                              ),
                          ],
                        )
                      : const SizedBox(
                          key: ValueKey('forum-sub-forums-collapsed'),
                          width: double.infinity,
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

class _SubForumTile extends StatelessWidget {
  const _SubForumTile({
    super.key,
    required this.subForum,
    required this.onTap,
    required this.palette,
  });

  final ForumDisplaySubForum subForum;
  final VoidCallback onTap;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                subForum.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: palette.title,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: palette.softText, size: 18),
          ],
        ),
      ),
    );
  }
}

class _TopEntrySection extends StatelessWidget {
  const _TopEntrySection({
    required this.entries,
    required this.isExpanded,
    required this.onToggle,
    required this.onOpenEntry,
    required this.palette,
  });

  final List<ForumDisplayTopEntry> entries;
  final bool isExpanded;
  final VoidCallback onToggle;
  final ValueChanged<ForumDisplayTopEntry> onOpenEntry;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return _ForumDisplayGroup(
      palette: palette,
      keyOverride: const Key('forum-display-top-entries'),
      shadowAlpha: 0.05,
      shadowBlurRadius: 7,
      shadowOffset: const Offset(0, 2),
      child: DecoratedBox(
        decoration: BoxDecoration(color: palette.surfaceContainerLow),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                key: const Key('forum-display-top-entries-toggle'),
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Row(
                    children: [
                      _RotatingArrowIcon(
                        isExpanded: isExpanded,
                        color: palette.accent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '公告 / 置顶',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: palette.title,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (isExpanded) _SoftDivider(palette: palette),
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SizeTransition(
                        sizeFactor: animation,
                        alignment: const Alignment(-1, -1),
                        child: child,
                      ),
                    );
                  },
                  child: isExpanded
                      ? Column(
                          key: const ValueKey('forum-top-expanded'),
                          children: [
                            for (final entry in entries)
                              _TopEntryTile(
                                key: ValueKey(
                                  'forum-top-${entry.tid}-${entry.title}',
                                ),
                                entry: entry,
                                onTap: () => onOpenEntry(entry),
                                palette: palette,
                              ),
                          ],
                        )
                      : const SizedBox(
                          key: ValueKey('forum-top-collapsed'),
                          width: double.infinity,
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

class _TopEntryTile extends StatelessWidget {
  const _TopEntryTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.palette,
  });

  final ForumDisplayTopEntry entry;
  final VoidCallback onTap;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final color =
        _parseColor(entry.titleColorHex) ??
        (entry.isAnnouncement ? palette.warning : palette.accent);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: entry.tid.trim().isEmpty ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 5, 10, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SmallBadge(
                label: entry.badgeLabel.isNotEmpty
                    ? entry.badgeLabel
                    : (entry.isAnnouncement ? '公告' : '置顶'),
                accentColor: entry.isAnnouncement
                    ? palette.warning
                    : palette.accent,
                palette: palette,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreadAppear extends StatelessWidget {
  const _ThreadAppear({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cappedIndex = index.clamp(0, 6).toInt();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 170 + cappedIndex * 24),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 10),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _ThreadListSection extends StatelessWidget {
  const _ThreadListSection({
    required this.signature,
    required this.threads,
    required this.onOpenThread,
    required this.onOpenThreadTag,
    required this.onCopyThreadLink,
    required this.palette,
  });

  final String signature;
  final List<ForumThreadSummary> threads;
  final ValueChanged<ForumThreadSummary> onOpenThread;
  final ValueChanged<ForumThreadSummary> onOpenThreadTag;
  final ValueChanged<ForumThreadSummary> onCopyThreadLink;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0, 0.025),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offsetAnimation, child: child),
        );
      },
      child: Padding(
        key: ValueKey('forum-thread-list-$signature'),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        child: KeyedSubtree(
          key: const Key('forum-thread-list-group'),
          child: _SeparatedColumn(
            palette: palette,
            gap: 8,
            showDividers: false,
            children: [
              for (var index = 0; index < threads.length; index++)
                _ThreadAppear(
                  key: ValueKey('forum-thread-appear-${threads[index].tid}'),
                  index: index,
                  child: _ThreadCard(
                    thread: threads[index],
                    onTap: () => onOpenThread(threads[index]),
                    onLongPress: () => onCopyThreadLink(threads[index]),
                    onTapTag: () => onOpenThreadTag(threads[index]),
                    palette: palette,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreadCard extends StatefulWidget {
  const _ThreadCard({
    required this.thread,
    required this.onTap,
    required this.onLongPress,
    required this.onTapTag,
    required this.palette,
  });

  final ForumThreadSummary thread;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onTapTag;
  final ForumDisplayThemePalette palette;

  @override
  State<_ThreadCard> createState() => _ThreadCardState();
}

class _ThreadCardState extends State<_ThreadCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final palette = widget.palette;
    final titleColor = _parseColor(thread.titleColorHex) ?? palette.threadTitle;
    return AnimatedScale(
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      scale: _isPressed ? 0.985 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: ForumNativeSurfaceShadows.card(palette.stateLayer),
        ),
        child: Material(
          color: palette.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: Key('forum-thread-${thread.tid}'),
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            borderRadius: BorderRadius.circular(12),
            onHighlightChanged: (isHighlighted) {
              if (_isPressed != isHighlighted) {
                setState(() => _isPressed = isHighlighted);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: _isPressed
                    ? Color.alphaBlend(
                        palette.stateLayer,
                        palette.surfaceContainerLow,
                      )
                    : palette.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Avatar(
                          url: thread.avatarUrl,
                          author: thread.author,
                          palette: palette,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ThreadAuthorBlock(
                            thread: thread,
                            palette: palette,
                          ),
                        ),
                        if (thread.badgeLabel?.isNotEmpty == true) ...[
                          const SizedBox(width: 6),
                          _ThreadBadge(
                            label: thread.badgeLabel!,
                            palette: palette,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      thread.subject,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: titleColor,
                        height: 1.28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (thread.excerpt.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        thread.excerpt.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.bodyText,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _ThreadFooter(
                      thread: thread,
                      onTapTag: widget.onTapTag,
                      palette: palette,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThreadAuthorBlock extends StatelessWidget {
  const _ThreadAuthorBlock({required this.thread, required this.palette});

  final ForumThreadSummary thread;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final authorStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: palette.author,
      fontWeight: FontWeight.w700,
      height: 1.08,
    );
    final dateStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: palette.softText,
      fontWeight: FontWeight.w600,
      height: 1.08,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          thread.author.isNotEmpty ? thread.author : '匿名',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: authorStyle,
        ),
        if (thread.dateline.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            thread.dateline.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: dateStyle,
          ),
        ],
      ],
    );
  }
}

class _ThreadFooter extends StatelessWidget {
  const _ThreadFooter({
    required this.thread,
    required this.onTapTag,
    required this.palette,
  });

  final ForumThreadSummary thread;
  final VoidCallback onTapTag;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final hasTag = thread.sourceTagName?.trim().isNotEmpty == true;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Row(
            children: [
              _MetricChip(
                icon: Icons.visibility_outlined,
                value: thread.views,
                palette: palette,
              ),
              const SizedBox(width: 6),
              _MetricChip(
                icon: Icons.chat_bubble_outline,
                value: thread.replies,
                palette: palette,
              ),
            ],
          ),
        ),
        if (hasTag) ...[
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 118),
            child: Align(
              alignment: Alignment.centerRight,
              widthFactor: 1,
              child: _ThreadTagChip(
                thread: thread,
                onTapTag: onTapTag,
                palette: palette,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ThreadTagChip extends StatelessWidget {
  const _ThreadTagChip({
    required this.thread,
    required this.onTapTag,
    required this.palette,
  });

  final ForumThreadSummary thread;
  final VoidCallback onTapTag;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final tagName = thread.sourceTagName?.trim();
    if (tagName == null || tagName.isEmpty) {
      return const SizedBox.shrink();
    }
    final isClickable = thread.sourceTagUrl?.trim().isNotEmpty == true;
    return InkWell(
      key: Key('forum-thread-tag-${thread.tid}'),
      borderRadius: BorderRadius.circular(8),
      onTap: isClickable ? onTapTag : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceContainerHigh.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(8),
          border: isClickable ? null : Border.all(color: palette.outlineSoft),
          boxShadow: isClickable
              ? [
                  BoxShadow(
                    color: palette.stateLayer.withValues(alpha: 0.045),
                    blurRadius: 5,
                    offset: const Offset(0, 1.5),
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          child: Text(
            '#$tagName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: palette.tag,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.url,
    required this.author,
    required this.palette,
  });

  final String? url;
  final String author;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url?.trim();
    final useDefaultAvatar = isForumDefaultOrUnsupportedAvatarUrl(imageUrl);
    return CircleAvatar(
      radius: 18,
      backgroundColor: palette.avatarBackground,
      foregroundColor: palette.avatarForeground,
      child: useDefaultAvatar
          ? ClipOval(child: forumDefaultAvatarImage(width: 36, height: 36))
          : ClipOval(
              child: Image.network(
                imageUrl!,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    forumDefaultAvatarImage(width: 36, height: 36),
              ),
            ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.value,
    required this.palette,
  });

  final IconData icon;
  final int value;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: palette.surfaceContainerHigh.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: palette.softText),
          const SizedBox(width: 4),
          Text(
            value.toString(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: palette.softText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({
    required this.label,
    required this.accentColor,
    required this.palette,
  });

  final String label;
  final Color accentColor;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceContainerHigh.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: palette.stateLayer.withValues(alpha: 0.045),
            blurRadius: 5,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 26, minHeight: 18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: accentColor,
                height: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThreadBadge extends StatelessWidget {
  const _ThreadBadge({required this.label, required this.palette});

  final String label;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 30, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: palette.threadBadgeBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.threadBadgeOutline),
        boxShadow: [
          BoxShadow(
            color: palette.stateLayer.withValues(alpha: 0.05),
            blurRadius: 7,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: palette.threadBadgeForeground,
          height: 1.1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LoadMoreSection extends StatelessWidget {
  const _LoadMoreSection({
    required this.currentPage,
    required this.lastPage,
    required this.canLoadPrevious,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadPrevious,
    required this.onLoadMore,
    required this.onSelectPage,
    required this.palette,
  });

  final int currentPage;
  final int? lastPage;
  final bool canLoadPrevious;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadPrevious;
  final VoidCallback onLoadMore;
  final ValueChanged<int> onSelectPage;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PageButton(
            key: const Key('forum-display-prev-page-button'),
            label: '上一页',
            enabled: canLoadPrevious && !isLoadingMore,
            emphasized: false,
            onPressed: onLoadPrevious,
            palette: palette,
          ),
          const SizedBox(width: 8),
          _CurrentPageButton(
            currentPage: currentPage > 0 ? currentPage : 1,
            lastPage: lastPage,
            enabled: !isLoadingMore,
            onSelected: onSelectPage,
            palette: palette,
          ),
          const SizedBox(width: 8),
          if (isLoadingMore)
            const SizedBox(
              width: 72,
              height: 34,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            _PageButton(
              key: const Key('forum-display-load-more-button'),
              label: hasMore ? '下一页' : '没有更多',
              enabled: hasMore,
              emphasized: false,
              onPressed: onLoadMore,
              palette: palette,
            ),
        ],
      ),
    );
  }
}

class _CurrentPageButton extends StatelessWidget {
  const _CurrentPageButton({
    required this.currentPage,
    required this.lastPage,
    required this.enabled,
    required this.onSelected,
    required this.palette,
  });

  final int currentPage;
  final int? lastPage;
  final bool enabled;
  final ValueChanged<int> onSelected;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: TextButton(
        key: const Key('forum-display-current-page-button'),
        onPressed: enabled ? () => _showPagePicker(context) : null,
        style: _pageButtonStyle(context, enabled, palette, emphasized: true),
        child: Text('第$currentPage页'),
      ),
    );
  }

  Future<void> _showPagePicker(BuildContext context) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => _ForumDisplayPagePickerDialog(
        currentPage: currentPage,
        lastPage: lastPage,
      ),
    );
    if (selected != null) {
      onSelected(selected);
    }
  }
}

class _ForumDisplayPagePickerDialog extends StatefulWidget {
  const _ForumDisplayPagePickerDialog({
    required this.currentPage,
    required this.lastPage,
  });

  final int currentPage;
  final int? lastPage;

  @override
  State<_ForumDisplayPagePickerDialog> createState() =>
      _ForumDisplayPagePickerDialogState();
}

class _ForumDisplayPagePickerDialogState
    extends State<_ForumDisplayPagePickerDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentPage.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lastPage = widget.lastPage;
    return AlertDialog(
      title: const Text('选择页码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('forum-display-page-input'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: lastPage == null ? '页码' : '页码（1-$lastPage）',
              errorText: _errorText,
            ),
            onSubmitted: (_) => _submit(context),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ForumDisplayPageIncrementButton(
                buttonKey: const Key('forum-display-page-plus-5-button'),
                increment: 5,
                currentPage: widget.currentPage,
                lastPage: lastPage,
              ),
              _ForumDisplayPageIncrementButton(
                buttonKey: const Key('forum-display-page-plus-10-button'),
                increment: 10,
                currentPage: widget.currentPage,
                lastPage: lastPage,
              ),
              _ForumDisplayPageIncrementButton(
                buttonKey: const Key('forum-display-page-plus-50-button'),
                increment: 50,
                currentPage: widget.currentPage,
                lastPage: lastPage,
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('forum-display-page-confirm-button'),
          onPressed: () => _submit(context),
          child: const Text('跳转'),
        ),
      ],
    );
  }

  void _submit(BuildContext context) {
    final page = int.tryParse(_controller.text.trim());
    final lastPage = widget.lastPage;
    if (page == null || page < 1) {
      setState(() => _errorText = '请输入有效页码');
      return;
    }
    if (lastPage != null && page > lastPage) {
      setState(() => _errorText = '不能超过第$lastPage页');
      return;
    }
    Navigator.of(context).pop(page);
  }
}

class _ForumDisplayPageIncrementButton extends StatelessWidget {
  const _ForumDisplayPageIncrementButton({
    required this.buttonKey,
    required this.increment,
    required this.currentPage,
    required this.lastPage,
  });

  final Key buttonKey;
  final int increment;
  final int currentPage;
  final int? lastPage;

  @override
  Widget build(BuildContext context) {
    final targetPage = currentPage + increment;
    final maxPage = lastPage;
    final enabled = maxPage == null || targetPage <= maxPage;
    return OutlinedButton(
      key: buttonKey,
      onPressed: enabled ? () => Navigator.of(context).pop(targetPage) : null,
      child: Text('+$increment'),
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.emphasized,
    required this.onPressed,
    required this.palette,
  });

  final String label;
  final bool enabled;
  final bool emphasized;
  final VoidCallback onPressed;
  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        style: _pageButtonStyle(
          context,
          enabled,
          palette,
          emphasized: emphasized,
        ),
        child: Text(label),
      ),
    );
  }
}

ButtonStyle _pageButtonStyle(
  BuildContext context,
  bool enabled,
  ForumDisplayThemePalette palette, {
  required bool emphasized,
}) {
  return TextButton.styleFrom(
    backgroundColor: palette.surfaceContainerHigh.withValues(alpha: 0.42),
    disabledBackgroundColor: palette.surfaceContainerHigh.withValues(
      alpha: 0.42,
    ),
    disabledForegroundColor: palette.disabledText,
    foregroundColor: enabled ? palette.accent : palette.disabledText,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide.none,
    ),
    textStyle: Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
  );
}

class _EmptyThreadList extends StatelessWidget {
  const _EmptyThreadList({required this.palette});

  final ForumDisplayThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return _ForumDisplayGroup(
      palette: palette,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Text(
            '暂无帖子',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.softText),
          ),
        ),
      ),
    );
  }
}

Color? _parseColor(String? source) {
  final value = source?.trim();
  if (value == null || value.isEmpty || !value.startsWith('#')) {
    return null;
  }
  final hex = value.substring(1);
  if (hex.length == 3) {
    final expanded = hex.split('').map((char) => '$char$char').join();
    return Color(int.parse('FF$expanded', radix: 16));
  }
  if (hex.length == 6) {
    return Color(int.parse('FF$hex', radix: 16));
  }
  if (hex.length == 8) {
    return Color(int.parse(hex, radix: 16));
  }
  return null;
}
