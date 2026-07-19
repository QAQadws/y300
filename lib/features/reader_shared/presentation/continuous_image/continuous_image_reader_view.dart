import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';

import 'continuous_image_extent_observer.dart';

enum ContinuousImageReaderMode { vertical, horizontal }

typedef ContinuousImageReaderItemBuilder =
    Widget Function(
      BuildContext context,
      ContinuousImageItem item,
      int index, {
      required bool paged,
    });

class ContinuousImageReaderView extends StatelessWidget {
  const ContinuousImageReaderView({
    super.key,
    required this.items,
    required this.mode,
    required this.itemBuilder,
    required this.onExtentResolved,
    this.scrollController,
    this.pageController,
    this.layoutResolver = const ContinuousImageLayoutResolver(),
    this.scrollCacheExtent,
    this.reverse = false,
    this.onPageChanged,
    this.horizontalPhysics,
    this.verticalTrailingBuilder,
    this.verticalTrailingItemCount = 0,
    this.verticalTrailingItemBuilder,
    this.horizontalTrailingBuilder,
    this.horizontalAdvanceBuilder,
    this.horizontalPagePadding = EdgeInsets.zero,
    this.verticalListKey = const Key('continuous-image-reader-list'),
    this.horizontalPageKey = const Key('continuous-image-reader-page-view'),
    this.slotKeyPrefix = 'continuous-image-reader-slot',
    this.verticalItemAnchorKeyBuilder,
  });

  final List<ContinuousImageItem> items;
  final ContinuousImageReaderMode mode;
  final ContinuousImageReaderItemBuilder itemBuilder;
  final ValueChanged<ContinuousImageExtent> onExtentResolved;
  final ScrollController? scrollController;
  final PageController? pageController;
  final ContinuousImageLayoutResolver layoutResolver;
  final ScrollCacheExtent? scrollCacheExtent;
  final bool reverse;
  final ValueChanged<int>? onPageChanged;
  final ScrollPhysics? horizontalPhysics;
  final WidgetBuilder? verticalTrailingBuilder;
  final int verticalTrailingItemCount;
  final IndexedWidgetBuilder? verticalTrailingItemBuilder;
  final WidgetBuilder? horizontalTrailingBuilder;
  final WidgetBuilder? horizontalAdvanceBuilder;
  final EdgeInsetsGeometry horizontalPagePadding;
  final Key verticalListKey;
  final Key horizontalPageKey;
  final String slotKeyPrefix;
  final Key Function(ContinuousImageItem item, int index)?
  verticalItemAnchorKeyBuilder;

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case ContinuousImageReaderMode.vertical:
        return _buildVertical(context);
      case ContinuousImageReaderMode.horizontal:
        return _buildHorizontal(context);
    }
  }

  Widget _buildVertical(BuildContext context) {
    final trailingCount = verticalTrailingItemBuilder != null
        ? verticalTrailingItemCount.clamp(0, 1 << 20).toInt()
        : verticalTrailingBuilder == null
        ? 0
        : 1;
    return ListView.builder(
      key: verticalListKey,
      controller: scrollController,
      scrollCacheExtent: scrollCacheExtent,
      padding: EdgeInsets.zero,
      itemCount: items.length + trailingCount,
      itemBuilder: (context, index) {
        if (index >= items.length) {
          final trailingIndex = index - items.length;
          final indexedBuilder = verticalTrailingItemBuilder;
          if (indexedBuilder != null) {
            return indexedBuilder(context, trailingIndex);
          }
          return verticalTrailingBuilder!(context);
        }
        final item = items[index];
        return Column(
          children: [
            ContinuousImageReaderSlot(
              key: ValueKey<String>('$slotKeyPrefix-${item.index}'),
              anchorKey: verticalItemAnchorKeyBuilder?.call(item, index),
              item: item,
              layoutResolver: layoutResolver,
              onExtentResolved: onExtentResolved,
              child: itemBuilder(context, item, index, paged: false),
            ),
            if (item.spacingAfter > 0) SizedBox(height: item.spacingAfter),
          ],
        );
      },
    );
  }

  Widget _buildHorizontal(BuildContext context) {
    final hasTail = horizontalTrailingBuilder != null;
    final hasAdvance = horizontalAdvanceBuilder != null;
    final tailIndex = items.length;
    final advanceIndex = tailIndex + (hasTail ? 1 : 0);
    return PageView.builder(
      key: horizontalPageKey,
      controller: pageController,
      physics: horizontalPhysics,
      reverse: reverse,
      allowImplicitScrolling: true,
      onPageChanged: onPageChanged,
      itemCount: items.length + (hasTail ? 1 : 0) + (hasAdvance ? 1 : 0),
      itemBuilder: (context, index) {
        if (hasTail && index == tailIndex) {
          return horizontalTrailingBuilder!(context);
        }
        if (hasAdvance && index == advanceIndex) {
          return horizontalAdvanceBuilder!(context);
        }
        final item = items[index];
        return Padding(
          padding: horizontalPagePadding,
          child: SizedBox.expand(
            child: itemBuilder(context, item, index, paged: true),
          ),
        );
      },
    );
  }
}

class ContinuousImageReaderSlot extends StatelessWidget {
  const ContinuousImageReaderSlot({
    super.key,
    required this.item,
    required this.layoutResolver,
    required this.onExtentResolved,
    required this.child,
    this.anchorKey,
  });

  final ContinuousImageItem item;
  final ContinuousImageLayoutResolver layoutResolver;
  final ValueChanged<ContinuousImageExtent> onExtentResolved;
  final Widget child;
  final Key? anchorKey;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final hint = layoutResolver.resolveInitialHint(item: item);
        final expectedHeight = width / hint.aspectRatio;
        final aspectRatio = width > 0
            ? width / expectedHeight
            : hint.aspectRatio;
        final slot = ContinuousImageExtentObserver(
          item: item,
          aspectRatio: aspectRatio,
          dimensionSource: hint.source,
          onExtentResolved: onExtentResolved,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: expectedHeight),
            child: ClipRect(child: child),
          ),
        );
        final key = anchorKey;
        return key == null ? slot : KeyedSubtree(key: key, child: slot);
      },
    );
  }
}
