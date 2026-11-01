import 'package:flutter/widgets.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_surface.dart';
import '../inline/forum_body_inline_paragraph_surface.dart';
import 'forum_body_prepared_text_fragment.dart';
import 'forum_body_text_page_composer.dart';
import 'forum_body_text_page_binding.dart';

export 'forum_body_text_page_binding.dart'
    show ForumBodyTextPageSurfaceFailure, ForumBodyTextPageSurfaceException;

/// Paint an already composed page using already prepared leases. No shaping,
/// cache acquisition, HTML preparation or settings resolution occurs in build.
/// The Host guards owner/catalog identity and supplies the original content box
/// while reflow is pending. This validates the generation and fragment geometry.
///
/// Each concurrently mounted fragment needs its own lease. Mounted paragraph
/// surfaces own those leases; construction failure or an abandoned, unmounted
/// widget leaves cleanup with the caller. Ordinary rebuilds may reuse leases.
final class ForumBodyTextPageSurface extends StatelessWidget {
  factory ForumBodyTextPageSurface({
    Key? key,
    required ForumBodyTextPageSnapshot snapshot,
    required int pageIndex,
    required String layoutId,
    required List<ForumBodyParagraphLease> leases,
    void Function(
      ForumBodyTextPageFragment fragment,
      HtmlProjectedSourcePosition position,
    )?
    onSourceTap,
  }) {
    validateForumBodyTextPageBinding(
      snapshot: snapshot,
      pageIndex: pageIndex,
      layoutId: layoutId,
      leases: leases,
    );
    return ForumBodyTextPageSurface.prepared(
      key: key,
      snapshot: snapshot,
      pageIndex: pageIndex,
      layoutId: layoutId,
      fragments: [
        for (final (index, fragment) in snapshot[pageIndex].fragments.indexed)
          ForumBodyPreparedTextFragment.paragraph(
            lease: leases[index],
            startLine: fragment.startLine,
            endLine: fragment.endLine,
          ),
      ],
      onSourceTap: onSourceTap,
    );
  }

  /// Complete typed ordinary/inline delivery. Validation borrows its inputs;
  /// construction failure or an unmounted widget stays caller-owned, just as
  /// with the ordinary entry. Mounted surfaces take the supplied handles.
  factory ForumBodyTextPageSurface.prepared({
    Key? key,
    required ForumBodyTextPageSnapshot snapshot,
    required int pageIndex,
    required String layoutId,
    required List<ForumBodyPreparedTextFragment> fragments,
    void Function(ForumBodyTextPageFragment, HtmlProjectedSourcePosition)?
    onSourceTap,
  }) {
    final page = validateForumBodyPreparedTextPageBinding(
      snapshot: snapshot,
      pageIndex: pageIndex,
      layoutId: layoutId,
      fragments: fragments,
    );
    return ForumBodyTextPageSurface._(
      key,
      page,
      layoutId,
      snapshot.width,
      snapshot.height,
      List.unmodifiable(fragments),
      onSourceTap,
    );
  }

  const ForumBodyTextPageSurface._(
    Key? key,
    this._page,
    this._layoutId,
    this._width,
    this._height,
    this._bindings,
    this._onSourceTap,
  ) : super(key: key);
  final ForumBodyTextPage _page;
  final String _layoutId;
  final double _width;
  final double _height;
  final List<ForumBodyPreparedTextFragment> _bindings;
  final void Function(ForumBodyTextPageFragment, HtmlProjectedSourcePosition)?
  _onSourceTap;

  static Never _fail(ForumBodyTextPageSurfaceFailure failure) =>
      throw ForumBodyTextPageSurfaceException(failure);

  static Object _bindingKey(ForumBodyPreparedTextFragment binding) =>
      switch (binding) {
        ForumBodyPreparedParagraphFragment() => binding.lease,
        ForumBodyPreparedInlineFragment() => binding.view,
      };

  Widget _fragmentSurface(
    ForumBodyTextPageFragment fragment,
    ForumBodyPreparedTextFragment binding,
  ) {
    final interaction = (
      _layoutId,
      _page.index,
      fragment.paragraphIndex,
      fragment.startLine,
      fragment.endLine,
      fragment.left,
      fragment.top,
    );
    final tap = _onSourceTap == null
        ? null
        : (HtmlProjectedSourcePosition position) =>
              _onSourceTap(fragment, position);
    return switch (binding) {
      ForumBodyPreparedParagraphFragment() => ForumBodyParagraphSurface(
        lease: binding.lease,
        startLine: binding.startLine,
        endLine: binding.endLine,
        interactionIdentity: interaction,
        onSourceTap: tap,
      ),
      ForumBodyPreparedInlineFragment() => ForumBodyInlineParagraphSurface(
        view: binding.view,
        paintBackgrounds: false,
        interactionIdentity: interaction,
        onSourceTap: tap,
      ),
    };
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.constrain(Size(_width, _height)) !=
          Size(_width, _height)) {
        _fail(ForumBodyTextPageSurfaceFailure.geometry);
      }
      return SizedBox(
        width: _width,
        height: _height,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (_bindings.any(
              (binding) =>
                  binding is ForumBodyPreparedInlineFragment &&
                  binding.view.isActive &&
                  binding.view.containerBackgrounds.isNotEmpty,
            ))
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _RubyPageBackgroundPainter(_page, _bindings),
                  ),
                ),
              ),
            for (final (index, fragment) in _page.fragments.indexed)
              Positioned(
                key: ObjectKey(_bindingKey(_bindings[index])),
                left: fragment.left,
                top: fragment.top,
                width: fragment.width,
                height: fragment.height,
                child: _fragmentSurface(fragment, _bindings[index]),
              ),
          ],
        ),
      );
    },
  );
}

/// One page background plane keeps natural font-box overflow clipped to the
/// actual content box and underneath every paragraph/annotation glyph.
final class _RubyPageBackgroundPainter extends CustomPainter {
  const _RubyPageBackgroundPainter(this.page, this.bindings);
  final ForumBodyTextPage page;
  final List<ForumBodyPreparedTextFragment> bindings;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    try {
      // Stack need not clip paint overflow when its children's layout fits.
      canvas.clipRect(Offset.zero & size, doAntiAlias: false);
      for (final (index, binding) in bindings.indexed) {
        if (binding is ForumBodyPreparedInlineFragment &&
            binding.view.isActive) {
          final fragment = page.fragments[index];
          binding.view.paintContainerBackgrounds(
            canvas,
            Offset(fragment.left, fragment.top),
          );
        }
      }
    } finally {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _RubyPageBackgroundPainter oldDelegate) =>
      !identical(page, oldDelegate.page) ||
      !identical(bindings, oldDelegate.bindings);
}
