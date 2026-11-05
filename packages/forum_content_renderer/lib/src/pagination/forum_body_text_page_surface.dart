import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../style/forum_body_quote_decoration.dart';
import '../contracts/forum_html_display_image.dart';
import '../contracts/forum_html_image_host.dart';
import '../contracts/forum_collapse_header_metrics.dart';
import '../contracts/forum_html_collapse_labels.dart';
import '../helpers/forum_collapse_chrome.dart';
import '../html_rendering/widgets/forum_html_image_view.dart';
import '../paragraph/forum_body_paragraph_surface.dart';
import '../inline/forum_body_inline_paragraph_surface.dart';
import '../inline/forum_body_inline_paragraph_view.dart';
import '../inline/forum_body_emphasis_fragment_surface.dart';
import '../services/forum_html_image_anchor_controller.dart';
import 'forum_body_prepared_text_fragment.dart';
import 'forum_body_text_page_composer.dart';
import 'forum_body_text_page_binding.dart';
import 'forum_body_text_selection_snapshot.dart';

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
    void Function(ForumBodyTextPageFragment, ForumBodyTextSelectionSnapshot)?
    onSourceLongPress,
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
      onSourceLongPress: onSourceLongPress,
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
    // A cell's internal page has a large layout ceiling. Mount only the
    // occupied box when placing that already published slice in a table.
    bool compactHeight = false,
    ForumHtmlImageHost? imageHost,
    ForumHtmlImageAnchorController? imageAnchorController,
    ForumHtmlCollapseLabels? collapseLabels,
    ValueChanged<ForumBodyTextPageFragment>? onCollapseToggle,
    void Function(ForumBodyPreparedImageFragment, bool)? onImageDisplayChanged,
    void Function(ForumBodyPreparedImageFragment, ForumHtmlImageLayout)?
    onImageLayoutResolved,
    ValueChanged<ForumBodyPreparedImageFragment>? onImageTap,
    void Function(
      ForumBodyPreparedInlineFragment,
      ForumBodyInlineImageBinding,
      bool,
    )?
    onInlineImageDisplayChanged,
    void Function(
      ForumBodyPreparedInlineFragment,
      ForumBodyInlineImageBinding,
      ForumHtmlImageLayout,
    )?
    onInlineImageLayoutResolved,
    void Function(ForumBodyPreparedInlineFragment, ForumBodyInlineImageBinding)?
    onInlineImageTap,
    void Function(ForumBodyTextPageFragment, HtmlProjectedSourcePosition)?
    onSourceTap,
    void Function(ForumBodyTextPageFragment, ForumBodyTextSelectionSnapshot)?
    onSourceLongPress,
  }) {
    final page = validateForumBodyPreparedTextPageBinding(
      snapshot: snapshot,
      pageIndex: pageIndex,
      layoutId: layoutId,
      fragments: fragments,
    );
    final images = <ForumBodyPreparedImageFragment, ForumHtmlDisplayImage>{};
    for (final fragment in fragments) {
      final binding = fragment is ForumBodyPreparedListItemFragment
          ? fragment.body
          : fragment;
      if (binding is ForumBodyPreparedInlineFragment &&
          binding.view.images.isNotEmpty &&
          imageHost == null) {
        _fail(ForumBodyTextPageSurfaceFailure.leases);
      }
      if (binding is! ForumBodyPreparedImageFragment) continue;
      if (imageHost == null) _fail(ForumBodyTextPageSurfaceFailure.leases);
      final entry = binding.content.input.entry;
      final uri = Uri.tryParse(entry.url);
      if (uri == null) _fail(ForumBodyTextPageSurfaceFailure.identity);
      final display = imageHost.resolveImage(
        url: uri,
        imageIndex: entry.index,
        isSticker: false,
        htmlSize: entry.htmlWidth != null && entry.htmlHeight != null
            ? Size(entry.htmlWidth!, entry.htmlHeight!)
            : null,
      );
      if (display == null ||
          display.sourceUrl != entry.url ||
          display.cacheKey != entry.cacheKey ||
          display.isSticker) {
        _fail(ForumBodyTextPageSurfaceFailure.identity);
      }
      images[binding] = display;
    }
    return ForumBodyTextPageSurface._(
      key,
      page,
      layoutId,
      snapshot.width,
      compactHeight ? page.usedHeight : snapshot.height,
      List.unmodifiable(fragments),
      onSourceTap,
      onSourceLongPress,
      imageHost,
      imageAnchorController,
      Map.unmodifiable(images),
      onImageDisplayChanged,
      onImageLayoutResolved,
      onImageTap,
      onInlineImageDisplayChanged,
      onInlineImageLayoutResolved,
      onInlineImageTap,
      collapseLabels,
      onCollapseToggle,
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
    this._onSourceLongPress,
    this._imageHost,
    this._imageAnchorController,
    this._images,
    this._onImageDisplayChanged,
    this._onImageLayoutResolved,
    this._onImageTap,
    this._onInlineImageDisplayChanged,
    this._onInlineImageLayoutResolved,
    this._onInlineImageTap,
    this._collapseLabels,
    this._onCollapseToggle,
  ) : super(key: key);
  final ForumBodyTextPage _page;
  final String _layoutId;
  final double _width;
  final double _height;
  final List<ForumBodyPreparedTextFragment> _bindings;
  final void Function(ForumBodyTextPageFragment, HtmlProjectedSourcePosition)?
  _onSourceTap;
  final void Function(
    ForumBodyTextPageFragment,
    ForumBodyTextSelectionSnapshot,
  )?
  _onSourceLongPress;
  final ForumHtmlImageHost? _imageHost;
  final ForumHtmlImageAnchorController? _imageAnchorController;
  final Map<ForumBodyPreparedImageFragment, ForumHtmlDisplayImage> _images;
  final void Function(ForumBodyPreparedImageFragment, bool)?
  _onImageDisplayChanged;
  final void Function(ForumBodyPreparedImageFragment, ForumHtmlImageLayout)?
  _onImageLayoutResolved;
  final ValueChanged<ForumBodyPreparedImageFragment>? _onImageTap;
  final void Function(
    ForumBodyPreparedInlineFragment,
    ForumBodyInlineImageBinding,
    bool,
  )?
  _onInlineImageDisplayChanged;
  final void Function(
    ForumBodyPreparedInlineFragment,
    ForumBodyInlineImageBinding,
    ForumHtmlImageLayout,
  )?
  _onInlineImageLayoutResolved;
  final void Function(
    ForumBodyPreparedInlineFragment,
    ForumBodyInlineImageBinding,
  )?
  _onInlineImageTap;
  final ForumHtmlCollapseLabels? _collapseLabels;
  final ValueChanged<ForumBodyTextPageFragment>? _onCollapseToggle;

  static Never _fail(ForumBodyTextPageSurfaceFailure failure) =>
      throw ForumBodyTextPageSurfaceException(failure);

  static Object _bindingKey(ForumBodyPreparedTextFragment binding) =>
      switch (binding) {
        ForumBodyPreparedImageFragment() => binding,
        ForumBodyPreparedListItemFragment() => binding.picture,
        ForumBodyPreparedParagraphFragment() => binding.lease,
        ForumBodyPreparedInlineFragment() => binding.view,
        ForumBodyPreparedEmphasisFragment() => binding.view,
        ForumBodyPreparedFittedEmphasisFragment() => binding.view,
      };

  Widget _fragmentSurface(
    ForumBodyTextPageFragment fragment,
    ForumBodyPreparedTextFragment binding,
  ) {
    if (binding is ForumBodyPreparedListItemFragment) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: _fragmentSurface(fragment, binding.body)),
          Positioned.fill(
            child: IgnorePointer(child: _ListMarkerSurface(binding)),
          ),
        ],
      );
    }
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
      ForumBodyPreparedImageFragment() => _ImageFragmentSurface(
        binding: binding,
        host: _imageHost!,
        image: _images[binding]!,
        anchorController: _imageAnchorController,
        onDisplayChanged: _onImageDisplayChanged,
        onLayoutResolved: _onImageLayoutResolved,
        onTap: _onImageTap,
      ),
      ForumBodyPreparedListItemFragment() => throw StateError(
        'Nested list delivery',
      ),
      ForumBodyPreparedParagraphFragment() => ForumBodyParagraphSurface(
        lease: binding.lease,
        startLine: binding.startLine,
        endLine: binding.endLine,
        interactionIdentity: interaction,
        onSourceTap: tap,
      ),
      ForumBodyPreparedInlineFragment() when binding.view.images.isEmpty =>
        ForumBodyInlineParagraphSurface(
          view: binding.view,
          paintBackgrounds: false,
          interactionIdentity: interaction,
          onSourceTap: tap,
        ),
      ForumBodyPreparedInlineFragment() => ForumBodyInlineImageSurface(
        view: binding.view,
        imageHost: _imageHost,
        imageAnchorController: _imageAnchorController,
        onImageDisplayChanged: _onInlineImageDisplayChanged == null
            ? null
            : (image, rendered) =>
                  _onInlineImageDisplayChanged(binding, image, rendered),
        onImageLayoutResolved: _onInlineImageLayoutResolved == null
            ? null
            : (image, layout) =>
                  _onInlineImageLayoutResolved(binding, image, layout),
        onImageTap: _onInlineImageTap == null
            ? null
            : (image) => _onInlineImageTap(binding, image),
        paintBackgrounds: false,
        interactionIdentity: interaction,
        onSourceTap: tap,
      ),
      ForumBodyPreparedEmphasisFragment() => ForumBodyEmphasisFragmentSurface(
        view: binding.view,
        interactionIdentity: interaction,
        onSourceTap: tap,
      ),
      ForumBodyPreparedFittedEmphasisFragment() => ForumBodyEmphasisLineSurface(
        view: binding.view,
        interactionIdentity: interaction,
        onSourceTap: tap,
      ),
    };
  }

  Widget _placedFragment(
    BuildContext context,
    ForumBodyTextPageFragment fragment,
    ForumBodyPreparedTextFragment binding,
  ) {
    final key = ObjectKey(_bindingKey(binding));
    final surface = _fragmentSurface(fragment, binding);
    final body = fragment.kind == ForumBodyTextPageFragmentKind.image
        ? surface
        : _TextLongPressSurface(
            identity: (
              _layoutId,
              _page.index,
              fragment.paragraphIndex,
              fragment.startLine,
              fragment.endLine,
              fragment.left,
              fragment.top,
              fragment.width,
              fragment.height,
            ),
            onLongPress: _onSourceLongPress == null
                ? null
                : (point) {
                    final selected = forumBodyTextSelectionAt(
                      binding: binding,
                      fragment: fragment,
                      pageSize: Size(_width, _height),
                      point: point,
                    );
                    if (selected != null) {
                      _onSourceLongPress(fragment, selected);
                    }
                  },
            child: surface,
          );
    final header = fragment.collapseHeader;
    if (header == null) {
      return Positioned(
        key: key,
        left: fragment.left,
        top: fragment.top,
        width: fragment.width,
        height: fragment.height,
        child: body,
      );
    }
    final bounds = header.bounds;
    return Positioned.fromRect(
      key: key,
      rect: bounds,
      child: Directionality(
        textDirection: header.direction,
        child: Material(
          type: MaterialType.transparency,
          child: DecoratedBox(
            decoration: forumCollapseOutline(
              Theme.of(context).colorScheme.outlineVariant,
            ),
            child: ForumCollapseHeaderControl(
              toggleKey: ValueKey(
                'forum-native-collapse-toggle-${header.id}-${fragment.paragraphIndex}',
              ),
              expanded: header.expanded,
              label: header.expanded
                  ? _collapseLabels?.expandedSemanticsLabel
                  : _collapseLabels?.collapsedSemanticsLabel,
              onTap: _onCollapseToggle == null
                  ? null
                  : () {
                      if (binding.isActive) _onCollapseToggle(fragment);
                    },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  PositionedDirectional(
                    start: ForumCollapseHeaderMetrics.inset,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: ForumCollapseChevron(expanded: header.expanded),
                      ),
                    ),
                  ),
                  Positioned(
                    left: fragment.left - bounds.left,
                    top: fragment.top - bounds.top,
                    width: fragment.width,
                    height: fragment.height,
                    child: body,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
            if (_page.backgrounds.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _BlockBackgroundPainter(_page.backgrounds),
                  ),
                ),
              ),
            if (_page.rules.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _RulePainter(_page.rules)),
                ),
              ),
            if (_bindings.any((binding) => _hasRubyBackground(binding)))
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _RubyPageBackgroundPainter(_page, _bindings),
                  ),
                ),
              ),
            for (final (index, fragment) in _page.fragments.indexed)
              _placedFragment(context, fragment, _bindings[index]),
          ],
        ),
      );
    },
  );
}

/// Resource pixels may change, but published placement is fixed. The Host
/// uses ForumHtmlImageView with contain fit; new hints reflow via a new
/// layout generation. This surface owns the transient delivery on mount.
final class _ImageFragmentSurface extends StatefulWidget {
  const _ImageFragmentSurface({
    required this.binding,
    required this.host,
    required this.image,
    this.anchorController,
    this.onDisplayChanged,
    this.onLayoutResolved,
    this.onTap,
  });
  final ForumBodyPreparedImageFragment binding;
  final ForumHtmlImageHost host;
  final ForumHtmlDisplayImage image;
  final ForumHtmlImageAnchorController? anchorController;
  final void Function(ForumBodyPreparedImageFragment, bool)? onDisplayChanged;
  final void Function(ForumBodyPreparedImageFragment, ForumHtmlImageLayout)?
  onLayoutResolved;
  final ValueChanged<ForumBodyPreparedImageFragment>? onTap;
  @override
  State<_ImageFragmentSurface> createState() => _ImageFragmentSurfaceState();
}

final class _ImageFragmentSurfaceState extends State<_ImageFragmentSurface> {
  @override
  Widget build(BuildContext context) {
    if (!widget.binding.isActive) {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.leases,
      );
    }
    final input = widget.binding.content.input;
    final image = Semantics(
      image: true,
      label:
          widget.binding.content.input.entry.alt ??
          widget.binding.content.input.entry.title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null
            ? null
            : () {
                if (!mounted || !widget.binding.isActive) return;
                widget.onTap?.call(widget.binding);
              },
        child: ForumHtmlImageView(
          host: widget.host,
          image: widget.image,
          fit: BoxFit.contain,
          onImageLayoutResolved: (layout) {
            if (!mounted || !widget.binding.isActive) return;
            widget.onLayoutResolved?.call(widget.binding, layout);
          },
          onImageDisplayChanged: (ready) {
            if (!mounted || !widget.binding.isActive) return;
            widget.binding.reportDisplayFrame(ready);
            widget.onDisplayChanged?.call(widget.binding, ready);
          },
        ),
      ),
    );
    final entry = input.entry;
    final controller = widget.anchorController;
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fromRect(
          rect: widget.binding.content.frame.imageRect,
          child: controller == null
              ? image
              : ForumHtmlImageAnchor(
                  controller: controller,
                  sourceId: input.identity.sourceId,
                  index: entry.index,
                  cacheKey: entry.cacheKey,
                  url: entry.url,
                  child: image,
                ),
        ),
      ],
    );
  }

  @override
  void didUpdateWidget(covariant _ImageFragmentSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.binding, widget.binding)) {
      oldWidget.binding.close();
    }
  }

  @override
  void dispose() {
    widget.binding.close();
    super.dispose();
  }
}

/// Retire gesture geometry without remounting/releasing the borrowed body.
final class _TextLongPressSurface extends StatefulWidget {
  const _TextLongPressSurface({
    required this.identity,
    required this.onLongPress,
    required this.child,
  });
  final Object identity;
  final ValueChanged<Offset>? onLongPress;
  final Widget child;
  @override
  State<_TextLongPressSurface> createState() => _TextLongPressSurfaceState();
}

final class _TextLongPressSurfaceState extends State<_TextLongPressSurface> {
  late LongPressGestureRecognizer _press;
  void _bind() {
    _press = LongPressGestureRecognizer()
      ..onLongPressStart = (details) {
        if (mounted) widget.onLongPress?.call(details.localPosition);
      };
  }

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant _TextLongPressSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        (oldWidget.onLongPress == null) != (widget.onLongPress == null)) {
      _press.dispose();
      _bind();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: widget.onLongPress == null ? null : _press.addPointer,
    child: widget.child,
  );
  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }
}

bool _hasRubyBackground(ForumBodyPreparedTextFragment delivery) {
  final body = delivery is ForumBodyPreparedListItemFragment
      ? delivery.body
      : delivery;
  return body is ForumBodyPreparedInlineFragment &&
      body.view.isActive &&
      body.view.containerBackgrounds.isNotEmpty;
}

final class _ListMarkerSurface extends StatefulWidget {
  const _ListMarkerSurface(this.binding);
  final ForumBodyPreparedListItemFragment binding;
  @override
  State<_ListMarkerSurface> createState() => _ListMarkerSurfaceState();
}

final class _ListMarkerSurfaceState extends State<_ListMarkerSurface> {
  @override
  void didUpdateWidget(covariant _ListMarkerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.binding.picture, widget.binding.picture)) {
      oldWidget.binding.picture.release();
    }
  }

  @override
  void dispose() {
    widget.binding.picture.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ListMarkerPainter(widget.binding));
}

final class _ListMarkerPainter extends CustomPainter {
  const _ListMarkerPainter(this.binding);
  final ForumBodyPreparedListItemFragment binding;
  @override
  void paint(Canvas canvas, Size size) {
    if (binding.isActive) {
      binding.picture.paint(canvas, Offset(0, binding.placement.baseline));
    }
  }

  @override
  bool shouldRepaint(covariant _ListMarkerPainter oldDelegate) =>
      !identical(binding, oldDelegate.binding);
}

final class _BlockBackgroundPainter extends CustomPainter {
  const _BlockBackgroundPainter(this.backgrounds);
  final List<ForumBodyTextPageBackground> backgrounds;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    try {
      canvas.clipRect(Offset.zero & size, doAntiAlias: false);
      final paint = Paint();
      for (final background in backgrounds) {
        paint.color = background.color;
        final rect = Rect.fromLTWH(
          background.left,
          background.top,
          background.width,
          background.height,
        );
        final quote = background.quoteDecoration;
        if (quote == null) {
          canvas.drawRect(rect, paint);
          continue;
        }
        // Continue the actual rounded shape outside the clipped slice. Drawing
        // a tiny RRect for a short page tail would compress its corner radius.
        const radius = ForumBodyQuoteDecoration.radius * 1.0;
        final shape = Rect.fromLTRB(
          rect.left,
          background.startsBox ? rect.top : rect.top - radius * 2,
          rect.right,
          background.endsBox ? rect.bottom : rect.bottom + radius * 2,
        );
        final painter = BoxDecoration(
          color: background.color,
          border: Border(
            left: BorderSide(
              color: quote.borderColor,
              width: ForumBodyQuoteDecoration.borderWidth * 1.0,
            ),
          ),
          borderRadius: BorderRadius.circular(radius),
        ).createBoxPainter();
        canvas.save();
        try {
          canvas.clipRect(rect, doAntiAlias: false);
          painter.paint(
            canvas,
            shape.topLeft,
            ImageConfiguration(size: shape.size),
          );
        } finally {
          painter.dispose();
          canvas.restore();
        }
      }
    } finally {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BlockBackgroundPainter oldDelegate) =>
      !identical(backgrounds, oldDelegate.backgrounds);
}

final class _RulePainter extends CustomPainter {
  const _RulePainter(this.rules);
  final List<ForumBodyTextPageRule> rules;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    try {
      canvas.clipRect(Offset.zero & size, doAntiAlias: false);
      final paint = Paint();
      for (final rule in rules) {
        paint.color = rule.color;
        canvas.drawRect(
          Rect.fromLTWH(rule.left, rule.top, rule.width, rule.thickness),
          paint,
        );
      }
    } finally {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _RulePainter oldDelegate) =>
      !identical(rules, oldDelegate.rules);
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
      for (final (index, delivery) in bindings.indexed) {
        final binding = delivery is ForumBodyPreparedListItemFragment
            ? delivery.body
            : delivery;
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
