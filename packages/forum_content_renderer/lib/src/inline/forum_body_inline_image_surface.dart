part of 'forum_body_inline_paragraph_surface.dart';

/// Takes one fully prepared mixed line view. Each mounted surface needs its
/// own parent/child handles; abandoned unmounted widgets remain caller-owned.
final class ForumBodyInlineImageSurface extends StatefulWidget {
  const ForumBodyInlineImageSurface({
    super.key,
    required this.view,
    this.onSourceTap,
    this.interactionIdentity,
    this.paintBackgrounds = true,
    this.excludeTextSemantics = false,
    this.imageHost,
    this.imageAnchorController,
    this.onImageDisplayChanged,
    this.onImageLayoutResolved,
    this.onImageTap,
  });
  final ForumBodyInlineParagraphView view;
  final void Function(HtmlProjectedSourcePosition)? onSourceTap;
  final Object? interactionIdentity;
  final bool paintBackgrounds;

  /// A page with its own text semantics still uses the real image semantics.
  final bool excludeTextSemantics;
  final ForumHtmlImageHost? imageHost;
  final ForumHtmlImageAnchorController? imageAnchorController;
  final void Function(ForumBodyInlineImageBinding, bool)? onImageDisplayChanged;
  final void Function(ForumBodyInlineImageBinding, ForumHtmlImageLayout)?
  onImageLayoutResolved;
  final ValueChanged<ForumBodyInlineImageBinding>? onImageTap;
  @override
  State<ForumBodyInlineImageSurface> createState() => _InlineSurfaceState();
}

final class _InlineSurfaceState extends State<ForumBodyInlineImageSurface> {
  var _displayRevision = 0;
  var _tapRevision = 0;
  @override
  void didUpdateWidget(covariant ForumBodyInlineImageSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.view, widget.view) ||
        !identical(oldWidget.imageHost, widget.imageHost) ||
        oldWidget.interactionIdentity != widget.interactionIdentity) {
      _tapRevision++;
    }
    if (!identical(oldWidget.view, widget.view) ||
        !identical(oldWidget.imageHost, widget.imageHost)) {
      _displayRevision++;
      _clearFrames(
        oldWidget.view,
        notify: identical(oldWidget.view, widget.view),
      );
    }
  }

  void _clearFrames(ForumBodyInlineParagraphView view, {bool notify = false}) {
    if (!view.isActive) return;
    for (final binding in view.images.values) {
      if (binding.reportDisplayFrame(false) && notify) {
        widget.onImageDisplayChanged?.call(binding, false);
      }
    }
  }

  bool _accept(
    ForumBodyInlineImageBinding binding,
    int revision,
    ForumBodyInlineParagraphView view,
    ForumHtmlImageHost host,
  ) =>
      mounted &&
      revision == _displayRevision &&
      identical(widget.view, view) &&
      identical(widget.imageHost, host) &&
      view.isActive &&
      binding.isActive &&
      identical(view.images[binding.atomIndex], binding);

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final bindings = view.images;
    final text = ExcludeSemantics(
      excluding: widget.excludeTextSemantics,
      child: ForumBodyInlineParagraphSurface._imageTextLayer(
        view: view,
        onSourceTap: widget.onSourceTap,
        interactionIdentity: widget.interactionIdentity,
        paintBackgrounds: widget.paintBackgrounds,
      ),
    );
    if (bindings.isEmpty) return text;
    final host = widget.imageHost;
    if (host == null) {
      throw const ForumBodyInlineViewException(
        ForumBodyInlineViewFailure.leases,
      );
    }
    final displays = <ForumBodyInlineImageBinding, ForumHtmlDisplayImage>{};
    for (final binding in bindings.values) {
      final input = binding.input, expected = binding.input.image;
      final uri = Uri.tryParse(expected.sourceUrl);
      final display = uri == null
          ? null
          : host.resolveImage(
              url: uri,
              imageIndex: input.entry?.index,
              isSticker: expected.isSticker,
              htmlSize: expected.htmlSize,
            );
      if (display == null ||
          display.sourceUrl != expected.sourceUrl ||
          display.cacheKey != expected.cacheKey ||
          display.isSticker != expected.isSticker ||
          display.htmlSize != expected.htmlSize) {
        throw const ForumBodyInlineViewException(
          ForumBodyInlineViewFailure.identity,
        );
      }
      displays[binding] = display;
    }
    final revision = _displayRevision;
    return SizedBox(
      width: view.width,
      height: view.height,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(child: text),
          for (final entry in displays.entries)
            Positioned.fromRect(
              key: ObjectKey(entry.key),
              rect: entry.key.rect,
              child: _image(entry.key, entry.value, revision, view, host),
            ),
        ],
      ),
    );
  }

  Widget _image(
    ForumBodyInlineImageBinding binding,
    ForumHtmlDisplayImage display,
    int revision,
    ForumBodyInlineParagraphView view,
    ForumHtmlImageHost host,
  ) {
    final tapRevision = _tapRevision;
    final tap = widget.onImageTap == null || binding.input.entry == null
        ? null
        : () {
            if (_tapRevision == tapRevision &&
                _accept(binding, revision, view, host)) {
              widget.onImageTap?.call(binding);
            }
          };
    final reference = binding.input.element.resource!;
    final surface = Semantics(
      image: true,
      label: reference.alt ?? reference.title ?? '',
      onTap: tap,
      child: ExcludeSemantics(
        child: _InlineImageTapSurface(
          identity: (binding, tapRevision),
          onTap: tap,
          child: ForumHtmlImageView(
            host: host,
            image: display,
            fit: BoxFit.contain,
            initialInlineSize: binding.rect.size,
            onImageDisplayChanged: (rendered) {
              if (_accept(binding, revision, view, host) &&
                  binding.reportDisplayFrame(rendered)) {
                widget.onImageDisplayChanged?.call(binding, rendered);
              }
            },
            onImageLayoutResolved: (layout) {
              if (_accept(binding, revision, view, host)) {
                widget.onImageLayoutResolved?.call(binding, layout);
              }
            },
          ),
        ),
      ),
    );
    final controller = widget.imageAnchorController;
    final entry = binding.input.entry;
    if (controller == null || entry == null) return surface;
    return ForumHtmlImageAnchor(
      key: ValueKey((
        'native-readable-image',
        binding.input.identity.sourceId,
        entry.index,
      )),
      controller: controller,
      sourceId: binding.input.identity.sourceId,
      index: entry.index,
      cacheKey: entry.cacheKey,
      url: entry.url,
      child: surface,
    );
  }

  @override
  void dispose() {
    _displayRevision++;
    _clearFrames(widget.view);
    super.dispose();
  }
}

/// Retire an in-flight tap without remounting the decoded image subtree.
final class _InlineImageTapSurface extends StatefulWidget {
  const _InlineImageTapSurface({
    required this.identity,
    required this.child,
    this.onTap,
  });
  final Object identity;
  final Widget child;
  final VoidCallback? onTap;
  @override
  State<_InlineImageTapSurface> createState() => _InlineImageTapState();
}

final class _InlineImageTapState extends State<_InlineImageTapSurface> {
  late TapGestureRecognizer _tap;
  void _bind() {
    _tap = TapGestureRecognizer()
      ..onTap = () {
        if (mounted) widget.onTap?.call();
      };
  }

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant _InlineImageTapSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _tap.dispose();
      _bind();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (event) {
      if (widget.onTap != null) _tap.addPointer(event);
    },
    child: widget.child,
  );
  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }
}
