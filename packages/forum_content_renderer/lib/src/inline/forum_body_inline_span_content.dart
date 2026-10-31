import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_paint_text_style.dart';
import '../style/forum_body_style_options.dart';

/// Exact independently projected input retained for source-bound child binding.
/// These are display coordinates, never inferred from equal text or HTML.
final class ForumBodyInlineContext {
  const ForumBodyInlineContext._(this.content, this.startUtf16, this.endUtf16);
  final ForumBodyParagraphContent content;
  final int startUtf16;
  final int endUtf16;
}

/// Pure mixed-inline input: actual child display/source text and a separate
/// parent TextPainter span. Independent contexts must be collected together
/// before entering this port; ordinary style spans are not separate contexts.
///
/// Atom dimensions and paint/hit/selection stay with the parent's actual child
/// layouts. This value holds no native leases, widgets, DOM or measurement job.
final class ForumBodyInlineSpanContent {
  ForumBodyInlineSpanContent._({
    required this.identity,
    required this.path,
    required this.fontRevision,
    required this.styleRevision,
    required this.style,
    required this.projection,
    required List<ForumBodyInlineContext> contexts,
    required List<ForumBodyParagraphRun> runs,
  }) : contexts = List.unmodifiable(contexts),
       runs = List.unmodifiable(runs);

  static const revision = 2;

  factory ForumBodyInlineSpanContent.compose({
    required ForumBodyIdentity identity,
    required String? path,
    required String fontRevision,
    required int styleRevision,
    required ForumBodyResolvedStyle style,
    required List<ForumBodyParagraphContent> contexts,
    required List<({int startUtf16, int endUtf16})> atomicRanges,
    int maxInputCodeUnits = 16384,
    int maxRuns = 512,
    int maxContexts = 512,
    int maxAtoms = 512,
  }) {
    if (maxInputCodeUnits < 0 ||
        maxRuns < 0 ||
        maxContexts < 0 ||
        maxAtoms < 0) {
      throw ArgumentError('Invalid mixed inline input budget');
    }
    if (contexts.length > maxContexts) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.inputLimit,
        path,
      );
    }
    final segments = <HtmlDisplayTextSegment>[];
    final retainedContexts = <ForumBodyInlineContext>[];
    final runs = <ForumBodyParagraphRun>[];
    var inputLength = 0;
    for (final context in contexts) {
      if (context.identity != identity ||
          context.fontRevision != fontRevision ||
          context.styleRevision != styleRevision) {
        throw ForumBodyParagraphInputException(
          ForumBodyParagraphInputFailure.identity,
          context.path,
        );
      }
      final start = inputLength;
      inputLength += context.projection.text.length;
      if (inputLength > maxInputCodeUnits) {
        throw ForumBodyParagraphInputException(
          ForumBodyParagraphInputFailure.inputLimit,
          path,
        );
      }
      if (runs.length + context.runs.length > maxRuns) {
        throw ForumBodyParagraphInputException(
          ForumBodyParagraphInputFailure.runLimit,
          path,
        );
      }
      segments.add(
        HtmlDisplayTextSegment(context.projection, runIndexOffset: runs.length),
      );
      retainedContexts.add(
        ForumBodyInlineContext._(context, start, inputLength),
      );
      runs.addAll(context.runs);
    }
    final display = HtmlDisplayTextProjection.concatenate(
      segments,
      maxOutputCodeUnits: maxInputCodeUnits,
      maxSegments: maxContexts,
    );
    return ForumBodyInlineSpanContent._(
      identity: identity,
      path: path,
      fontRevision: fontRevision,
      styleRevision: styleRevision,
      style: style,
      contexts: retainedContexts,
      projection: HtmlInlineTextProjection.build(
        display: display,
        atomicRanges: atomicRanges,
        maxAtoms: maxAtoms,
        maxDisplayCodeUnits: maxInputCodeUnits,
        maxEngineCodeUnits: maxInputCodeUnits,
      ),
      runs: runs,
    );
  }

  final ForumBodyIdentity identity;
  final String? path;
  final String fontRevision;
  final int styleRevision;
  final ForumBodyResolvedStyle style;
  final HtmlInlineTextProjection projection;
  final List<ForumBodyParagraphRun> runs;
  final List<ForumBodyInlineContext> contexts;

  /// Direct TextPainter input only. Set its placeholder dimensions in atom
  /// order, using the already-scaled child geometry. RichText/WidgetSpan scale
  /// extraction is intentionally outside this native span contract.
  late final TextSpan textSpan = _parentInput.span;

  /// Only runs actually shaped by the parent. Atomic children retain their
  /// own direction and per-size scaling; those inputs must not be validated or
  /// rescaled as ordinary parent text.
  late final List<ForumBodyParagraphRun> parentRuns = _parentInput.runs;
  late final _parentInput = _buildTextSpan();

  void validateDimensions(List<PlaceholderDimensions> dimensions) {
    if (dimensions.length != projection.atoms.length) {
      throw ArgumentError('Native inline dimensions do not match atoms');
    }
    for (final dimension in dimensions) {
      _validateDimension(dimension);
    }
  }

  ({TextSpan span, List<ForumBodyParagraphRun> runs}) _buildTextSpan() {
    final children = <InlineSpan>[];
    final parentRunIndices = <int>{};
    final parts = projection.display.parts;
    final atoms = projection.atoms;
    var partIndex = 0;
    var atomIndex = 0;
    var cursor = 0;
    while (cursor < projection.display.text.length) {
      if (atomIndex < atoms.length &&
          cursor == atoms[atomIndex].displayStartUtf16) {
        children.add(const _NativeInlinePlaceholder());
        cursor = atoms[atomIndex++].displayEndUtf16;
        continue;
      }
      while (partIndex < parts.length &&
          parts[partIndex].utf16Start + parts[partIndex].text.length <=
              cursor) {
        partIndex++;
      }
      final part = parts[partIndex];
      parentRunIndices.add(part.runIndex);
      final partEnd = part.utf16Start + part.text.length;
      final end =
          atomIndex < atoms.length &&
              atoms[atomIndex].displayStartUtf16 < partEnd
          ? atoms[atomIndex].displayStartUtf16
          : partEnd;
      children.add(
        TextSpan(
          text: part.text.substring(
            cursor - part.utf16Start,
            end - part.utf16Start,
          ),
          style: forumBodyPaintTextStyle(runs[part.runIndex].style),
        ),
      );
      cursor = end;
    }
    return (
      span: TextSpan(
        style: style.textStyle,
        children: List.unmodifiable(children),
      ),
      runs: List.unmodifiable(parentRunIndices.map((index) => runs[index])),
    );
  }
}

/// A native paragraph placeholder has no Widget subtree or gesture recognizer.
/// Its only payload is supplied separately via TextPainter dimensions; geometry
/// is already scaled by the child's own font sizes and TextScaler.
final class _NativeInlinePlaceholder extends PlaceholderSpan {
  const _NativeInlinePlaceholder()
    : super(
        alignment: ui.PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
      );

  @override
  void build(
    ui.ParagraphBuilder builder, {
    TextScaler textScaler = TextScaler.noScaling,
    List<PlaceholderDimensions>? dimensions,
  }) {
    if (dimensions == null || builder.placeholderCount >= dimensions.length) {
      throw StateError('Native inline placeholder dimensions are missing');
    }
    final dimension = dimensions[builder.placeholderCount];
    _validateDimension(dimension);
    builder.addPlaceholder(
      dimension.size.width,
      dimension.size.height,
      alignment,
      baseline: baseline,
      baselineOffset: dimension.baselineOffset,
    );
  }

  @override
  bool visitChildren(InlineSpanVisitor visitor) => visitor(this);
  @override
  bool visitDirectChildren(InlineSpanVisitor visitor) => true;
  @override
  InlineSpan? getSpanForPositionVisitor(
    TextPosition position,
    Accumulator offset,
  ) {
    if (position.offset == offset.value) return this;
    offset.increment(1);
    return null;
  }

  @override
  int? codeUnitAtVisitor(int index, Accumulator offset) {
    final local = index - offset.value;
    offset.increment(1);
    return local == 0 ? PlaceholderSpan.placeholderCodeUnit : null;
  }

  @override
  RenderComparison compareTo(InlineSpan other) =>
      other is _NativeInlinePlaceholder
      ? RenderComparison.identical
      : RenderComparison.layout;
  @override
  bool debugAssertIsValid() => true;
}

void _validateDimension(PlaceholderDimensions dimension) {
  if (dimension.alignment != ui.PlaceholderAlignment.baseline ||
      dimension.baseline != TextBaseline.alphabetic ||
      !dimension.size.width.isFinite ||
      !dimension.size.height.isFinite ||
      dimension.size.width < 0 ||
      dimension.size.height <= 0 ||
      dimension.size.width > 16384 ||
      dimension.size.height > 16384 ||
      dimension.baselineOffset == null ||
      !dimension.baselineOffset!.isFinite ||
      dimension.baselineOffset! < 0 ||
      dimension.baselineOffset! > dimension.size.height) {
    throw ArgumentError('Invalid native inline placeholder geometry');
  }
}
