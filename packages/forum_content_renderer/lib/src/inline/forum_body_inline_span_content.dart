import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_paint_text_style.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_native_space_span.dart';

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
    required this.appliesFirstLineIndent,
  }) : contexts = List.unmodifiable(contexts),
       runs = List.unmodifiable(runs);

  static const revision = 8;

  factory ForumBodyInlineSpanContent.compose({
    required ForumBodyIdentity identity,
    required String? path,
    required String fontRevision,
    required int styleRevision,
    required ForumBodyResolvedStyle style,
    required List<ForumBodyParagraphContent> contexts,
    required List<({int startUtf16, int endUtf16})> atomicRanges,
    Set<int> softSpaceAtoms = const {},
    bool appliesFirstLineIndent = true,
    // Complete original-source ordering of the display contexts, when their
    // visual placement differs. The pure projection validates every range.
    List<int>? sourceOrder,
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
    final runIndices = Map<ForumBodyParagraphRun, int>.identity();
    var inputLength = 0;
    for (final context in contexts) {
      if (context.isSourceFree) {
        throw ForumBodyParagraphInputException(
          ForumBodyParagraphInputFailure.structure,
          context.path,
        );
      }
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
      final remap = <int, int>{};
      // Source windows share their original run objects. Retain only actual
      // ownership, without duplicating that table or merging equal styles.
      for (final part in context.projection.parts) {
        final run = context.runs[part.runIndex];
        final int index;
        if (runIndices.containsKey(run)) {
          index = runIndices[run]!;
        } else {
          if (runs.length >= maxRuns) {
            throw ForumBodyParagraphInputException(
              ForumBodyParagraphInputFailure.runLimit,
              path,
            );
          }
          index = runs.length;
          runIndices[run] = index;
          runs.add(run);
        }
        remap[part.runIndex] = index;
      }
      segments.add(
        HtmlDisplayTextSegment(context.projection, runIndexMap: remap),
      );
      retainedContexts.add(
        ForumBodyInlineContext._(context, start, inputLength),
      );
    }
    final display = HtmlDisplayTextProjection.concatenate(
      segments,
      sourceOrder: sourceOrder,
      maxOutputCodeUnits: maxInputCodeUnits,
      maxSegments: maxContexts,
    );
    return ForumBodyInlineSpanContent._(
      identity: identity,
      path: path,
      fontRevision: fontRevision,
      styleRevision: styleRevision,
      style: style,
      appliesFirstLineIndent: appliesFirstLineIndent,
      contexts: retainedContexts,
      projection: HtmlInlineTextProjection.build(
        display: display,
        atomicRanges: atomicRanges,
        softSpaceAtoms: softSpaceAtoms,
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
  final bool appliesFirstLineIndent;
  final HtmlInlineTextProjection projection;
  final List<ForumBodyParagraphRun> runs;
  final List<ForumBodyInlineContext> contexts;

  final _contextIndex =
      Map<ForumBodyParagraphContent, ForumBodyInlineContext?>.identity();
  var _indexedContexts = 0;
  bool get isContextIndexReady => _indexedContexts == contexts.length;

  /// Pure derived indexing, reusable across cancelled reading preparations.
  /// No native owner, callback or resource enters this immutable input cache.
  int prepareContextIndex({required int maxContexts}) {
    if (maxContexts <= 0) throw ArgumentError.value(maxContexts);
    var work = 0;
    while (!isContextIndexReady && work < maxContexts) {
      final context = contexts[_indexedContexts++];
      _contextIndex[context.content] =
          _contextIndex.containsKey(context.content) ? null : context;
      work++;
    }
    return work;
  }

  ForumBodyInlineAtomicContextCursor openAtomicContexts(int index) =>
      ForumBodyInlineAtomicContextCursor._(this, index);

  /// Resolve actual independent children covering one engine atom. Explicit
  /// source-free font struts occupy no display range; they cannot provide glyph
  /// or source coverage. Equal text is never a textual context identity.
  List<ForumBodyInlineContext> resolveAtomicContexts(
    int index,
    List<ForumBodyParagraphContent> children,
  ) {
    while (!isContextIndexReady) {
      prepareContextIndex(maxContexts: 32);
    }
    final cursor = openAtomicContexts(index);
    final result = <ForumBodyInlineContext>[];
    try {
      for (final child in children) {
        result.add(cursor.resolve(child));
      }
      cursor.finish();
      return List.unmodifiable(result);
    } finally {
      cursor.close();
    }
  }

  /// Direct TextPainter input only. Set its placeholder dimensions in atom
  /// order, using the already-scaled child geometry. RichText/WidgetSpan scale
  /// extraction is intentionally outside this native span contract.
  TextSpan get textSpan {
    if (projection.hasSoftSpaces) {
      throw StateError(
        'Soft inline spaces require explicit measured dimensions',
      );
    }
    return _parentInput.span;
  }

  /// Builds engine glue from all logical atom dimensions. A direct TextPainter
  /// consumer must pass only opaque-atom dimensions to setPlaceholderDimensions;
  /// ForumBodyInlineParagraphLayout handles that mapping and native validation.
  TextSpan textSpanWithDimensions(List<PlaceholderDimensions> dimensions) {
    validateDimensions(dimensions);
    return projection.hasSoftSpaces
        ? _buildTextSpan(dimensions: dimensions).span
        : textSpan;
  }

  /// Only runs actually shaped by the parent. Atomic children retain their
  /// own direction and per-size scaling; those inputs must not be validated or
  /// rescaled as ordinary parent text.
  late final List<ForumBodyParagraphRun> parentRuns = _parentInput.runs;
  late final _parentInput = _buildTextSpan();

  void validateDimensions(List<PlaceholderDimensions> dimensions) {
    if (dimensions.length != projection.atoms.length) {
      throw ArgumentError('Native inline dimensions do not match atoms');
    }
    if (!projection.hasSoftSpaces) {
      for (final dimension in dimensions) {
        _validateDimension(dimension);
      }
      return;
    }
    for (final (index, dimension) in dimensions.indexed) {
      // Only the mechanical SPACE may be width-only during native row
      // discovery. Opaque children still require a positive actual envelope;
      // visible gap delivery must recheck its own measured glyph dimensions.
      _validateDimension(
        dimension,
        allowZeroHeight: projection.atoms[index].isSoftSpace,
      );
    }
  }

  ({TextSpan span, List<ForumBodyParagraphRun> runs}) _buildTextSpan({
    List<PlaceholderDimensions>? dimensions,
  }) {
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
        children.add(
          atoms[atomIndex].isSoftSpace
              ? ForumBodyNativeSpaceSpan(dimensions?[atomIndex].size.width ?? 0)
              : const _NativeInlinePlaceholder(),
        );
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

/// One atom's source cursor over an already indexed current parent. Every
/// source decision is shared by synchronous lookup and cooperative binding.
final class ForumBodyInlineAtomicContextCursor {
  ForumBodyInlineAtomicContextCursor._(
    ForumBodyInlineSpanContent content,
    int index,
  ) : _content = content {
    RangeError.checkValidIndex(index, content.projection.atoms, 'index');
    if (!content.isContextIndexReady) {
      throw StateError('Inline context index is incomplete');
    }
    final atom = content.projection.atoms[index];
    _offset = atom.displayStartUtf16;
    _end = atom.displayEndUtf16;
  }
  ForumBodyInlineSpanContent? _content;
  late int _offset;
  late final int _end;
  ForumBodyInlineContext resolve(ForumBodyParagraphContent child) {
    final content = _content;
    if (content == null) throw StateError('Inline source cursor is retired');
    if (child.isSourceFree) {
      if (child.identity != content.identity ||
          child.fontRevision != content.fontRevision ||
          child.styleRevision != content.styleRevision ||
          child.projection.text.isNotEmpty) {
        throw ForumBodyParagraphInputException(
          ForumBodyParagraphInputFailure.identity,
          child.path,
        );
      }
      return ForumBodyInlineContext._(child, _offset, _offset);
    }
    final window = content._contextIndex[child];
    if (window == null) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.identity,
        child.path,
      );
    }
    if (window.startUtf16 != _offset || window.endUtf16 < _offset) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.structure,
        child.path,
      );
    }
    _offset = window.endUtf16;
    return window;
  }

  void finish() {
    final content = _content;
    if (content == null) throw StateError('Inline source cursor is retired');
    if (_offset != _end) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.structure,
        content.path,
      );
    }
    close();
  }

  void close() => _content = null;
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

void _validateDimension(
  PlaceholderDimensions dimension, {
  bool allowZeroHeight = false,
}) {
  if (dimension.alignment != ui.PlaceholderAlignment.baseline ||
      dimension.baseline != TextBaseline.alphabetic ||
      !dimension.size.width.isFinite ||
      !dimension.size.height.isFinite ||
      dimension.size.width < 0 ||
      dimension.size.height < 0 ||
      (!allowZeroHeight && dimension.size.height == 0) ||
      dimension.size.width > 16384 ||
      dimension.size.height > 16384 ||
      dimension.baselineOffset == null ||
      !dimension.baselineOffset!.isFinite ||
      dimension.baselineOffset! < 0 ||
      dimension.baselineOffset! > dimension.size.height) {
    throw ArgumentError('Invalid native inline placeholder geometry');
  }
}
