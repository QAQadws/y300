import 'dart:math' as math;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:forum_content_renderer/forum_text.dart';

import '../block/forum_body_block_flow_cursor.dart';
import '../document/forum_body_collapse_layout.dart';
import '../document/forum_body_document.dart';
import '../flow/forum_body_text_flow_cursor.dart';
import '../inline/forum_body_native_space_span.dart';
import '../paragraph/forum_body_first_line_indent.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_layout.dart'
    show ForumBodyParagraphLayout, ForumBodyParagraphWindow;
import '../style/forum_body_paint_text_style.dart';
import '../style/forum_body_style_options.dart';

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
/// Resource/mixed-format support is deliberately not delegated to pagination.
final class ForumBodyContinuous extends LeafRenderObjectWidget {
  const ForumBodyContinuous({
    super.key,
    required this.document,
    required this.reader,
    this.textScaler = TextScaler.noScaling,
    this.controller,
    this.onTap,
    this.expansion = const {},
    this.contentRoot,
  });

  final ForumBodyDocument document;
  final ForumBodyReaderStyle reader;
  final TextScaler textScaler;
  final ForumBodyContinuousController? controller;
  final ValueChanged<ForumBodyContinuousHit>? onTap;
  final Map<String, bool> expansion;
  final ForumBodyElement? contentRoot;

  @override
  RenderBox createRenderObject(BuildContext context) => _ContinuousBox(this);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderBox renderObject,
  ) => (renderObject as _ContinuousBox).configure(this);
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

final class _ContinuousBox extends RenderBox {
  _ContinuousBox(ForumBodyContinuous input)
    : _input = input,
      _expansion = Map.of(input.expansion);
  ForumBodyContinuous _input;
  Map<String, bool> _expansion;
  final _painters = <TextPainter>[];
  final _texts = <_Text>[];
  final _paints = <_Paint>[];
  bool _ready = false;
  int _layoutCount = 0;
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

  void _clear() {
    _retireTap();
    _ready = false;
    for (final painter in _painters) {
      painter.dispose();
    }
    _painters.clear();
    _texts.clear();
    _paints.clear();
    _copyText = '';
  }

  void _retireTap() {
    _tap?.dispose();
    _tap = null;
  }

  TextPainter _text(InlineSpan span, ForumBodyResolvedStyle style) {
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
    _clear();
    _layoutCount++;
    final width = constraints.maxWidth;
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
      paragraphBuilder: const ForumBodyParagraphContentBuilder(
        maxInputCodeUnits: 65536,
        maxRuns: 2048,
      ),
    );
    final open = <_Background>[];
    final markers = <String, TextPainter>{};
    final copied = StringBuffer();
    var endsWithNewline = false;
    String? previousPath;
    var y = 0.0;
    void startBoxes() {
      for (final box in open) {
        box.top ??= y;
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
            final painter = _text(
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
            final window = unit.paragraph.window;
            final end = original.projection.text.length;
            final content = switch (window) {
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
            final painter = _text(span, content.style);
            final fitted =
                content.layoutMode != ForumBodyParagraphLayoutMode.wrap;
            painter.layout(
              minWidth: fitted ? 0 : inner,
              maxWidth: fitted ? double.infinity : inner,
            );
            final scale = fitted && painter.width > inner
                ? inner / painter.width
                : 1.0;
            final text = _Text(
              content,
              painter,
              Offset(unit.contentLeft + inset, y),
              scale,
              indent == 0 ? 0 : 2,
            );
            _texts.add(text);
            _paints.add(text);
            final baseline =
                painter.computeDistanceToActualBaseline(
                  TextBaseline.alphabetic,
                ) *
                scale;
            for (final marker in unit.listMarkers) {
              final font = markers.remove(marker.itemPath);
              if (font == null) continue;
              final left = marker.style.textDirection == TextDirection.ltr
                  ? marker.contentLeft - font.height * .25 - font.width
                  : marker.contentLeft +
                        marker.contentWidth +
                        font.height * .25;
              _paints.add(
                _Label(
                  font,
                  Offset(
                    left,
                    y +
                        baseline -
                        font.computeDistanceToActualBaseline(
                          TextBaseline.alphabetic,
                        ),
                  ),
                ),
              );
            }
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
            throw ForumBodyContinuousUnsupported(
              'image',
              unit.image.event.node.path,
            );
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
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    final clip = canvas.getLocalClipBounds();
    for (final record in _paints) {
      if (record.bounds.overlaps(clip)) record.paint(canvas);
    }
    canvas.restore();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
    config.textDirection = _input.reader.textDirection;
    config.label = _ready ? _copyText : '';
  }
}

sealed class _Paint {
  Rect get bounds;
  void paint(Canvas canvas);
}

final class _Text implements _Paint {
  _Text(this.content, this.painter, this.offset, this.scale, this.prefix);
  final ForumBodyParagraphContent content;
  final TextPainter painter;
  final Offset offset;
  final double scale;
  final int prefix;
  @override
  Rect get bounds => offset & (painter.size * scale);
  @override
  void paint(Canvas canvas) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
  }
}

final class _Label implements _Paint {
  _Label(this.painter, this.offset);
  final TextPainter painter;
  final Offset offset;
  @override
  Rect get bounds => offset & painter.size;
  @override
  void paint(Canvas canvas) => painter.paint(canvas, offset);
}

final class _Rule implements _Paint {
  _Rule(this.bounds, this.color);
  @override
  final Rect bounds;
  final Color color;
  @override
  void paint(Canvas canvas) => canvas.drawRect(bounds, Paint()..color = color);
}

final class _Background implements _Paint {
  _Background(this.left, this.width, this.color, this.quote);
  final double left, width;
  final Color? color;
  final ForumBodyQuoteDecoration? quote;
  double? top, bottom;
  @override
  Rect get bounds => Rect.fromLTWH(
    left,
    top ?? 0,
    width,
    math.max(0, (bottom ?? top ?? 0) - (top ?? 0)),
  );
  @override
  void paint(Canvas canvas) {
    final rect = bounds;
    if (rect.isEmpty) return;
    final radius = quote == null
        ? Radius.zero
        : const Radius.circular(ForumBodyQuoteDecoration.radius * 1.0);
    if (color != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        Paint()..color = color!,
      );
    }
    if (quote != null) {
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left,
          rect.top,
          ForumBodyQuoteDecoration.borderWidth * 1.0,
          rect.height,
        ),
        Paint()..color = quote!.borderColor,
      );
    }
  }
}
