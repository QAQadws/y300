part of 'forum_body_continuous.dart';

List<Widget> _continuousImages(ForumBodyContinuous input) {
  if (input.document.imageElements.isEmpty) return const [];
  final collapses = ForumBodyCollapseLayout(
    input.document,
    expansionOverrides: input.expansion,
  );
  final children = <Widget>[];
  for (final element in input.document.imageElements) {
    final root = input.contentRoot;
    if (root != null && !element.path.startsWith('${root.path}/')) continue;
    if (collapses.hidesPath(element.path)) continue;
    final ancestors = input.document.ancestryOf(element)!;
    final local = root == null
        ? ancestors
        : ancestors.skipWhile((node) => !identical(node, root)).skip(1);
    // Dedicated format handlers own their descendants. Do not mount resources
    // from an unsupported table/ruby as a side effect of a failed comparison.
    if (local.any(
      (node) =>
          node.kind == ForumBodyElementKind.table ||
          node.kind == ForumBodyElementKind.ruby,
    )) {
      continue;
    }
    final styles = const ForumBodyStyleResolver().open(
      input.document,
      input.reader,
      collapses: collapses,
      contentRoot: element,
    );
    final ForumBodyResolvedStyle style;
    try {
      style = styles.root;
    } finally {
      styles.close();
    }
    if (style.hidden) continue;
    final source = style.visibilityHidden
        ? ForumBodyInlineImageSource.hidden(
            document: input.document,
            element: element,
          )
        : input.imageSources[element.path];
    if (source == null ||
        source.identity != input.document.identity ||
        !identical(source.element, element) ||
        (!style.visibilityHidden &&
            (source.isHidden || input.imageHost == null))) {
      throw ForumBodyContinuousUnsupported('image-resource', element.path);
    }
    if ((!source.isHidden && source.image.isSticker) ||
        const {
          'inline',
          'inline-block',
        }.contains(element.style.value('display')?.trim().toLowerCase())) {
      throw ForumBodyContinuousUnsupported('inline-image', element.path);
    }
    children.add(
      _ResourceSlot(
        key: ValueKey((input.document.identity, element.path)),
        path: element.path,
        child: _ContinuousImage(
          source: source,
          style: style,
          host: input.imageHost,
          preferNaturalWidth: root != null,
          onTap: input.onImageTap,
        ),
      ),
    );
  }
  return children;
}

/// Resource state stays in the existing image view. This adapter only resolves
/// its continuous replaced-element box at the actual containing width.
final class _ContinuousImage extends StatefulWidget {
  const _ContinuousImage({
    required this.source,
    required this.style,
    required this.host,
    required this.preferNaturalWidth,
    required this.onTap,
  });
  final ForumBodyInlineImageSource source;
  final ForumBodyResolvedStyle style;
  final ForumHtmlImageHost? host;
  final bool preferNaturalWidth;
  final ValueChanged<ForumBodyInlineImageSource>? onTap;
  @override
  State<_ContinuousImage> createState() => _ContinuousImageState();
}

final class _ContinuousImageState extends State<_ContinuousImage> {
  ForumHtmlImageLayout? _layout;
  @override
  void didUpdateWidget(_ContinuousImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.host, widget.host) ||
        oldWidget.source.isHidden != widget.source.isHidden ||
        (!widget.source.isHidden &&
            oldWidget.source.image.identity != widget.source.image.identity)) {
      _layout = null;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final source = widget.source, host = widget.host;
      final style = widget.style;
      final image = source.isHidden ? null : source.image;
      final layout = _layout ?? image?.initialLayout;
      final reference = source.element.resource!;
      final intrinsic = layout?.displaySize ?? image?.htmlSize;
      final ratio =
          layout?.aspectRatio ??
          intrinsic?.aspectRatio ??
          (reference.width != null && reference.height != null
              ? reference.width! / reference.height!
              : .7);
      final cssWidth = style.box.width;
      final automaticWidth =
          cssWidth == null || cssWidth.unit == ForumBodyLengthUnit.auto;
      // BlockFlowCursor already resolved CSS width/min/max and padding once.
      // Re-applying a percentage here would shrink the image a second time.
      final width = automaticWidth && widget.preferNaturalWidth
          ? math.min(
              constraints.maxWidth,
              reference.width ?? intrinsic?.width ?? style.textStyle.fontSize!,
            )
          : constraints.maxWidth;
      final size = constraints.maxHeight == 0
          ? Size(width, 0)
          : fitForumBodyReplacedImage(
              intrinsicWidth: width,
              aspectRatio: ratio,
              width: width,
              height: constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : null,
              minWidth: 0,
              maxWidth: null,
              availableWidth: constraints.maxWidth,
              // Continuous content has no page-height cap, including long images.
              availableHeight: constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : double.maxFinite,
            );
      final child = image == null
          ? const SizedBox.shrink()
          : Semantics(
              image: true,
              label: reference.alt ?? '',
              button: widget.onTap != null,
              child: GestureDetector(
                key: ValueKey((
                  source.identity,
                  source.element.path,
                  host,
                  image.identity,
                )),
                onTap: widget.onTap == null
                    ? null
                    : () => widget.onTap!(widget.source),
                child: ExcludeSemantics(
                  child: ForumHtmlImageView(
                    host: host!,
                    image: image,
                    fit: BoxFit.fill,
                    initialInlineSize: Size.square(style.textStyle.fontSize!),
                    onImageLayoutResolved: (value) {
                      if (!mounted ||
                          !identical(widget.source, source) ||
                          !identical(widget.host, host) ||
                          _layout == value) {
                        return;
                      }
                      setState(() => _layout = value);
                    },
                  ),
                ),
              ),
            );
      final x = switch ((style.textAlign, style.textDirection)) {
        (TextAlign.center, _) => 0.0,
        (TextAlign.right, _) ||
        (TextAlign.end, TextDirection.ltr) ||
        (TextAlign.start || TextAlign.justify, TextDirection.rtl) => 1.0,
        _ => -1.0,
      };
      return Align(
        alignment: Alignment(x, -1),
        heightFactor: 1,
        child: SizedBox.fromSize(size: size, child: child),
      );
    },
  );
}
