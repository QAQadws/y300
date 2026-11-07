import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import '../paragraph/forum_body_first_line_indent.dart';
import '../paragraph/forum_body_horizontal_text_frame.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_native_text_paint.dart';
import '../style/forum_body_paint_text_style.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_native_space_span.dart';
import 'forum_body_inline_image_input.dart';

part 'forum_body_inline_parent_cursor.dart';
part 'forum_body_inline_paint_input.dart';

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
/// Explicit resource atoms own only empty insertion fences. A numeric slot is
/// not a readable resource binding and cannot enter the text-context cursor.
final class ForumBodyInlineSpanContent {
  ForumBodyInlineSpanContent._({
    required this.identity,
    required this.path,
    required this.fontRevision,
    required this.styleRevision,
    required this.style,
    required this.projection,
    Map<int, ForumBodyInlineImageInput> images = const {},
    required List<ForumBodyInlineContext> contexts,
    required List<ForumBodyParagraphRun> runs,
    required this.appliesFirstLineIndent,
  }) : _sourceMapping = null,
       paintLayer = ForumBodyParagraphPaintLayer.all,
       images = images.isEmpty ? const {} : Map.unmodifiable(images),
       contexts = List.unmodifiable(contexts),
       runs = List.unmodifiable(runs);

  // The paint table changes independently of every real child/source window.
  ForumBodyInlineSpanContent._withPaintStyles(
    ForumBodyInlineSpanContent original,
    this.style,
    List<ForumBodyParagraphRun> runs,
  ) : identity = original.identity,
      path = original.path,
      fontRevision = original.fontRevision,
      styleRevision = original.styleRevision,
      projection = original.projection,
      images = original.images,
      contexts = original.contexts,
      runs = UnmodifiableListView(runs),
      paintLayer = original.paintLayer,
      appliesFirstLineIndent = original.appliesFirstLineIndent,
      _sourceMapping = original;

  ForumBodyInlineSpanContent._paintLayer(
    ForumBodyInlineSpanContent original,
    this.paintLayer,
  ) : identity = original.identity,
      path = original.path,
      fontRevision = original.fontRevision,
      styleRevision = original.styleRevision,
      style = original.style,
      projection = original.projection,
      images = original.images,
      contexts = original.contexts,
      runs = original.runs,
      appliesFirstLineIndent = original.appliesFirstLineIndent,
      _sourceMapping = original;

  static const revision = 12;

  factory ForumBodyInlineSpanContent.compose({
    required ForumBodyIdentity identity,
    required String? path,
    required String fontRevision,
    required int styleRevision,
    required ForumBodyResolvedStyle style,
    required List<ForumBodyParagraphContent> contexts,
    required List<({int startUtf16, int endUtf16})> atomicRanges,
    Set<int> softSpaceAtoms = const {},
    Set<int> resourceAtoms = const {},
    Map<int, ForumBodyInlineImageInput> images = const {},
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
      if (context.isSourceFree ||
          context.paintLayer != ForumBodyParagraphPaintLayer.all) {
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
    if (images.isNotEmpty) {
      final sourceImages = Set<ForumBodyElement>.identity();
      for (final entry in images.entries) {
        RangeError.checkValidIndex(entry.key, atomicRanges, 'images');
        final image = entry.value;
        if (!resourceAtoms.contains(entry.key) ||
            image.identity != identity ||
            !sourceImages.add(image.element)) {
          throw ArgumentError(
            'Inline images require distinct source resource slots',
          );
        }
        inputLength += image.retainedCodeUnits;
        if (inputLength > maxInputCodeUnits) {
          throw ForumBodyParagraphInputException(
            ForumBodyParagraphInputFailure.inputLimit,
            path,
          );
        }
      }
    }
    return ForumBodyInlineSpanContent._(
      identity: identity,
      path: path,
      fontRevision: fontRevision,
      styleRevision: styleRevision,
      style: style,
      appliesFirstLineIndent: appliesFirstLineIndent,
      images: images,
      contexts: retainedContexts,
      projection: HtmlInlineTextProjection.build(
        display: display,
        atomicRanges: atomicRanges,
        softSpaceAtoms: softSpaceAtoms,
        resourceAtoms: resourceAtoms,
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
  final ForumBodyParagraphPaintLayer paintLayer;
  final ForumBodyInlineSpanContent? _sourceMapping;
  final HtmlInlineTextProjection projection;
  final Map<int, ForumBodyInlineImageInput> images;
  final List<ForumBodyParagraphRun> runs;
  final List<ForumBodyInlineContext> contexts;

  /// Repartition only opaque engine slots after a measured group is too wide.
  /// Original display/source fences, windows and run identities stay intact.
  ForumBodyInlineSpanContent repartitionAtoms({
    required List<({int startUtf16, int endUtf16})> atomicRanges,
    required Set<int> softSpaceAtoms,
    Set<int> resourceAtoms = const {},
  }) {
    if (_sourceMapping != null ||
        paintLayer != ForumBodyParagraphPaintLayer.all) {
      throw StateError('Only original inline input can repartition atoms');
    }
    final remapped = HtmlInlineTextProjection.build(
      display: projection.display,
      atomicRanges: atomicRanges,
      softSpaceAtoms: softSpaceAtoms,
      resourceAtoms: resourceAtoms,
    );
    final remappedImages = <int, ForumBodyInlineImageInput>{};
    if (projection.hasResources || remapped.hasResources) {
      final previousResources = projection.atoms
          .where((a) => a.isResource)
          .iterator;
      final nextResources = remapped.atoms.where((a) => a.isResource).iterator;
      while (true) {
        final previous = previousResources.moveNext(),
            next = nextResources.moveNext();
        if (previous != next ||
            (previous &&
                previousResources.current.displayStartUtf16 !=
                    nextResources.current.displayStartUtf16)) {
          throw ArgumentError('Repartitioning cannot change resource fences');
        }
        if (!previous) break;
        final image = images[previousResources.current.index];
        if (image != null) remappedImages[nextResources.current.index] = image;
      }
    }
    return ForumBodyInlineSpanContent._(
      identity: identity,
      path: path,
      fontRevision: fontRevision,
      styleRevision: styleRevision,
      style: style,
      projection: remapped,
      images: remappedImages,
      contexts: contexts,
      runs: runs,
      appliesFirstLineIndent: appliesFirstLineIndent,
    );
  }

  // Only the enclosing constrained paragraph reserves an edge. Atomic child
  // fonts participate too; their intrinsic layouts keep their native origins.
  late final double horizontalInset =
      _sourceMapping?.horizontalInset ??
      (projection.display.text.isEmpty
          ? 0.0
          : forumBodyHorizontalTextInset([
              style,
              ...runs.map((run) => run.style),
            ]));

  /// Display/source ownership stays fixed; only wrap's native coordinates gain
  /// the mechanical prefix. Intrinsic child measurement leaves indent outside.
  HtmlInlineTextProjection projectionForLayout(
    ForumBodyParagraphLayoutMode layoutMode,
  ) =>
      _sourceMapping?.projectionForLayout(layoutMode) ??
      (forumBodyHasFirstLineIndent(
            style: style,
            displayText: projection.display.text,
            startsWithResource: _startsWithResource,
            appliesFirstLineIndent: appliesFirstLineIndent,
            layoutMode: layoutMode,
          )
          ? _indentedProjection
          : projection);

  late final _indentedProjection = HtmlInlineTextProjection.build(
    display: projection.display,
    atomicRanges: [
      for (final atom in projection.atoms)
        (startUtf16: atom.displayStartUtf16, endUtf16: atom.displayEndUtf16),
    ],
    softSpaceAtoms: {
      for (final atom in projection.atoms)
        if (atom.isSoftSpace) atom.index,
    },
    resourceAtoms: {
      for (final atom in projection.atoms)
        if (atom.isResource) atom.index,
    },
    enginePrefix: ForumBodyNativeSpaceSpan.nonBreakingText,
    maxAtoms: projection.atoms.length,
    maxDisplayCodeUnits: projection.display.text.length,
    maxEngineCodeUnits:
        projection.engineText.length +
        ForumBodyNativeSpaceSpan.nonBreakingText.length,
  );

  double resolveFirstLineIndent(
    double width,
    Map<double, double> scales,
    ForumBodyParagraphLayoutMode layoutMode,
  ) => resolveForumBodyFirstLineIndentValue(
    style: style,
    displayText: projection.display.text,
    startsWithResource: _startsWithResource,
    appliesFirstLineIndent: appliesFirstLineIndent,
    layoutMode: layoutMode,
    width: width,
    scales: scales,
  );

  bool get _startsWithResource =>
      projection.atoms.isNotEmpty &&
      projection.atoms.first.isResource &&
      projection.atoms.first.displayStartUtf16 == 0;

  final _contextIndex =
      Map<ForumBodyParagraphContent, ForumBodyInlineContext?>.identity();
  var _indexedContexts = 0;
  bool get isContextIndexReady => _indexedContexts == contexts.length;

  /// Pure derived indexing, reusable across cancelled reading preparations.
  /// No native owner, callback or resource enters this immutable input cache.
  int prepareContextIndex({required int maxContexts}) {
    _ensureSourceInput();
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

  ForumBodyInlineAtomicContextCursor openAtomicContexts(int index) {
    _ensureSourceInput();
    return ForumBodyInlineAtomicContextCursor._(this, index);
  }

  void _ensureSourceInput() {
    if (paintLayer != ForumBodyParagraphPaintLayer.all) {
      throw StateError('Inline paint phases cannot bind source contexts');
    }
  }

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
  /// firstLineIndent is an already resolved advance for projectionForLayout;
  /// callers must keep the span and effective engine projection paired.
  TextSpan textSpanWithDimensions(
    List<PlaceholderDimensions> dimensions, {
    double firstLineIndent = 0,
  }) {
    validateDimensions(dimensions);
    final span = projection.hasSoftSpaces
        ? _buildTextSpan(dimensions: dimensions).span
        : textSpan;
    return firstLineIndent == 0
        ? span
        : forumBodyNativePaintSpan(
            style: style.textStyle,
            layer: paintLayer,
            children: [
              ForumBodyNativeSpaceSpan.nonBreaking(firstLineIndent),
              ...span.children!,
            ],
          );
  }

  /// Only runs actually shaped by the parent. Atomic children retain their
  /// own direction and per-size scaling; those inputs must not be validated or
  /// rescaled as ordinary parent text.
  late final List<ForumBodyParagraphRun> parentRuns = _parentInput.runs;
  late final _parentInput = _buildTextSpan();

  late final bool hasSolidParentTextBackground =
      paintLayer == ForumBodyParagraphPaintLayer.all &&
      parentRuns.any((run) => forumBodySolidTextBackground(run.style) != null);

  late final ForumBodyInlineSpanContent withoutTextBackground =
      ForumBodyInlineSpanContent._withPaintStyles(
        this,
        forumBodyWithoutSolidTextBackground(style),
        [
          for (final run in runs)
            ForumBodyParagraphRun(
              run.path,
              forumBodyWithoutSolidTextBackground(run.style),
            ),
        ],
      );

  Iterable<({int start, int end, ForumBodyResolvedStyle style})>
  get parentTextRanges sync* {
    final cursor = _InlineParentCursor(projection);
    while (!cursor.isComplete) {
      final part = cursor.advance();
      if (part?.runIndex case final runIndex?) {
        yield (
          start: part!.startUtf16,
          end: part.endUtf16,
          style: runs[runIndex].style,
        );
      }
    }
  }

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
    final atoms = projection.atoms;
    final cursor = _InlineParentCursor(projection);
    while (!cursor.isComplete) {
      final piece = cursor.advance();
      if (piece == null) continue;
      if (piece.atomIndex case final atomIndex?) {
        children.add(
          atoms[atomIndex].isSoftSpace
              ? ForumBodyNativeSpaceSpan(dimensions?[atomIndex].size.width ?? 0)
              : const _NativeInlinePlaceholder(),
        );
        continue;
      }
      final runIndex = piece.runIndex!;
      parentRunIndices.add(runIndex);
      children.add(
        forumBodyNativePaintSpan(
          text: projection.display.text.substring(
            piece.startUtf16,
            piece.endUtf16,
          ),
          style: runs[runIndex].style.textStyle,
          resolved: runs[runIndex].style,
          layer: paintLayer,
        ),
      );
    }
    return (
      span: forumBodyNativePaintSpan(
        style: style.textStyle,
        layer: paintLayer,
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
    if (atom.isResource) {
      throw ArgumentError('Resource slots have no text contexts');
    }
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
