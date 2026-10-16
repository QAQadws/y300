import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Owns keyboard avoidance for the document and its bottom actions together.
class BlogComposerLayout extends StatelessWidget {
  const BlogComposerLayout({
    super.key,
    required this.body,
    this.toolbar,
    this.onKeyboardShown,
  });

  final Widget body;
  final Widget? toolbar;
  final VoidCallback? onKeyboardShown;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = math.max(
      media.viewInsets.bottom,
      media.viewPadding.bottom,
    );
    return MediaQuery(
      // This viewport already excludes the keyboard and bottom safe area.
      // Keep those metrics out of the editor and the toolbar's own SafeArea.
      data: media
          .removeViewInsets(removeBottom: true)
          .removePadding(removeBottom: true),
      child: _AnimatedBlogComposerLayout(
        bottomInset: bottomInset,
        duration: media.disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 180),
        body: body,
        toolbar: toolbar,
        onEnd: media.viewInsets.bottom > 0 ? onKeyboardShown : null,
      ),
    );
  }
}

class _AnimatedBlogComposerLayout extends ImplicitlyAnimatedWidget {
  const _AnimatedBlogComposerLayout({
    required this.bottomInset,
    required super.duration,
    required this.body,
    required this.toolbar,
    super.onEnd,
  }) : super(curve: Curves.easeOutCubic);

  final double bottomInset;
  final Widget body;
  final Widget? toolbar;

  @override
  ImplicitlyAnimatedWidgetState<_AnimatedBlogComposerLayout> createState() =>
      _AnimatedBlogComposerLayoutState();
}

class _AnimatedBlogComposerLayoutState
    extends ImplicitlyAnimatedWidgetState<_AnimatedBlogComposerLayout> {
  Tween<double>? _bottomInset;
  late Animation<double> _insetAnimation;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _bottomInset = visitor(
      _bottomInset,
      widget.bottomInset,
      (value) => Tween<double>(begin: value as double),
    ) as Tween<double>?;
  }

  @override
  void didUpdateTweens() {
    _insetAnimation = _bottomInset!.animate(animation);
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: CustomMultiChildLayout(
      // Only layout listens to animation ticks; document widgets stay intact.
      delegate: _BlogComposerLayoutDelegate(_insetAnimation),
      children: [
        LayoutId(id: _BlogComposerSlot.body, child: widget.body),
        if (widget.toolbar case final toolbar?)
          LayoutId(id: _BlogComposerSlot.toolbar, child: toolbar),
      ],
    ),
  );
}

enum _BlogComposerSlot { body, toolbar }

class _BlogComposerLayoutDelegate extends MultiChildLayoutDelegate {
  _BlogComposerLayoutDelegate(this.bottomInset) : super(relayout: bottomInset);

  final Animation<double> bottomInset;

  @override
  void performLayout(Size size) {
    var toolbarHeight = 0.0;
    if (hasChild(_BlogComposerSlot.toolbar)) {
      toolbarHeight = layoutChild(
        _BlogComposerSlot.toolbar,
        BoxConstraints(
          minWidth: size.width,
          maxWidth: size.width,
          maxHeight: size.height,
        ),
      ).height;
    }
    // Keep short landscape viewports valid even with a tall IME or toolbar.
    final inset = bottomInset.value.clamp(
      0.0,
      math.max(0.0, size.height - toolbarHeight),
    );
    final bodyHeight = math.max(0.0, size.height - toolbarHeight - inset);
    layoutChild(
      _BlogComposerSlot.body,
      BoxConstraints.tight(Size(size.width, bodyHeight)),
    );
    positionChild(_BlogComposerSlot.body, Offset.zero);
    if (hasChild(_BlogComposerSlot.toolbar)) {
      positionChild(_BlogComposerSlot.toolbar, Offset(0, bodyHeight));
    }
  }

  @override
  bool shouldRelayout(_BlogComposerLayoutDelegate oldDelegate) =>
      bottomInset != oldDelegate.bottomInset;
}
