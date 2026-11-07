import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart' show listEquals;
import '../document/forum_body_document.dart';

import '../inline/forum_body_inline_span_content.dart';
import '../inline/forum_body_inline_font_frame_plan.dart';
import '../inline/forum_body_emphasis_paragraph_metrics.dart';
import '../inline/forum_body_inline_paragraph_request.dart';
import '../inline/forum_body_ruby_atom_plan.dart';
import '../inline/forum_body_ruby_column_request.dart';
import '../inline/forum_body_ruby_group_metrics.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_layout.dart'
    show ForumBodyParagraphLayoutException;
import '../paragraph/forum_body_text_request.dart';
import '../paragraph/forum_body_native_request.dart';
import '../inline/forum_body_text_band_content.dart';
import '../inline/forum_body_ruby_container_background.dart';
import '../inline/forum_body_ruby_root_box.dart';
import 'forum_body_text_page_binding.dart';
import 'forum_body_text_page_composer.dart';
import 'forum_body_source_hint.dart';
import 'forum_body_list_marker_plan.dart';
import 'forum_body_image_frame.dart';

export '../inline/forum_body_ruby_column_request.dart';

part 'forum_body_emphasis_page_content.dart';

/// Retained pure input for one composed paragraph, without a native owner,
/// preparation cursor, Context or callback. The session controls total input
/// retention; native resources remain in its existing shared reading cache.
sealed class ForumBodyTextPageContent {
  const ForumBodyTextPageContent._();
  ForumBodyTextPageContent get bodyContent => this;
  factory ForumBodyTextPageContent.paragraph(
    ForumBodyParagraphContent content,
  ) = ForumBodyParagraphPageContent;
  factory ForumBodyTextPageContent.emphasis(
    ForumBodyEmphasisParagraphMetrics paragraph,
  ) = ForumBodyEmphasisPageContent;
  factory ForumBodyTextPageContent.inline({
    required ForumBodyInlineSpanContent content,
    required List<PlaceholderDimensions> dimensions,
    required List<ForumBodyRubyColumnRequest> rubyGroups,
    List<ForumBodyRubyLevelMetrics?>? rubyLevelMetrics,
    Map<int, ForumBodyRubyContainerFontBox> containerBackgrounds,
    Map<int, ForumBodyRubyRootFontBox> rootFonts,
    ForumBodyParagraphLayoutMode layoutMode,
  }) = ForumBodyInlinePageContent;
  factory ForumBodyTextPageContent.inlineAtoms({
    required ForumBodyInlineSpanContent content,
    required List<PlaceholderDimensions> dimensions,
    required List<ForumBodyRubyAtomPlan> rubyAtoms,
    Set<int> trimmedAtomIndices,
    Map<int, ForumBodyRubyContainerFontBox> containerBackgrounds,
    Map<int, ForumBodyRubyRootFontBox> rootFonts,
    ForumBodyParagraphLayoutMode layoutMode,
  }) = ForumBodyInlinePageContent.atoms;
  int get textCodeUnits;
  int get runCount;
  int get retainedTextCodeUnits => textCodeUnits;
  int get retainedRuns => runCount;
  ForumBodyIdentity get identity;
  double requestWidthFor(ForumBodyTextPageFragment fragment);
  int nativeHandleCountFor(ForumBodyTextPageFragment fragment);
  int imageCountFor(ForumBodyTextPageFragment fragment) => 0;
  int nativePreparationHandleCountFor(ForumBodyTextPageFragment fragment) =>
      nativeHandleCountFor(fragment);
  Iterable<ForumBodyNativeRequestSlot> nativeFootprintFor(
    ForumBodyTextPageFragment fragment,
  );

  /// Inputs already known by the retained plan, including scenes. A format
  /// needing cooperative scene composition adds that contribution in PageJob.
  /// Resource acquisition and final handle reservation remain separate.
  Iterable<ForumBodyNativeBudgetSlot> nativeBudgetFootprintFor(
    ForumBodyTextPageFragment fragment,
  ) => nativeFootprintFor(fragment);
}

/// A pure prepared resource. It consumes retained metadata, but no text run,
/// line, shaping request or paragraph-cache entry.
final class ForumBodyImagePageContent extends ForumBodyTextPageContent {
  ForumBodyImagePageContent({
    required this.input,
    required this.frame,
    required this.fontRevision,
    required this.styleRevision,
  }) : super._();
  final ForumBodyImageInput input;
  final ForumBodyImageFrame frame;
  final String fontRevision;
  final int styleRevision;
  @override
  ForumBodyIdentity get identity => input.identity;
  @override
  int get textCodeUnits => 0;
  @override
  int get runCount => 0;
  @override
  int get retainedTextCodeUnits => input.retainedCodeUnits;
  @override
  int imageCountFor(ForumBodyTextPageFragment fragment) {
    nativeHandleCountFor(fragment);
    return 1;
  }

  @override
  double requestWidthFor(ForumBodyTextPageFragment fragment) => frame.width;
  @override
  int nativeHandleCountFor(ForumBodyTextPageFragment fragment) {
    if (fragment.kind != ForumBodyTextPageFragmentKind.image ||
        fragment.path != input.element.path ||
        fragment.fontRevision != fontRevision ||
        fragment.styleRevision != styleRevision) {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.identity,
      );
    }
    if (!identical(fragment.imageFrame, frame) ||
        fragment.width != frame.width ||
        fragment.height != frame.height ||
        fragment.startLine != 0 ||
        fragment.endLine != 0 ||
        fragment.coverageStartUtf16 != 0 ||
        fragment.coverageEndUtf16 != 0 ||
        fragment.sourceHint != null ||
        fragment.imageCount != 1 ||
        fragment.imagePaths.length != 1 ||
        fragment.imagePaths.single != input.element.path) {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.geometry,
      );
    }
    return 0;
  }

  @override
  Iterable<ForumBodyNativeRequestSlot> nativeFootprintFor(
    ForumBodyTextPageFragment fragment,
  ) {
    nativeHandleCountFor(fragment);
    return const [];
  }
}

final class ForumBodyListItemPageContent extends ForumBodyTextPageContent {
  ForumBodyListItemPageContent(this.body, this.markers) : super._() {
    if (body is ForumBodyListItemPageContent ||
        body.identity != markers.identity) {
      throw ArgumentError('List markers require current unwrapped body');
    }
  }
  final ForumBodyTextPageContent body;
  final ForumBodyListMarkerPlan markers;
  @override
  ForumBodyTextPageContent get bodyContent => body;
  @override
  int imageCountFor(ForumBodyTextPageFragment fragment) =>
      body.imageCountFor(fragment);
  @override
  ForumBodyIdentity get identity => body.identity;
  @override
  int get textCodeUnits => body.textCodeUnits;
  @override
  int get runCount => body.runCount;
  @override
  int get retainedTextCodeUnits =>
      body.retainedTextCodeUnits + markers.retainedCodeUnits;
  @override
  int get retainedRuns => body.retainedRuns + markers.fontCount;
  @override
  double requestWidthFor(ForumBodyTextPageFragment fragment) =>
      body.requestWidthFor(fragment);
  void _validate(ForumBodyTextPageFragment fragment) {
    final marker = fragment.listMarker;
    if (body is ForumBodyImagePageContent &&
        marker?.baseline != markers.blockTopBaseline) {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.geometry,
      );
    }
    if (marker != null &&
        (fragment.startLine != 0 ||
            marker.bounds !=
                markers.bounds.shift(Offset(0, marker.baseline)))) {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.geometry,
      );
    }
  }

  @override
  int nativeHandleCountFor(ForumBodyTextPageFragment fragment) {
    _validate(fragment);
    return body.nativeHandleCountFor(fragment) +
        (fragment.listMarker == null ? 0 : 1);
  }

  @override
  int nativePreparationHandleCountFor(ForumBodyTextPageFragment fragment) {
    _validate(fragment);
    return body.nativePreparationHandleCountFor(fragment) +
        (fragment.listMarker == null ? 0 : markers.preparationHandleCount);
  }

  @override
  Iterable<ForumBodyNativeRequestSlot> nativeFootprintFor(
    ForumBodyTextPageFragment fragment,
  ) => body.nativeFootprintFor(fragment);
  @override
  Iterable<ForumBodyNativeBudgetSlot> nativeBudgetFootprintFor(
    ForumBodyTextPageFragment fragment,
  ) sync* {
    _validate(fragment);
    yield* body.nativeBudgetFootprintFor(fragment);
    if (fragment.listMarker != null) yield* markers.footprint;
  }
}

final class ForumBodyParagraphPageContent extends ForumBodyTextPageContent {
  ForumBodyParagraphPageContent(this.content) : super._() {
    if (content.isSourceFree) {
      throw ArgumentError('Anonymous font struts are not document paragraphs');
    }
  }
  final ForumBodyParagraphContent content;
  @override
  ForumBodyIdentity get identity => content.identity;
  @override
  int get textCodeUnits => content.projection.text.length;
  @override
  int get runCount => content.runs.length;
  @override
  double requestWidthFor(ForumBodyTextPageFragment fragment) =>
      content.layoutMode == ForumBodyParagraphLayoutMode.intrinsicSingleLine &&
          fragment.width == 0
      ? 1
      : fragment.width;
  @override
  int nativeHandleCountFor(ForumBodyTextPageFragment fragment) {
    if (fragment.kind != ForumBodyTextPageFragmentKind.paragraph ||
        fragment.path != content.path ||
        fragment.fontRevision != content.fontRevision ||
        fragment.styleRevision != content.styleRevision) {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.identity,
      );
    }
    return 1;
  }

  @override
  Iterable<ForumBodyNativeRequestSlot> nativeFootprintFor(
    ForumBodyTextPageFragment fragment,
  ) sync* {
    nativeHandleCountFor(fragment);
    yield (
      request: ForumBodyTextRequest.paragraph(content),
      width: requestWidthFor(fragment),
      minimumLineCount: fragment.endLine,
    );
  }
}

final class ForumBodyInlinePageContent extends ForumBodyTextPageContent {
  ForumBodyInlinePageContent({
    required ForumBodyInlineSpanContent content,
    required List<PlaceholderDimensions> dimensions,
    required List<ForumBodyRubyColumnRequest> rubyGroups,
    List<ForumBodyRubyLevelMetrics?>? rubyLevelMetrics,
    Map<int, ForumBodyRubyContainerFontBox> containerBackgrounds = const {},
    Map<int, ForumBodyRubyRootFontBox> rootFonts = const {},
    ForumBodyParagraphLayoutMode layoutMode = ForumBodyParagraphLayoutMode.wrap,
  }) : this.atoms(
         content: content,
         dimensions: dimensions,
         rubyAtoms: _columnAtoms(rubyGroups, rubyLevelMetrics),
         containerBackgrounds: containerBackgrounds,
         rootFonts: rootFonts,
         layoutMode: layoutMode,
       );

  ForumBodyInlinePageContent.atoms({
    required this.content,
    required List<PlaceholderDimensions> dimensions,
    required List<ForumBodyRubyAtomPlan> rubyAtoms,
    Set<int> trimmedAtomIndices = const {},
    Map<int, ForumBodyRubyContainerFontBox> containerBackgrounds = const {},
    Map<int, ForumBodyRubyRootFontBox> rootFonts = const {},
    this.layoutMode = ForumBodyParagraphLayoutMode.wrap,
  }) : fontFrames = null,
       dimensions = List.unmodifiable(dimensions),
       rubyAtoms = List.unmodifiable(rubyAtoms),
       trimmedAtomIndices = Set.unmodifiable(trimmedAtomIndices),
       containerBackgrounds = Map.unmodifiable(containerBackgrounds),
       rootFonts = Map.unmodifiable(rootFonts),
       _nativeHandlePrefix = List.filled(rubyAtoms.length + 1, 0),
       super._() {
    content.validateDimensions(this.dimensions);
    if (rubyAtoms.length != content.projection.atoms.length ||
        layoutMode == ForumBodyParagraphLayoutMode.fitSingleLine) {
      throw ArgumentError('Invalid inline page input');
    }
    final retained = Set<ForumBodyParagraphContent>.identity()
      ..addAll(content.contexts.map((item) => item.content))
      ..addAll(rubyAtoms.expand((atom) => atom.glyphContexts));
    final checkedBands = Set<ForumBodyTextBandContent>.identity();
    if (this.rootFonts.length > rubyAtoms.length ||
        this.rootFonts.keys.any(
          (index) => index < 0 || index >= rubyAtoms.length,
        )) {
      throw ArgumentError('Invalid ruby root font snapshot index');
    }
    if (this.containerBackgrounds.length > rubyAtoms.length ||
        this.containerBackgrounds.keys.any(
          (index) => index < 0 || index >= rubyAtoms.length,
        )) {
      throw ArgumentError('Invalid ruby container font snapshot index');
    }
    for (final index in trimmedAtomIndices) {
      if (index < 0 ||
          index >= rubyAtoms.length ||
          !content.projection.atoms[index].isSoftSpace) {
        throw ArgumentError('Invalid inline trimmed atom snapshot');
      }
    }
    for (final (index, plan) in rubyAtoms.indexed) {
      final root = switch (plan) {
        ForumBodyInlineImageAtomPlan() ||
        ForumBodyTextBaselineAtomPlan() ||
        ForumBodyIntrinsicInlineAtomPlan() => null,
        ForumBodyRubyColumnPlan(:final request) => request.rootBox,
        ForumBodyRubySegmentPlan(:final request) => request.rootBox,
        ForumBodyRubySoftSpacePlan(:final request) => request.rootBox,
      };
      if (!identical(this.rootFonts[index]?.input, root)) {
        throw ArgumentError('Ruby root font snapshot differs from request');
      }
      final background = switch (plan) {
        ForumBodyInlineImageAtomPlan() ||
        ForumBodyTextBaselineAtomPlan() ||
        ForumBodyIntrinsicInlineAtomPlan() => null,
        ForumBodyRubyColumnPlan(:final request) => request.background,
        ForumBodyRubySegmentPlan(:final request) => request.background,
        ForumBodyRubySoftSpacePlan(:final request) => request.background,
      };
      if (!identical(
        this.containerBackgrounds[index]?.background,
        background,
      )) {
        throw ArgumentError(
          'Ruby container font snapshot differs from request',
        );
      }
      _nativeHandlePrefix[index + 1] =
          _nativeHandlePrefix[index] +
          (trimmedAtomIndices.contains(index) ? 0 : plan.nativeHandleCount);
      if (content.projection.atoms[index].isSoftSpace !=
          (plan is ForumBodyRubySoftSpacePlan)) {
        throw ArgumentError(
          'Soft native slots require actual soft-space plans',
        );
      }
      if (content.projection.atoms[index].isResource !=
              (plan is ForumBodyInlineImageAtomPlan) ||
          (plan is ForumBodyInlineImageAtomPlan &&
              !identical(content.images[index], plan.input))) {
        throw ArgumentError(
          'Inline resource slot requires its actual image plan',
        );
      }
      final target = switch (plan) {
        ForumBodyInlineImageAtomPlan(:final input) => (
          size: input.dimensions.size,
          baseline: input.dimensions.baselineOffset!,
        ),
        ForumBodyIntrinsicInlineAtomPlan(:final metrics) => (
          size: metrics.size,
          baseline: metrics.baseline,
        ),
        ForumBodyTextBaselineAtomPlan(:final metrics) => (
          size: metrics.size,
          baseline: metrics.baseline,
        ),
        ForumBodyRubySegmentPlan(:final metrics) => (
          size: metrics.size,
          baseline: metrics.baseline,
        ),
        ForumBodyRubySoftSpacePlan(:final metrics) => (
          size: metrics.size,
          baseline: metrics.baseline,
        ),
        ForumBodyRubyColumnPlan(metrics: final metrics?) => (
          size: metrics.size,
          baseline: metrics.baseline,
        ),
        _ => null,
      };
      if (target != null) {
        final framed = this.rootFonts[index]?.enclose(
          childSize: target.size,
          childBaseline: target.baseline,
        );
        final size = framed?.size ?? target.size;
        final baseline = framed?.baseline ?? target.baseline;
        final dimension = this.dimensions[index];
        if ((dimension.size.width - size.width).abs() > 1e-4 ||
            (dimension.size.height - size.height).abs() > 1e-4 ||
            (dimension.baselineOffset! - baseline).abs() > 1e-4) {
          throw ArgumentError(
            'Ruby atom dimensions do not match numeric target',
          );
        }
      }
      if (plan is! ForumBodyInlineImageAtomPlan) {
        content.resolveAtomicContexts(
          index,
          plan.sourceContexts.toList(growable: false),
        );
      }
      for (final request in plan.nativeRequests) {
        // Keep the complete band input inside this already bounded paragraph.
        // An off-input tail must not evade the session's retention accounting.
        if (request is ForumBodyTextBandChildRequest &&
            checkedBands.add(request.band) &&
            request.band.contexts.any(
              (context) => !retained.contains(context),
            )) {
          throw ForumBodyParagraphInputException(
            ForumBodyParagraphInputFailure.identity,
            content.path,
          );
        }
      }
    }
  }
  factory ForumBodyInlinePageContent.withFontFrames(
    ForumBodyInlineFontFramePlan plan,
  ) => ForumBodyInlinePageContent._framed(
    plan.allocation.input.natural.page,
    plan,
  );
  ForumBodyInlinePageContent._framed(
    ForumBodyInlinePageContent source,
    ForumBodyInlineFontFramePlan plan,
  ) : content = source.content,
      dimensions = source.dimensions,
      rubyAtoms = source.rubyAtoms,
      trimmedAtomIndices = source.trimmedAtomIndices,
      containerBackgrounds = source.containerBackgrounds,
      rootFonts = source.rootFonts,
      _nativeHandlePrefix = source._nativeHandlePrefix,
      layoutMode = source.layoutMode,
      fontFrames = plan,
      super._() {
    if (source.fontFrames != null ||
        source.layoutMode != ForumBodyParagraphLayoutMode.wrap ||
        !identical(source.content, plan.source.content)) {
      throw ArgumentError('Font frames require their original source');
    }
  }
  final ForumBodyInlineFontFramePlan? fontFrames;
  final ForumBodyInlineSpanContent content;
  final List<PlaceholderDimensions> dimensions;

  /// A composite child must budget this actual native parent in addition to its
  /// glyph leaves. Source contexts remain in content, never inferred from a
  /// native handle list. The request owns only this frozen pure geometry.
  late final parentRequest = ForumBodyInlineParagraphRequest(
    content: content,
    dimensions: dimensions,
    layoutMode: layoutMode,
  );
  final List<ForumBodyRubyAtomPlan> rubyAtoms;
  final Set<int> trimmedAtomIndices;
  final Map<int, ForumBodyRubyContainerFontBox> containerBackgrounds;
  final Map<int, ForumBodyRubyRootFontBox> rootFonts;
  final List<int> _nativeHandlePrefix;
  // Legacy column-only access remains explicit: never drop component members
  // or silently present its first column as the complete parent atom.
  late final List<ForumBodyRubyColumnRequest> rubyGroups = List.unmodifiable([
    for (final atom in rubyAtoms)
      atom is ForumBodyRubyColumnPlan
          ? atom.request
          : throw StateError('Inline input contains non-column atoms'),
  ]);
  late final List<ForumBodyRubyLevelMetrics?> rubyLevelMetrics =
      List.unmodifiable([
        for (final atom in rubyAtoms)
          atom is ForumBodyRubyColumnPlan
              ? atom.level
              : throw StateError('Inline input contains non-column atoms'),
      ]);
  final ForumBodyParagraphLayoutMode layoutMode;
  @override
  ForumBodyIdentity get identity => content.identity;
  @override
  int get textCodeUnits => content.projection.display.text.length;
  @override
  int get runCount => content.runs.length;
  @override
  late final retainedTextCodeUnits =
      textCodeUnits +
      rubyAtoms.fold<int>(0, (sum, atom) => sum + atom.extraTextCodeUnits) +
      (fontFrames?.source.retainedTextCodeUnits ?? 0);
  @override
  late final retainedRuns =
      runCount +
      rubyAtoms.fold<int>(0, (sum, atom) => sum + atom.extraRuns) +
      (fontFrames?.source.retainedRuns ?? 0);
  // Intrinsic shaping ignores a valid request width. Preserve an empty physical
  // frame's zero width while still passing native input admission explicitly.
  @override
  double requestWidthFor(ForumBodyTextPageFragment fragment) =>
      layoutMode == ForumBodyParagraphLayoutMode.intrinsicSingleLine &&
          fragment.width == 0
      ? 1
      : fragment.width;

  List<int> visibleAtoms(ForumBodyTextPageFragment fragment) {
    if (fragment.kind != ForumBodyTextPageFragmentKind.inline ||
        fragment.path != content.path ||
        fragment.fontRevision != content.fontRevision ||
        fragment.styleRevision != content.styleRevision) {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.identity,
      );
    }
    RangeError.checkValidRange(
      fragment.coverageStartUtf16,
      fragment.coverageEndUtf16,
      content.projection.display.text.length,
    );
    if (fontFrames case final frames?) {
      try {
        final selected = frames.fragment(fragment.startLine, fragment.endLine);
        if (fragment.width != frames.width ||
            fragment.height != selected.height ||
            fragment.coverageStartUtf16 != selected.coverageStartUtf16 ||
            fragment.coverageEndUtf16 != selected.coverageEndUtf16 ||
            fragment.sourceHint !=
                forumBodySourceHint(
                  content.projection.display,
                  selected.coverageStartUtf16,
                  selected.coverageEndUtf16,
                )) {
          throw const ForumBodyTextPageSurfaceException(
            ForumBodyTextPageSurfaceFailure.geometry,
          );
        }
      } on RangeError {
        throw const ForumBodyTextPageSurfaceException(
          ForumBodyTextPageSurfaceFailure.geometry,
        );
      } on ForumBodyParagraphLayoutException {
        throw const ForumBodyTextPageSurfaceException(
          ForumBodyTextPageSurfaceFailure.geometry,
        );
      }
    }
    final engine = fragment.engineRange;
    if (engine == null) {
      if (fragment.startLine == fragment.endLine &&
          content.projection.atoms.isEmpty) {
        return const [];
      }
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.geometry,
      );
    }
    final projection = content.projectionForLayout(layoutMode);
    RangeError.checkValidRange(
      engine.startUtf16,
      engine.endUtf16,
      projection.engineText.length,
    );
    if (!projection.isLegalEngineBoundary(engine.startUtf16) ||
        !projection.isLegalEngineBoundary(engine.endUtf16) ||
        projection.displayRangeForEngineRange(
              startUtf16: engine.startUtf16,
              endUtf16: engine.endUtf16,
            ) !=
            (
              startUtf16: fragment.coverageStartUtf16,
              endUtf16: fragment.coverageEndUtf16,
            )) {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.geometry,
      );
    }
    final result = <int>[];
    for (final atom in projection.atoms) {
      if (atom.engineEndUtf16 <= engine.startUtf16) continue;
      if (atom.engineUtf16 >= engine.endUtf16) break;
      if (atom.engineUtf16 < engine.startUtf16 ||
          atom.engineEndUtf16 > engine.endUtf16) {
        throw const ForumBodyTextPageSurfaceException(
          ForumBodyTextPageSurfaceFailure.geometry,
        );
      }
      if (!trimmedAtomIndices.contains(atom.index)) result.add(atom.index);
    }
    return List.unmodifiable(result);
  }

  @override
  int imageCountFor(ForumBodyTextPageFragment fragment) {
    final paths = [
      for (final index in visibleAtoms(fragment))
        if (content.images[index] case final image? when !image.isHidden)
          image.element.path,
    ];
    if (fragment.imageCount != paths.length ||
        !listEquals(fragment.imagePaths, paths)) {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.geometry,
      );
    }
    return paths.length;
  }

  @override
  int nativeHandleCountFor(ForumBodyTextPageFragment fragment) =>
      (fontFrames?.visibleParentHandleCount(
            fragment.startLine,
            fragment.endLine,
          ) ??
          1) +
      visibleAtoms(
        fragment,
      ).fold<int>(0, (sum, index) => sum + rubyAtoms[index].nativeHandleCount);

  @override
  int nativePreparationHandleCountFor(ForumBodyTextPageFragment fragment) =>
      nativeHandleCountFor(fragment) +
      (fontFrames == null
          ? 0
          : fontFrames!.preparationParentHandleCount(
                  fragment.startLine,
                  fragment.endLine,
                ) -
                fontFrames!.visibleParentHandleCount(
                  fragment.startLine,
                  fragment.endLine,
                ));

  @override
  Iterable<ForumBodyNativeRequestSlot> nativeFootprintFor(
    ForumBodyTextPageFragment fragment,
  ) sync* {
    for (final slot in nativeBudgetFootprintFor(fragment)) {
      final request = slot.request;
      if (request is ForumBodyNativeRequest) {
        yield (
          request: request,
          width: slot.width,
          minimumLineCount: slot.minimumLineCount,
        );
      }
    }
  }

  @override
  Iterable<ForumBodyNativeBudgetSlot> nativeBudgetFootprintFor(
    ForumBodyTextPageFragment fragment,
  ) sync* {
    yield (
      request: parentRequest,
      width: requestWidthFor(fragment),
      minimumLineCount: fontFrames?.lines.length ?? fragment.endLine,
    );
    if (fontFrames case final frames?) {
      yield* frames.paintReference.nativeFootprint;
    }
    for (final atom in visibleAtoms(fragment)) {
      yield* rubyAtoms[atom].nativeBudgetFootprint;
    }
  }

  /// Actual parent plus visible child request slots in a legal display window.
  /// Prefix sums are built in the existing bounded input validation pass;
  /// composition queries are logarithmic and never measure or retain leases.
  int nativeHandleCountInRange(int start, int end) {
    RangeError.checkValidRange(start, end, textCodeUnits);
    final atoms = content.projection.atoms;
    int lowerBound(int offset, {required bool byEnd}) {
      var low = 0;
      var high = atoms.length;
      while (low < high) {
        final mid = (low + high) ~/ 2;
        final before = byEnd
            ? atoms[mid].displayEndUtf16 <= offset
            : atoms[mid].displayStartUtf16 < offset;
        if (before) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      return low;
    }

    final first = lowerBound(start, byEnd: true);
    final after = lowerBound(end, byEnd: false);
    if ((first < atoms.length && atoms[first].displayStartUtf16 < start) ||
        (after > 0 && atoms[after - 1].displayEndUtf16 > end)) {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.geometry,
      );
    }
    return (fontFrames == null ? 1 : 3) +
        _nativeHandlePrefix[after] -
        _nativeHandlePrefix[first];
  }

  int nativePreparationHandleCountInRange(int start, int end) =>
      nativeHandleCountInRange(start, end) + (fontFrames == null ? 0 : 7);
}

List<ForumBodyRubyAtomPlan> _columnAtoms(
  List<ForumBodyRubyColumnRequest> requests,
  List<ForumBodyRubyLevelMetrics?>? levels,
) {
  if (levels != null && levels.length != requests.length) {
    throw ArgumentError('Invalid inline page targets');
  }
  return [
    for (final (index, request) in requests.indexed)
      ForumBodyRubyAtomPlan.column(request: request, level: levels?[index]),
  ];
}
