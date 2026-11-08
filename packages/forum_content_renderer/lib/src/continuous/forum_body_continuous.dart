import 'dart:math' as math;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:forum_content_renderer/forum_text.dart';

import '../block/forum_body_block_flow_cursor.dart';
import '../block/forum_body_block_box.dart';
import '../contracts/forum_html_image_host.dart';
import '../document/forum_body_collapse_layout.dart';
import '../document/forum_body_document.dart';
import '../flow/forum_body_text_flow_cursor.dart';
import '../inline/forum_body_inline_image_input.dart';
import '../inline/forum_body_native_space_span.dart';
import '../paragraph/forum_body_first_line_indent.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_layout.dart'
    show ForumBodyParagraphLayout, ForumBodyParagraphWindow;
import '../style/forum_body_paint_text_style.dart';
import '../style/forum_body_style_options.dart';
import '../style/forum_body_style_resolver.dart';
import '../style/forum_body_length.dart';
import '../style/forum_body_box_style.dart';
import '../style/forum_body_replaced_image_size.dart';
import '../html_rendering/widgets/forum_html_image_view.dart';
import '../contracts/forum_html_display_image.dart';

part 'forum_body_continuous_images.dart';
part 'forum_body_continuous_paint.dart';

/// Unsupported experiment input must remain visible to its developer host;
/// silently flattening it would make a performance comparison misleading.
final class ForumBodyContinuousUnsupported implements Exception {
  const ForumBodyContinuousUnsupported(this.kind, this.path);
  final String kind;
  final String? path;
  @override
  String toString() => 'ForumBodyContinuousUnsupported($kind, $path)';
}

final class ForumBodyContinuousHit {
  const ForumBodyContinuousHit(
    this.identity,
    this.path,
    this.source,
    this.link,
  );
  final ForumBodyIdentity identity;
  final String path;
  final HtmlProjectedSourcePosition source;
  final String? link;
}

/// Borrows only one attached view's actual layout; it owns no cache or session.
final class ForumBodyContinuousController {
  _ContinuousBox? _view;
  bool get isReady => _view?.attached == true && _view!._ready;
  Size? get size => isReady ? _view!.size : null;
  String? get copyText => isReady ? _view!._copyText : null;
  int get layoutCount => _view?._layoutCount ?? 0;

  /// Cumulative TextPainter allocations, including outside list markers.
  int get textPainterCreationCount => _view?._textPainterCreationCount ?? 0;
  int get paragraphCount => isReady ? _view!._texts.length : 0;
  ForumBodyContinuousHit? hitTest(Offset point) =>
      isReady ? _view!._hit(point) : null;

  void _bind(_ContinuousBox view) {
    if (_view != null && !identical(_view, view)) {
      throw StateError('Continuous controller already has a view');
    }
    _view = view;
  }

  void _unbind(_ContinuousBox view) {
    if (identical(_view, view)) _view = null;
  }
}

/// A bounded prototype of normal continuous text flow. Native text is shaped
/// during performLayout and painted by that same TextPainter. There is no page
/// composer, precomputed geometry phase, preparation job, lease or frame queue.
/// Resource children participate in that layout through the existing image Host.
/// Mixed formats are never delegated to pagination.
final class ForumBodyContinuous extends StatelessWidget {
  const ForumBodyContinuous({
    super.key,
    required this.document,
    required this.reader,
    this.textScaler = TextScaler.noScaling,
    this.controller,
    this.onTap,
    this.expansion = const {},
    this.contentRoot,
    this.imageSources = const {},
    this.imageHost,
    this.onImageTap,
  });

  final ForumBodyDocument document;
  final ForumBodyReaderStyle reader;
  final TextScaler textScaler;
  final ForumBodyContinuousController? controller;
  final ValueChanged<ForumBodyContinuousHit>? onTap;
  final Map<String, bool> expansion;
  final ForumBodyElement? contentRoot;
  final Map<String, ForumBodyInlineImageSource> imageSources;
  final ForumHtmlImageHost? imageHost;
  final ValueChanged<ForumBodyInlineImageSource>? onImageTap;

  @override
  Widget build(BuildContext context) =>
      _ContinuousSurface(input: this, children: _continuousImages(this));
}

final class _ContinuousSurface extends MultiChildRenderObjectWidget {
  const _ContinuousSurface({required this.input, required super.children});
  final ForumBodyContinuous input;

  @override
  RenderBox createRenderObject(BuildContext context) => _ContinuousBox(input);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderBox renderObject,
  ) => (renderObject as _ContinuousBox).configure(input);
}

Object _readerKey(ForumBodyReaderStyle reader) => (
  reader.textStyle,
  reader.fontRevision,
  reader.linkColor,
  reader.textAlign,
  reader.textDirection,
  reader.paragraphBefore,
  reader.paragraphAfter,
  reader.firstLineIndent,
  reader.compressBlankLines,
  reader.removeSourceIndent,
  reader.roleFontScales,
  reader.rubyFontScale,
  reader.showRubyAnnotations,
  reader.theme?.signature,
);

final class _ContinuousBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ContinuousParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ContinuousParentData> {
  _ContinuousBox(ForumBodyContinuous input)
    : _input = input,
      _expansion = Map.of(input.expansion);
  ForumBodyContinuous _input;
  Map<String, bool> _expansion;
  final _painters = <TextPainter>[];
  final _texts = <_Text>[];
  final _paints = <_Paint>[];
  final _textLayouts = <int, _Text>{};
  final _markerLayouts = <String, TextPainter>{};
  bool _ready = false;
  bool _layoutDirty = true;
  double? _layoutWidth;
  int _layoutCount = 0;
  int _textPainterCreationCount = 0;
  String _copyText = '';
  TapGestureRecognizer? _tap;

  void configure(ForumBodyContinuous input) {
    final changed =
        !identical(input.document, _input.document) ||
        !identical(input.contentRoot, _input.contentRoot) ||
        _readerKey(input.reader) != _readerKey(_input.reader) ||
        !mapEquals(input.reader.policy.values, _input.reader.policy.values) ||
        input.textScaler != _input.textScaler ||
        !mapEquals(input.expansion, _expansion);
    if (!identical(_input.controller, input.controller)) {
      _input.controller?._unbind(this);
      if (attached) input.controller?._bind(this);
    }
    _input = input;
    if (changed) {
      _expansion = Map.of(input.expansion);
      _ready = false;
      _layoutDirty = true;
      _retireTap();
      markNeedsLayout();
      markNeedsSemanticsUpdate();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _input.controller?._bind(this);
  }

  @override
  void detach() {
    _input.controller?._unbind(this);
    _retireTap();
    super.detach();
  }

  @override
  void dispose() {
    _input.controller?._unbind(this);
    _clear();
    super.dispose();
  }

  void _clear({bool discardText = true}) {
    _retireTap();
    _ready = false;
    if (discardText) {
      for (final painter in _painters) {
        painter.dispose();
      }
      _painters.clear();
      _textLayouts.clear();
      _markerLayouts.clear();
    }
    _texts.clear();
    _paints.clear();
    _copyText = '';
  }

  void _retireTap() {
    _tap?.dispose();
    _tap = null;
  }

  TextPainter _text(InlineSpan span, ForumBodyResolvedStyle style) {
    _textPainterCreationCount++;
    final painter = TextPainter(
      text: span,
      textAlign: style.textAlign,
      textDirection: style.textDirection,
      textScaler: _input.textScaler,
      locale: style.textStyle.locale,
    );
    _painters.add(painter);
    return painter;
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    _clear(discardText: _layoutDirty || _layoutWidth != width);
    _layoutCount++;
    if (!width.isFinite || width <= 0) {
      throw ArgumentError('Continuous body requires a finite positive width');
    }
    final collapses = ForumBodyCollapseLayout(
      _input.document,
      expansionOverrides: _expansion,
    );
    final flow = ForumBodyBlockFlowCursor(
      document: _input.document,
      reader: _input.reader,
      width: width,
      collapses: collapses,
      contentRoot: _input.contentRoot,
      dedicatedTables: true,
      allowReplacedImageHeight: true,
      paragraphBuilder: const ForumBodyParagraphContentBuilder(
        maxInputCodeUnits: 65536,
        maxRuns: 2048,
      ),
    );
    final open = <_Background>[];
    final markers = <String, TextPainter>{};
    final imageBoxes = <String, ForumBodyBlockBox>{};
    final resources = <String, RenderBox>{};
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _ContinuousParentData;
      resources[data.path] = child;
      child = data.nextSibling;
    }
    final copied = StringBuffer();
    var endsWithNewline = false;
    String? previousPath;
    var y = 0.0;
    void startBoxes() {
      for (final box in open) {
        box.top ??= y;
      }
    }

    void placeMarkers(List<ForumBodyListItemMarker> items, double baseline) {
      for (final marker in items) {
        final font = markers.remove(marker.itemPath);
        if (font == null) continue;
        final left = marker.style.textDirection == TextDirection.ltr
            ? marker.contentLeft - font.height * .25 - font.width
            : marker.contentLeft + marker.contentWidth + font.height * .25;
        _paints.add(
          _Label(
            font,
            Offset(
              left,
              y +
                  baseline -
                  font.computeDistanceToActualBaseline(TextBaseline.alphabetic),
            ),
          ),
        );
      }
    }

    try {
      while (!flow.isComplete) {
        flow.advance(maxEvents: 1024);
        final unit = flow.current;
        switch (unit) {
          case null:
            break;
          case ForumBodyBlockFlowListItemStart():
            if (unit.marker.style.listStyle.position ==
                ForumBodyListMarkerPosition.inside) {
              throw ForumBodyContinuousUnsupported(
                'inside-list-marker',
                unit.marker.itemPath,
              );
            }
            final label = unit.marker.text;
            if (label == null) {
              flow.resolveListItemGutter(unit, 0);
              break;
            }
            final painter = _markerLayouts[unit.marker.itemPath] ??= _text(
              TextSpan(
                text: label,
                style: forumBodyPaintTextStyle(unit.marker.style),
              ),
              unit.marker.style,
            );
            painter.layout();
            markers[unit.marker.itemPath] = painter;
            flow.resolveListItemGutter(
              unit,
              painter.width + painter.height * .25,
            );
          case ForumBodyBlockFlowSpace():
            if (unit.kind != ForumBodyBlockSpaceKind.collapsedMargin) {
              startBoxes();
            }
            y += unit.extent;
          case ForumBodyBlockFlowBoundary():
            if (unit.collapseTitle != null) {
              throw ForumBodyContinuousUnsupported(
                'collapse',
                unit.boundary.event?.node.path,
              );
            }
            switch (unit.boundary.kind) {
              case ForumBodyTextFlowBoundaryKind.openBlock:
                final style = unit.boundary.event!.style;
                final box = unit.box!;
                if (unit.boundary.event!.node case ForumBodyElement(
                  kind: ForumBodyElementKind.image,
                )) {
                  imageBoxes[unit.boundary.event!.node.path] = box;
                }
                final background = _Background(
                  unit.contentLeft - box.padding.left - box.leftBorder,
                  box.borderBoxWidth,
                  style.visibilityHidden ? null : style.boxBackground,
                  style.visibilityHidden ? null : style.quoteDecoration,
                );
                open.add(background);
                _paints.add(background);
              case ForumBodyTextFlowBoundaryKind.closeBlock:
                final box = open.removeLast();
                box.bottom = y;
              case ForumBodyTextFlowBoundaryKind.endDocument:
                break;
            }
          case ForumBodyBlockFlowParagraph():
            startBoxes();
            final original = unit.paragraph.content;
            final cached = _textLayouts[unit.paragraph.index];
            final window = unit.paragraph.window;
            final end = original.projection.text.length;
            final content =
                cached?.content ??
                switch (window) {
                  ForumBodyParagraphWindow.full => original,
                  ForumBodyParagraphWindow.beforeTerminalEmptyLine =>
                    original.displayWindow(startUtf16: 0, endUtf16: end - 1),
                  ForumBodyParagraphWindow.terminalEmptyLine =>
                    original.displayWindow(startUtf16: end, endUtf16: end),
                };
            if (content.hasBaselineShift) {
              throw ForumBodyContinuousUnsupported(
                'baseline-shift',
                content.path,
              );
            }
            if (content.runs.any(
              (run) =>
                  run.style.textStyle.decorationStyle !=
                      TextDecorationStyle.solid &&
                  run.style.textStyle.decorationStyle != null,
            )) {
              throw ForumBodyContinuousUnsupported(
                'decoration-style',
                content.path,
              );
            }
            final available = unit.contentWidth;
            final scales = ForumBodyParagraphLayout.validateInputs(
              content: content,
              width: available,
              textScaler: _input.textScaler,
            );
            final inset = content.horizontalInset;
            final inner = available - 2 * inset;
            final indent = resolveForumBodyFirstLineIndent(
              content,
              inner,
              scales,
            );
            final span = indent == 0
                ? content.textSpan
                : TextSpan(
                    style: content.style.textStyle,
                    children: [
                      ForumBodyNativeSpaceSpan.nonBreaking(indent),
                      content.textSpan,
                    ],
                  );
            final painter = cached?.painter ?? _text(span, content.style);
            final fitted =
                content.layoutMode != ForumBodyParagraphLayoutMode.wrap;
            painter.layout(
              minWidth: fitted ? 0 : inner,
              maxWidth: fitted ? double.infinity : inner,
            );
            final scale = fitted && painter.width > inner
                ? inner / painter.width
                : 1.0;
            final text =
                cached ??
                _Text(
                  content,
                  painter,
                  Offset(unit.contentLeft + inset, y),
                  scale,
                  indent == 0 ? 0 : 2,
                );
            text.offset = Offset(unit.contentLeft + inset, y);
            _textLayouts[unit.paragraph.index] = text;
            _texts.add(text);
            _paints.add(text);
            final baseline =
                painter.computeDistanceToActualBaseline(
                  TextBaseline.alphabetic,
                ) *
                scale;
            placeMarkers(unit.listMarkers, baseline);
            y += painter.height * scale;
            if (window != ForumBodyParagraphWindow.terminalEmptyLine) {
              if (copied.isNotEmpty &&
                  previousPath != original.path &&
                  !endsWithNewline) {
                copied.write('\n');
                endsWithNewline = true;
              }
              for (final part in original.projection.parts) {
                if (!original.runs[part.runIndex].style.visibilityHidden &&
                    part.text.isNotEmpty) {
                  copied.write(part.text);
                  endsWithNewline = part.text.endsWith('\n');
                }
              }
              previousPath = original.path;
            }
          case ForumBodyBlockFlowRule():
            startBoxes();
            _paints.add(
              _Rule(
                Rect.fromLTWH(unit.left, y, unit.width, unit.thickness),
                unit.color,
              ),
            );
            y += unit.thickness;
          case ForumBodyBlockFlowImage():
            startBoxes();
            final resource = resources[unit.image.event.node.path];
            if (resource == null) {
              throw ForumBodyContinuousUnsupported(
                'image-resource',
                unit.image.event.node.path,
              );
            }
            final style = unit.image.event.style;
            final box = imageBoxes.remove(unit.image.event.node.path)!;
            final height = style.box.height;
            final contentHeight = height?.unit != ForumBodyLengthUnit.px
                ? null
                : math.max(
                    0.0,
                    height!.value -
                        (style.box.sizing == ForumBodyBoxSizing.borderBox
                            ? box.padding.vertical
                            : 0),
                  );
            resource.layout(
              BoxConstraints.tightFor(
                width: unit.contentWidth,
                height: contentHeight,
              ),
              parentUsesSize: true,
            );
            final data = resource.parentData! as _ContinuousParentData;
            data.offset = Offset(unit.contentLeft, y);
            _paints.add(_Child(resource));
            placeMarkers(unit.listMarkers, resource.size.height);
            y += resource.size.height;
          case ForumBodyBlockFlowTable():
            throw ForumBodyContinuousUnsupported(
              'table',
              unit.table.element.path,
            );
          case ForumBodyBlockFlowInline():
            throw ForumBodyContinuousUnsupported(
              'mixed-inline',
              unit.paragraph.content.path,
            );
        }
      }
      if (!y.isFinite) throw StateError('Invalid continuous extent');
      size = constraints.constrain(Size(width, math.max(0, y)));
      _copyText = copied.toString();
      _ready = true;
      _layoutDirty = false;
      _layoutWidth = width;
      markNeedsSemanticsUpdate();
    } catch (_) {
      _clear();
      size = constraints.constrain(Size(width, 0));
      rethrow;
    } finally {
      flow.close();
    }
  }

  ForumBodyContinuousHit? _hit(Offset point) {
    if (!_ready) return null;
    for (final text in _texts.reversed) {
      final local = (point - text.offset) / text.scale;
      if (!(Offset.zero & text.painter.size).contains(local)) continue;
      final glyph = text.painter.getClosestGlyphForOffset(local);
      if (glyph == null || !glyph.graphemeClusterLayoutBounds.contains(local)) {
        continue;
      }
      final position = glyph.graphemeClusterCodeUnitRange.start;
      final display = position - text.prefix;
      if (display < 0 || display >= text.content.projection.text.length) {
        continue;
      }
      final part = text.content.projection.parts
          .where(
            (part) =>
                display >= part.utf16Start &&
                display < part.utf16Start + part.text.length,
          )
          .first;
      final run = text.content.runs[part.runIndex];
      if (run.style.visibilityHidden) return null;
      return ForumBodyContinuousHit(
        text.content.identity,
        run.path,
        text.content.projection.sourceAtUtf16(display),
        run.style.linkTarget,
      );
    }
    return null;
  }

  @override
  bool hitTestSelf(Offset position) => _ready;
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ContinuousParentData) {
      child.parentData = _ContinuousParentData();
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!_ready) return false;
    for (final record in _paints.reversed) {
      if (record is! _Child) continue;
      final child = record.child;
      final data = child.parentData! as _ContinuousParentData;
      if (result.addWithPaintOffset(
        offset: data.offset,
        position: position,
        hitTest: (result, local) => child.hitTest(result, position: local),
      )) {
        return true;
      }
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (!_ready) return;
    for (final record in _paints) {
      if (record is _Child) visitor(record.child);
    }
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      (_tap ??= TapGestureRecognizer()
            ..onTapUp = (details) {
              final hit = _hit(details.localPosition);
              if (hit != null) _input.onTap?.call(hit);
            })
          .addPointer(event);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_ready) return;
    final clip = context.canvas.getLocalClipBounds().shift(-offset);
    for (final record in _paints) {
      if (!record.bounds.overlaps(clip)) continue;
      if (record is _Child) {
        final data = record.child.parentData! as _ContinuousParentData;
        context.paintChild(record.child, offset + data.offset);
      } else if (record is _CanvasPaint) {
        // A child may create a composited layer, replacing context.canvas.
        final canvas = context.canvas;
        canvas.save();
        canvas.translate(offset.dx, offset.dy);
        record.paint(canvas);
        canvas.restore();
      }
    }
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
    config.textDirection = _input.reader.textDirection;
    config.label = _ready ? _copyText : '';
  }
}
