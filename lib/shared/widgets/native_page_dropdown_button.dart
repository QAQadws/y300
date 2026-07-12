import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A lazy, anchored page picker for native forum pagination surfaces.
///
/// Only visible rows are built, so threads and forums with many pages do not
/// pay the cost of materializing every menu item when the picker opens.
class NativePageDropdownButton extends StatefulWidget {
  const NativePageDropdownButton({
    super.key,
    required this.buttonKey,
    required this.menuKeyPrefix,
    required this.currentPage,
    required this.lastPage,
    required this.hasMore,
    required this.enabled,
    required this.label,
    required this.style,
    required this.onSelected,
  });

  final Key buttonKey;
  final String menuKeyPrefix;
  final int currentPage;
  final int? lastPage;
  final bool hasMore;
  final bool enabled;
  final String label;
  final ButtonStyle? style;
  final ValueChanged<int> onSelected;

  @override
  State<NativePageDropdownButton> createState() =>
      _NativePageDropdownButtonState();
}

class _NativePageDropdownButtonState extends State<NativePageDropdownButton> {
  final GlobalKey _anchorKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: widget.buttonKey,
      height: 34,
      child: TextButton(
        key: _anchorKey,
        onPressed: widget.enabled ? _showPageMenu : null,
        style: widget.style,
        child: Text(widget.label),
      ),
    );
  }

  Future<void> _showPageMenu() async {
    final anchor = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (anchor == null || overlay == null || !anchor.hasSize) {
      return;
    }

    final currentPage = math.max(1, widget.currentPage);
    final knownLastPage = widget.lastPage;
    final pageCount = knownLastPage != null && knownLastPage > 0
        ? math.max(currentPage, knownLastPage)
        : currentPage + (widget.hasMore ? 1 : 0);
    final anchorTopLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
    final anchorBottomRight = anchor.localToGlobal(
      anchor.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final anchorRect = Rect.fromPoints(anchorTopLeft, anchorBottomRight);
    final menuWidth = math.max(120.0, anchor.size.width);
    const horizontalMargin = 8.0;
    final menuLeft = (anchorRect.center.dx - menuWidth / 2)
        .clamp(
          horizontalMargin,
          math.max(
            horizontalMargin,
            overlay.size.width - menuWidth - horizontalMargin,
          ),
        )
        .toDouble();
    final viewportHeight = math.min(
      _NativePageListPopupEntry.itemExtent * pageCount,
      _NativePageListPopupEntry.maximumHeight,
    );

    final selected = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(menuLeft, anchorRect.bottom, menuWidth, 0),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      constraints: BoxConstraints.tightFor(width: menuWidth),
      items: [
        _NativePageListPopupEntry(
          key: Key('${widget.menuKeyPrefix}-page-menu'),
          menuKeyPrefix: widget.menuKeyPrefix,
          currentPage: currentPage,
          pageCount: pageCount,
          width: menuWidth,
          viewportHeight: viewportHeight,
        ),
      ],
    );

    if (!mounted || selected == null || selected == currentPage) {
      return;
    }
    widget.onSelected(selected);
  }
}

class _NativePageListPopupEntry extends PopupMenuEntry<int> {
  const _NativePageListPopupEntry({
    super.key,
    required this.menuKeyPrefix,
    required this.currentPage,
    required this.pageCount,
    required this.width,
    required this.viewportHeight,
  });

  static const double itemExtent = 44;
  static const double maximumHeight = itemExtent * 8;

  final String menuKeyPrefix;
  final int currentPage;
  final int pageCount;
  final double width;
  final double viewportHeight;

  @override
  double get height => viewportHeight;

  @override
  bool represents(int? value) => value == currentPage;

  @override
  State<_NativePageListPopupEntry> createState() =>
      _NativePageListPopupEntryState();
}

class _NativePageListPopupEntryState extends State<_NativePageListPopupEntry> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    final selectedOffset =
        (widget.currentPage - 1) * _NativePageListPopupEntry.itemExtent;
    final centeredOffset =
        selectedOffset -
        (widget.viewportHeight - _NativePageListPopupEntry.itemExtent) / 2;
    final maxOffset = math.max(
      0.0,
      widget.pageCount * _NativePageListPopupEntry.itemExtent -
          widget.viewportHeight,
    );
    _scrollController = ScrollController(
      initialScrollOffset: centeredOffset.clamp(0.0, maxOffset),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: widget.width,
      height: widget.viewportHeight,
      child: ListView.builder(
        key: Key('${widget.menuKeyPrefix}-page-list'),
        controller: _scrollController,
        itemExtent: _NativePageListPopupEntry.itemExtent,
        itemCount: widget.pageCount,
        padding: EdgeInsets.zero,
        itemBuilder: (context, index) {
          final page = index + 1;
          final selected = page == widget.currentPage;
          return Semantics(
            button: true,
            selected: selected,
            label: '第$page页',
            child: InkWell(
              key: Key('${widget.menuKeyPrefix}-page-option-$page'),
              onTap: () => Navigator.of(context).pop(page),
              child: ColoredBox(
                color: selected
                    ? colorScheme.secondaryContainer
                    : Colors.transparent,
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: selected
                          ? Icon(
                              Icons.check,
                              size: 18,
                              color: colorScheme.onSecondaryContainer,
                            )
                          : null,
                    ),
                    Expanded(
                      child: Text(
                        '$page',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: selected
                              ? colorScheme.onSecondaryContainer
                              : colorScheme.onSurface,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 36),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
