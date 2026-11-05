import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Rect;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import '../style/forum_body_quote_decoration.dart';
import '../inline/forum_body_inline_paragraph_layout.dart';
import '../inline/forum_body_emphasis_paragraph_metrics.dart';
import '../inline/forum_body_fitted_emphasis_plan.dart';
import '../inline/forum_body_inline_font_frame_plan.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_layout.dart';
import 'forum_body_source_hint.dart';
import 'forum_body_list_marker_plan.dart';
import 'forum_body_image_frame.dart';

part 'forum_body_emphasis_scene_reservation.dart';
part 'forum_body_text_page_background.dart';

enum ForumBodyTextPageFailure {
  oversizedGroup,
  invalidGeometry,
  pageLimit,
  fragmentLimit,
  nativeHandleLimit,
  nativeEntryLimit,
  nativeByteLimit,
  sceneLimit,
  backgroundDepth,
}

enum ForumBodyTextPageFragmentKind {
  paragraph,
  inline,
  emphasis,
  fittedEmphasis,
  image,
}

final class ForumBodyTextPageException implements Exception {
  const ForumBodyTextPageException(this.failure);
  final ForumBodyTextPageFailure failure;
  @override
  String toString() => 'ForumBodyTextPageException(${failure.name})';
}

/// Numeric placement only: no paragraph, lease, text span, Context or callback
/// is retained by a published page. The session owns content materialization.
final class ForumBodyTextPageFragment {
  const ForumBodyTextPageFragment._({
    required this.paragraphIndex,
    required this.path,
    required this.fontRevision,
    required this.styleRevision,
    required this.startLine,
    required this.endLine,
    required this.coverageStartUtf16,
    required this.coverageEndUtf16,
    required this.sourceHint,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.kind,
    this.listMarker,
    this.imageFrame,
  });
  final int paragraphIndex;
  final String? path;
  final String fontRevision;
  final int styleRevision;
  final int startLine;
  final int endLine;
  final int coverageStartUtf16;
  final int coverageEndUtf16;

  /// Inclusive raw source envelope, only a candidate hint. It can contain
  /// hidden/unmapped gaps. Zero-text rows and padding have no source hint.
  final ({int runeStart, int runeEnd})? sourceHint;
  final double left;
  final double top;
  final double width;
  final double height;
  final ForumBodyTextPageFragmentKind kind;
  final ForumBodyTextPageListMarker? listMarker;
  final ForumBodyImageFrame? imageFrame;
}

/// Numeric decoration envelope only; no font input or source position.
final class ForumBodyTextPageListMarker {
  const ForumBodyTextPageListMarker._(this.baseline, this.bounds);
  final double baseline;
  final Rect bounds;
}

/// Immutable paint geometry. A rule never contributes text, glyph coverage or
/// a semantic reading position. Its path is only a document-local identity.
final class ForumBodyTextPageRule {
  const ForumBodyTextPageRule._({
    required this.path,
    required this.left,
    required this.top,
    required this.width,
    required this.thickness,
    required this.color,
  });
  final String path;
  final double left;
  final double top;
  final double width;
  final double thickness;
  final Color color;
}

final class ForumBodyTextPage {
  ForumBodyTextPage._(
    this.index,
    List<ForumBodyTextPageFragment> fragments,
    List<ForumBodyTextPageRule> rules,
    List<ForumBodyTextPageBackground> backgrounds,
    this.usedHeight,
  ) : fragments = List.unmodifiable(fragments),
      rules = List.unmodifiable(rules),
      backgrounds = List.unmodifiable(backgrounds);
  final int index;
  final List<ForumBodyTextPageFragment> fragments;
  final List<ForumBodyTextPageRule> rules;
  final List<ForumBodyTextPageBackground> backgrounds;
  int get itemCount => fragments.length + rules.length + backgrounds.length;
  final double usedHeight;
}

/// Fixed read-only prefix over append-only storage. Completion and length are
/// captured at creation, so later publication never changes an earlier view.
/// Coverage offsets are paragraph-local display UTF-16, not semantic anchors.
final class ForumBodyTextPageSnapshot
    extends UnmodifiableListView<ForumBodyTextPage> {
  ForumBodyTextPageSnapshot._(
    List<ForumBodyTextPage> pages,
    this.identity,
    this.layoutId,
    this.width,
    this.height,
    this.isComplete,
  ) : backendRevision = ForumBodyParagraphLayout.backendRevision,
      composerRevision = ForumBodyTextPageComposer.revision,
      super(_PagePrefix(pages, pages.length));
  final ForumBodyIdentity identity;

  /// Caller-owned layout generation tag, never persisted as a reading anchor.
  final String layoutId;
  final double width;
  final double height;
  final int backendRevision;
  final int composerRevision;
  final bool isComplete;
}

final class _PagePrefix extends ListBase<ForumBodyTextPage> {
  _PagePrefix(this._pages, this._length);
  final List<ForumBodyTextPage> _pages;
  final int _length;
  @override
  int get length => _length;
  @override
  set length(int value) => throw UnsupportedError('Fixed page prefix');
  @override
  ForumBodyTextPage operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return _pages[index];
  }

  @override
  void operator []=(int index, ForumBodyTextPage value) =>
      throw UnsupportedError('Read-only page prefix');
}

/// Text, mixed-inline, rule and block-background composition over actual native
/// line geometry.
/// The block layer resolves CSS/reader spacing and horizontal placement first;
/// this class does not collapse margins or infer settings. It consumes at most
/// one paragraph lease, releases it on completion/close/failure, and stops each
/// advance at the next stable page. Demand, idle waits and retry generations
/// belong to the Host. It never shapes or slices HTML.
/// Signed inter-paragraph spacing can overlap earlier content on the current
/// page. The flow cursor and occupied height are separate: overlap never erases
/// earlier fragment extents. Placement is clamped at the current page's top; sealed
/// pages cannot be pulled back into. Page-start spacing is explicit/nonnegative.
final class ForumBodyTextPageComposer {
  ForumBodyTextPageComposer({
    required this.identity,
    required this.layoutId,
    required this.width,
    required this.height,
    required this.maxPages,
    required this.maxFragments,
    this.maxNativeHandlesPerPage,
    this.maxNativeEntriesPerPage,
    this.maxNativeEstimatedBytesPerPage,
    this.maxDeliveriesPerPage,
  }) {
    if (layoutId.isEmpty ||
        !width.isFinite ||
        width <= 0 ||
        !height.isFinite ||
        height <= 0 ||
        maxPages <= 0 ||
        maxFragments <= 0 ||
        (maxDeliveriesPerPage != null && maxDeliveriesPerPage! <= 0) ||
        (maxNativeHandlesPerPage != null && maxNativeHandlesPerPage! <= 0) ||
        (maxNativeEntriesPerPage != null && maxNativeEntriesPerPage! <= 0) ||
        (maxNativeEstimatedBytesPerPage != null &&
            maxNativeEstimatedBytesPerPage! <= 0)) {
      throw ArgumentError('Invalid page composition inputs');
    }
  }
  static const revision = 19;
  final ForumBodyIdentity identity;
  final String layoutId;
  final double width;
  final double height;

  /// Explicit metadata budgets, not measured native/GPU memory.
  final int maxPages;
  final int maxFragments;

  /// A resource may own zero native handles and still needs one delivery.
  final int? maxDeliveriesPerPage;
  final int? maxNativeHandlesPerPage;
  final int? maxNativeEntriesPerPage;
  final int? maxNativeEstimatedBytesPerPage;
  final _nativeEntries = <Object, int>{};
  int _nativeBytes = 0;
  int _usedNativeHandles = 0;
  int _lastFragmentNativeHandles = 0;
  int _sceneEntries = 0, _sceneBytes = 0;
  _EmphasisSceneReservation? _lastSceneReservation;
  final _pages = <ForumBodyTextPage>[];
  final _draft = <ForumBodyTextPageFragment>[];
  final _rules = <ForumBodyTextPageRule>[];
  final _backgrounds = _PageBackgrounds();
  ForumBodyTextPageSnapshot? _snapshot;
  _ActiveParagraph? _active;
  _ActivePadding? _padding;
  _ActiveRule? _rule;
  _ActiveImage? _image;
  int _nextParagraphIndex = 0;
  int _fragmentCount = 0;
  double _usedHeight = 0;
  double _flowHeight = 0;
  bool _complete = false;
  bool _closed = false;

  bool get isComplete => _complete;
  bool get isClosed => _closed;
  bool get needsInput =>
      !_closed &&
      !_complete &&
      _active == null &&
      _padding == null &&
      _rule == null &&
      _image == null;
  bool get hasPendingPadding => _padding != null;
  bool get hasPendingRule => _rule != null;
  bool get hasPendingImage => _image != null;

  /// Admission order only; consumed input can extend beyond the stable pages.
  /// This ordinal must not be persisted as a confirmed reading position.
  int get nextParagraphIndex => _nextParagraphIndex;

  /// Text, rules and box backgrounds share the retained metadata budget.
  int get retainedFragmentCount => _fragmentCount;
  ForumBodyTextPageSnapshot get snapshot =>
      _snapshot ??= ForumBodyTextPageSnapshot._(
        _pages,
        identity,
        layoutId,
        width,
        height,
        _complete,
      );

  /// Open only at a block boundary. Its collapsed top is resolved lazily by
  /// actual padding/text/rule placement; opening alone cannot paint a margin.
  void openBackground({
    required String path,
    required double left,
    required double width,
    required Color color,
    ForumBodyQuoteDecoration? quoteDecoration,
  }) {
    _ensureOpen();
    if (!needsInput) throw StateError('Composition input is still pending');
    if (!left.isFinite ||
        !width.isFinite ||
        !(left + width).isFinite ||
        width < 0) {
      throw ArgumentError('Invalid background geometry');
    }
    _backgrounds.open(path, left, width, color, quoteDecoration);
  }

  void closeBackground(String path) {
    _ensureOpen();
    if (!needsInput) throw StateError('Composition input is still pending');
    _backgrounds.close(path, _flowHeight);
    if (_usedHeight == height && !_backgrounds.needsEndBoundary) _seal();
  }

  void _touchBackgrounds(double top) {
    _fragmentCount += _backgrounds.touch(top, maxFragments - _fragmentCount);
  }

  /// Already resolved block geometry, sharing text's ordered input and page
  /// metadata budgets. Resources never create native rows or text coverage.
  void appendImage({
    required ForumBodyImageInput input,
    required ForumBodyImageFrame frame,
    required int inputIndex,
    required String fontRevision,
    required int styleRevision,
    required double left,
    double spaceBefore = 0,
  }) {
    _ensureOpen();
    if (!needsInput) throw StateError('Composition input is still pending');
    if (input.identity != identity || inputIndex != _nextParagraphIndex) {
      throw ArgumentError('Unordered or foreign image input');
    }
    if (!left.isFinite ||
        !spaceBefore.isFinite ||
        frame.height > height ||
        left < 0 ||
        left + frame.width > width) {
      throw ArgumentError('Invalid image composition inputs');
    }
    _image = _ActiveImage(
      input.element.path,
      frame,
      inputIndex,
      fontRevision,
      styleRevision,
      left,
      spaceBefore,
    );
    _nextParagraphIndex++;
  }

  /// Stop after sealing a preceding page. The same indivisible resource is
  /// placed on the next call; an earlier published prefix is never changed.
  ({int pagesPublished, bool isComplete}) advanceImage() {
    _ensureOpen();
    final active = _image;
    if (active == null) throw StateError('No image is pending');
    final before = _pages.length;
    try {
      if (maxDeliveriesPerPage != null &&
          _draft.length >= maxDeliveriesPerPage!) {
        _seal();
        return (pagesPublished: 1, isComplete: false);
      }
      final atStart = _draft.isEmpty && _rules.isEmpty && _usedHeight == 0;
      final top = math.max(
        0.0,
        _flowHeight + (atStart ? 0 : active.spaceBefore),
      );
      final bottom = top + active.frame.height;
      if (!bottom.isFinite) _fail(ForumBodyTextPageFailure.invalidGeometry);
      if (bottom > height) {
        if (atStart) _fail(ForumBodyTextPageFailure.oversizedGroup);
        _seal();
        return (pagesPublished: 1, isComplete: false);
      }
      _touchBackgrounds(top);
      if (_fragmentCount >= maxFragments) {
        _fail(ForumBodyTextPageFailure.fragmentLimit);
      }
      _draft.add(
        ForumBodyTextPageFragment._(
          paragraphIndex: active.index,
          path: active.path,
          fontRevision: active.fontRevision,
          styleRevision: active.styleRevision,
          startLine: 0,
          endLine: 0,
          coverageStartUtf16: 0,
          coverageEndUtf16: 0,
          sourceHint: null,
          left: active.left,
          top: top,
          width: active.frame.width,
          height: active.frame.height,
          kind: ForumBodyTextPageFragmentKind.image,
          imageFrame: active.frame,
        ),
      );
      _fragmentCount++;
      _lastFragmentNativeHandles = 0;
      _lastSceneReservation = null;
      _flowHeight = bottom;
      _usedHeight = math.max(_usedHeight, bottom);
      _image = null;
      if (_usedHeight == height && !_backgrounds.needsEndBoundary) _seal();
      return (pagesPublished: _pages.length - before, isComplete: true);
    } catch (_) {
      close();
      rethrow;
    }
  }

  void appendRule({
    required String path,
    required double left,
    required double width,
    required double thickness,
    required Color color,
    double spaceBefore = 0,
    double spaceAtPageStart = 0,
  }) {
    _ensureOpen();
    if (!needsInput) throw StateError('Composition input is still pending');
    if (!left.isFinite ||
        !width.isFinite ||
        width < 0 ||
        !thickness.isFinite ||
        thickness <= 0 ||
        !spaceBefore.isFinite ||
        !spaceAtPageStart.isFinite ||
        spaceAtPageStart < 0) {
      throw ArgumentError('Invalid rule composition inputs');
    }
    _rule = _ActiveRule(
      path,
      left,
      width,
      thickness,
      color,
      spaceBefore,
      spaceAtPageStart,
    );
  }

  /// A rule is indivisible. Stop after sealing an occupied page; the next
  /// bounded advance places the same pending rule at the new page's start.
  ({int pagesPublished, bool isComplete}) advanceRule() {
    _ensureOpen();
    final active = _rule;
    if (active == null) throw StateError('No rule is pending');
    final before = _pages.length;
    try {
      final atStart = _draft.isEmpty && _rules.isEmpty && _usedHeight == 0;
      final gap = atStart ? active.spaceAtPageStart : active.spaceBefore;
      final top = math.max(0.0, _flowHeight + gap);
      final bottom = top + active.thickness;
      if (!bottom.isFinite) _fail(ForumBodyTextPageFailure.invalidGeometry);
      if (bottom > height) {
        if (atStart) _fail(ForumBodyTextPageFailure.oversizedGroup);
        _seal();
        return (pagesPublished: 1, isComplete: false);
      }
      _touchBackgrounds(top);
      if (_fragmentCount >= maxFragments) {
        _fail(ForumBodyTextPageFailure.fragmentLimit);
      }
      _rules.add(
        ForumBodyTextPageRule._(
          path: active.path,
          left: active.left,
          top: top,
          width: active.width,
          thickness: active.thickness,
          color: active.color,
        ),
      );
      _fragmentCount++;
      _flowHeight = bottom;
      _usedHeight = math.max(_usedHeight, bottom);
      _rule = null;
      if (_usedHeight == height && !_backgrounds.needsEndBoundary) _seal();
      return (pagesPublished: _pages.length - before, isComplete: true);
    } catch (_) {
      close();
      rethrow;
    }
  }

  /// Ownership transfers only on success; rejected leases remain the caller's.
  /// Spacing is applied once before the paragraph, never on a continuation page.
  /// The block layer explicitly chooses its spacing when starting a new page.
  void append({
    required ForumBodyParagraphLease lease,
    required int paragraphIndex,
    required double left,
    required double spaceBefore,
    required double spaceAtPageStart,
    ForumBodyParagraphWindow window = ForumBodyParagraphWindow.full,
    ForumBodyListMarkerPlan? listMarkers,
  }) => _append(
    input: _CompositionParagraph.paragraph(lease),
    paragraphIndex: paragraphIndex,
    left: left,
    spaceBefore: spaceBefore,
    spaceAtPageStart: spaceAtPageStart,
    window: window,
    listMarkers: listMarkers,
  );

  /// Owns only the already measured parent. Child dimensions are part of its
  /// native input; readable page delivery separately requires source-bound
  /// visible child views, never parent paint or placeholder coverage alone.
  void appendInline({
    required ForumBodyInlineParagraphLease lease,
    required int paragraphIndex,
    required double left,
    required double spaceBefore,
    required double spaceAtPageStart,
    ForumBodyParagraphWindow window = ForumBodyParagraphWindow.full,
    ForumBodyListMarkerPlan? listMarkers,
    ForumBodyInlineFontFramePlan? fontFrames,
    int Function(int startUtf16, int endUtf16)? nativeHandleCountInRange,
    Iterable<Object> Function(int startUtf16, int endUtf16)?
    nativeEntriesInRange,
    Iterable<ForumBodyNativeInputCost> Function(int startUtf16, int endUtf16)?
    nativeCostsInRange,
  }) => _append(
    input: _CompositionParagraph.inline(
      lease,
      nativeHandleCountInRange,
      nativeEntriesInRange,
      nativeCostsInRange,
      fontFrames,
    ),
    paragraphIndex: paragraphIndex,
    left: left,
    spaceBefore: spaceBefore,
    spaceAtPageStart: spaceAtPageStart,
    window: window,
    listMarkers: listMarkers,
  );

  /// Numeric complete-group input only. This transfers no native resource;
  /// actual readable delivery must rebind the finalized fragment's source and
  /// single scene. The Host's generation guard remains live until consumption.
  void appendEmphasis({
    required ForumBodyEmphasisParagraphNativeEntries entries,
    required void Function() ensureOwner,
    required int paragraphIndex,
    required double left,
    required double spaceBefore,
    required double spaceAtPageStart,
    ForumBodyParagraphWindow window = ForumBodyParagraphWindow.full,
    ForumBodyListMarkerPlan? listMarkers,
  }) => _append(
    input: _CompositionParagraph.emphasis(entries, ensureOwner),
    paragraphIndex: paragraphIndex,
    left: left,
    spaceBefore: spaceBefore,
    spaceAtPageStart: spaceAtPageStart,
    window: window,
    listMarkers: listMarkers,
  );

  /// One already measured complete fitted line, never a fabricated wrapping
  /// row. Exact scene keys join the same native cost ledger as its font keys.
  void appendFittedEmphasis({
    required ForumBodyFittedEmphasisPlan plan,
    required void Function() ensureOwner,
    required int paragraphIndex,
    required double left,
    required double spaceBefore,
    required double spaceAtPageStart,
    ForumBodyParagraphWindow window = ForumBodyParagraphWindow.full,
    ForumBodyListMarkerPlan? listMarkers,
  }) => _append(
    input: _CompositionParagraph.fitted(plan, ensureOwner),
    paragraphIndex: paragraphIndex,
    left: left,
    spaceBefore: spaceBefore,
    spaceAtPageStart: spaceAtPageStart,
    window: window,
    listMarkers: listMarkers,
  );

  void _append({
    required _CompositionParagraph input,
    required int paragraphIndex,
    required double left,
    required double spaceBefore,
    required double spaceAtPageStart,
    required ForumBodyParagraphWindow window,
    ForumBodyListMarkerPlan? listMarkers,
  }) {
    _ensureOpen();
    if (!needsInput) throw StateError('Composition input is still pending');
    input.ensureActive();
    _ensureOpen();
    if (paragraphIndex != _nextParagraphIndex ||
        input.identity != identity ||
        !left.isFinite ||
        left < 0 ||
        left + input.width > width ||
        !spaceBefore.isFinite ||
        !spaceAtPageStart.isFinite ||
        spaceAtPageStart < 0) {
      throw ArgumentError('Invalid paragraph composition inputs');
    }
    final range = input.lineWindow(window);
    if (listMarkers != null &&
        (listMarkers.identity != identity || range.startLine != 0)) {
      throw ArgumentError('List marker belongs to another first line');
    }
    if (maxNativeHandlesPerPage != null &&
        input.kind == ForumBodyTextPageFragmentKind.inline &&
        input.nativeHandleCountInRange == null) {
      throw ArgumentError(
        'Bounded inline composition requires actual request costs',
      );
    }
    if (maxNativeEntriesPerPage != null &&
        input.kind == ForumBodyTextPageFragmentKind.inline &&
        input.nativeEntriesInRange == null &&
        input.nativeCostsInRange == null) {
      throw ArgumentError(
        'Bounded inline composition requires native entry identities',
      );
    }
    if (maxNativeEstimatedBytesPerPage != null &&
        input.kind == ForumBodyTextPageFragmentKind.inline &&
        input.nativeCostsInRange == null) {
      throw ArgumentError(
        'Bounded inline composition requires native input costs',
      );
    }
    _active = _ActiveParagraph(
      input,
      paragraphIndex,
      left,
      spaceBefore,
      spaceAtPageStart,
      range.startLine,
      range.endLine,
      listMarkers,
    );
  }

  /// Admit physical padding independently of paragraph spacing. It can occupy
  /// an otherwise empty page and does not imply source/semantic coverage. Each
  /// advance handles at most one page; huge values still obey maxPages. Caller
  /// supplies already resolved padding, not a collapsible margin.
  void appendPadding(
    double extent, {
    double spaceBefore = 0,
    double spaceAtPageStart = 0,
  }) {
    _ensureOpen();
    if (!needsInput) throw StateError('Composition input is still pending');
    if (!extent.isFinite ||
        extent < 0 ||
        !spaceBefore.isFinite ||
        !spaceAtPageStart.isFinite ||
        spaceAtPageStart < 0) {
      throw ArgumentError.value(extent, 'extent');
    }
    _padding = _ActivePadding(extent, spaceBefore, spaceAtPageStart);
  }

  ({double extentConsumed, int pagesPublished, bool isComplete})
  advancePadding() {
    _ensureOpen();
    final active = _padding;
    if (active == null) throw StateError('No padding is pending');
    final pagesBefore = _pages.length;
    try {
      if (active.remaining == 0) {
        _padding = null;
        return (extentConsumed: 0.0, pagesPublished: 0, isComplete: true);
      }
      if (!active.started) {
        final atPageStart = _draft.isEmpty && _usedHeight == 0;
        final gap = atPageStart ? active.spaceAtPageStart : active.spaceBefore;
        final top = math.max(0.0, _flowHeight + gap);
        if (!top.isFinite) _fail(ForumBodyTextPageFailure.invalidGeometry);
        if (top >= height) {
          if (atPageStart) _fail(ForumBodyTextPageFailure.oversizedGroup);
          _seal();
          return (extentConsumed: 0.0, pagesPublished: 1, isComplete: false);
        }
        _flowHeight = top;
        active.started = true;
      }
      final consumed = math.min(active.remaining, height - _flowHeight);
      _touchBackgrounds(_flowHeight);
      _flowHeight += consumed;
      _usedHeight = math.max(_usedHeight, _flowHeight);
      final after = active.remaining - consumed;
      // Subtracting a page remainder must not create a subpixel-only new page
      // for values such as 0.1 + 0.2. Padding carries no source text coverage.
      active.remaining = after;
      if (after <= precisionErrorTolerance) _padding = null;
      if (_usedHeight == height &&
          (_padding != null || !_backgrounds.needsEndBoundary)) {
        _seal();
      }
      return (
        extentConsumed: consumed,
        pagesPublished: _pages.length - pagesBefore,
        isComplete: _padding == null,
      );
    } catch (_) {
      close();
      rethrow;
    }
  }

  /// Budget counts inspected physical rows, including rows inside a protected
  /// grapheme. Such a group can span several calls before it can be placed.
  /// A call that publishes a page may inspect zero new rows: its known pending
  /// group remains for the next page. This is publication progress, not a stall.
  ({int linesInspected, int pagesPublished, bool paragraphCompleted}) advance({
    required int maxLines,
  }) {
    _ensureOpen();
    if (maxLines <= 0) throw ArgumentError.value(maxLines, 'maxLines');
    if (_active == null) throw StateError('No paragraph is pending');
    final pagesBefore = _pages.length;
    var inspected = 0;
    try {
      final active = _active!;
      final layout = active.input;
      layout.ensureActive();
      _ensureOpen();
      while (true) {
        if (layout.lines.isEmpty && active.groupEnd == null) {
          active.groupEnd = 0;
        }
        while (active.groupEnd == null && inspected < maxLines) {
          if (active.scanLine >= active.endLine) {
            _fail(ForumBodyTextPageFailure.invalidGeometry);
          }
          final line = layout.lines[active.scanLine++];
          inspected++;
          if (line.canBreakAfter) active.groupEnd = active.scanLine;
        }
        final end = active.groupEnd;
        if (end == null) return _result(inspected, pagesBefore, false);
        final continuation =
            _draft.isNotEmpty && _draft.last.paragraphIndex == active.index;
        if (!continuation &&
            maxDeliveriesPerPage != null &&
            _draft.length >= maxDeliveriesPerPage!) {
          _seal();
          return _result(inspected, pagesBefore, false);
        }
        final firstLine = continuation
            ? _draft.last.startLine
            : active.nextLine;
        final atPageStart = _draft.isEmpty && _usedHeight == 0;
        final gap = active.nextLine == active.firstLine
            ? (atPageStart ? active.spaceAtPageStart : active.spaceBefore)
            : 0.0;
        final marker = continuation
            ? _draft.last.listMarker
            : active.nextLine == active.firstLine && active.listMarkers != null
            ? ForumBodyTextPageListMarker._(
                layout.alphabeticBaseline,
                active.listMarkers!.bounds.shift(
                  Offset(0, layout.alphabeticBaseline),
                ),
              )
            : null;
        final top = continuation
            ? _draft.last.top
            : math.max(0.0, _flowHeight + gap) +
                  math.max(0.0, -(marker?.bounds.top ?? 0));
        final view = layout.lines.isEmpty
            ? null
            : layout.fragment(firstLine, end);
        final fragmentHeight = view?.height ?? layout.height;
        final bottom =
            top + math.max(fragmentHeight, marker?.bounds.bottom ?? 0);
        if (marker != null &&
            (active.left + marker.bounds.left < -precisionErrorTolerance ||
                active.left + marker.bounds.right >
                    width + precisionErrorTolerance)) {
          _fail(ForumBodyTextPageFailure.invalidGeometry);
        }
        if (!fragmentHeight.isFinite ||
            fragmentHeight < 0 ||
            !bottom.isFinite ||
            bottom < top) {
          _fail(ForumBodyTextPageFailure.invalidGeometry);
        }
        if (bottom > height) {
          if (_draft.isEmpty && _usedHeight == 0) {
            _fail(ForumBodyTextPageFailure.oversizedGroup);
          }
          _seal();
          return _result(inspected, pagesBefore, false);
        }
        if (!continuation && _fragmentCount >= maxFragments) {
          _fail(ForumBodyTextPageFailure.fragmentLimit);
        }
        final emphasis = layout._emphasisEntries;
        _EmphasisSceneReservation? scene;
        _EmphasisSceneAddition? sceneAddition;
        if (emphasis != null) {
          scene = continuation
              ? _lastSceneReservation!
              : _EmphasisSceneReservation(
                  emphasis.inLines(firstLine, end).first.group.top,
                );
          sceneAddition = scene.propose(
            emphasis
                .inLines(active.nextLine, end)
                .map((p) => p.sceneContribution),
          );
          if (!sceneAddition.withinLimits ||
              fragmentHeight >
                  ForumBodyEmphasisFragmentInputPreparation.defaultMaxHeight) {
            if (_draft.isEmpty && _usedHeight == 0) {
              _fail(ForumBodyTextPageFailure.sceneLimit);
            }
            _seal();
            return _result(inspected, pagesBefore, false);
          }
        }
        final frames = layout._frames;
        if (frames != null) {
          scene = continuation
              ? _lastSceneReservation!
              : _EmphasisSceneReservation(
                  frames.lines[firstLine].top,
                  maxGroups: frames.lines.length,
                  maxCommands: ForumBodyTextPictureInput.maximumCommands,
                );
          sceneAddition = scene.propose([
            for (var row = active.nextLine; row < end; row++)
              frames.sceneContributionForRow(row),
          ]);
          if (!sceneAddition.withinLimits || fragmentHeight > 32768) {
            if (_draft.isEmpty && _usedHeight == 0) {
              _fail(ForumBodyTextPageFailure.sceneLimit);
            }
            _seal();
            return _result(inspected, pagesBefore, false);
          }
        }
        final replacedSceneBytes = continuation
            ? (_lastSceneReservation?.estimatedBytes ?? 0)
            : 0;
        final proposedSceneEntries =
            _sceneEntries +
            (sceneAddition == null || sceneAddition.commands == 0 ? 0 : 1) -
            (continuation && (_lastSceneReservation?.estimatedBytes ?? 0) > 0
                ? 1
                : 0);
        final proposedSceneBytes =
            _sceneBytes -
            replacedSceneBytes +
            (sceneAddition?.estimatedBytes ?? 0);
        final limit = maxNativeHandlesPerPage;
        final bodyHandles = limit == null
            ? 0
            : emphasis != null
            ? 2
            : frames != null
            ? frames.preparationParentHandleCount(firstLine, end) +
                  frames.allocation.input.natural.page.nativeHandleCountInRange(
                    view?.coverageStartUtf16 ?? 0,
                    view?.coverageEndUtf16 ?? 0,
                  ) -
                  1
            : layout.nativeHandleCountInRange?.call(
                    view?.coverageStartUtf16 ?? 0,
                    view?.coverageEndUtf16 ?? 0,
                  ) ??
                  1;
        final handles =
            bodyHandles +
            (marker == null || limit == null
                ? 0
                : 1 + 2 * active.listMarkers!.fontCount);
        if (limit != null && handles <= 0) {
          _fail(ForumBodyTextPageFailure.invalidGeometry);
        }
        final replaced = continuation ? _lastFragmentNativeHandles : 0;
        final proposed = _usedNativeHandles - replaced + handles;
        if (limit != null && proposed > limit) {
          if (_draft.isEmpty && _usedHeight == 0) {
            _fail(ForumBodyTextPageFailure.nativeHandleLimit);
          }
          _seal();
          return _result(inspected, pagesBefore, false);
        }
        Map<Object, int>? addedEntries;
        final entryLimit = maxNativeEntriesPerPage;
        final byteLimit = maxNativeEstimatedBytesPerPage;
        var addedBytes = 0;
        if (entryLimit != null || byteLimit != null) {
          final from = layout.lines.isEmpty
              ? 0
              : layout.lines[active.nextLine].coverageStartUtf16;
          addedEntries = <Object, int>{};
          if (byteLimit != null) {
            final costs =
                emphasis?.fontCostsInLines(active.nextLine, end) ??
                layout.nativeCostsInRange?.call(
                  from,
                  view?.coverageEndUtf16 ?? 0,
                ) ??
                [
                  (
                    identity: layout.lease!.nativeInputIdentity,
                    estimatedBytes: layout.lease!.nativeLayoutEstimatedBytes,
                  ),
                ];
            for (final cost in costs) {
              if (cost.estimatedBytes <= 0) {
                _fail(ForumBodyTextPageFailure.invalidGeometry);
              }
              addedEntries[cost.identity] = math.max(
                addedEntries[cost.identity] ?? 0,
                cost.estimatedBytes,
              );
            }
          } else {
            for (final entry
                in emphasis
                        ?.fontCostsInLines(active.nextLine, end)
                        .map((cost) => cost.identity) ??
                    layout.nativeEntriesInRange?.call(
                      from,
                      view?.coverageEndUtf16 ?? 0,
                    ) ??
                    layout.nativeCostsInRange
                        ?.call(from, view?.coverageEndUtf16 ?? 0)
                        .map((cost) => cost.identity) ??
                    [layout.lease!.nativeInputIdentity]) {
              addedEntries[entry] = 0;
            }
          }
          _ensureOpen();
          layout.ensureActive();
          if (marker != null && !continuation) {
            for (final cost in active.listMarkers!.costs) {
              addedEntries[cost.identity] = math.max(
                addedEntries[cost.identity] ?? 0,
                cost.estimatedBytes,
              );
            }
          }
          if (addedEntries.isEmpty) {
            _fail(ForumBodyTextPageFailure.invalidGeometry);
          }
          final proposedEntries =
              _nativeEntries.length +
              proposedSceneEntries +
              addedEntries.keys
                  .where((entry) => !_nativeEntries.containsKey(entry))
                  .length;
          if (entryLimit != null && proposedEntries > entryLimit) {
            if (_draft.isEmpty && _usedHeight == 0) {
              _fail(ForumBodyTextPageFailure.nativeEntryLimit);
            }
            _seal();
            return _result(inspected, pagesBefore, false);
          }
          for (final entry in addedEntries.entries) {
            final old = _nativeEntries[entry.key] ?? 0;
            addedBytes += math.max(0, entry.value - old);
            addedEntries[entry.key] = math.max(old, entry.value);
          }
          if (byteLimit != null &&
              _nativeBytes + addedBytes + proposedSceneBytes > byteLimit) {
            if (_draft.isEmpty && _usedHeight == 0) {
              _fail(ForumBodyTextPageFailure.nativeByteLimit);
            }
            _seal();
            return _result(inspected, pagesBefore, false);
          }
        }
        // Only inspect newly consumed display text. Reordered source windows
        // need actual range envelopes; rescanning a growing fragment for every
        // appended row would make continuation composition quadratic.
        final addedHint = forumBodySourceHint(
          layout.projection,
          layout.lines.isEmpty
              ? 0
              : layout.lines[active.nextLine].coverageStartUtf16,
          view?.coverageEndUtf16 ?? 0,
        );
        final previousHint = continuation ? _draft.last.sourceHint : null;
        final sourceHint = previousHint == null
            ? addedHint
            : addedHint == null
            ? previousHint
            : (
                runeStart: math.min(
                  previousHint.runeStart,
                  addedHint.runeStart,
                ),
                runeEnd: math.max(previousHint.runeEnd, addedHint.runeEnd),
              );
        final fragment = ForumBodyTextPageFragment._(
          paragraphIndex: active.index,
          path: layout.path,
          fontRevision: layout.fontRevision,
          styleRevision: layout.styleRevision,
          startLine: firstLine,
          endLine: end,
          coverageStartUtf16: view?.coverageStartUtf16 ?? 0,
          coverageEndUtf16: view?.coverageEndUtf16 ?? 0,
          sourceHint: sourceHint,
          left: active.left,
          top: top,
          width: layout.width,
          height: fragmentHeight,
          kind: layout.kind,
          listMarker: marker,
        );
        _touchBackgrounds(top + math.min(0, marker?.bounds.top ?? 0));
        if (!continuation && _fragmentCount >= maxFragments) {
          _fail(ForumBodyTextPageFailure.fragmentLimit);
        }
        if (continuation) {
          _draft[_draft.length - 1] = fragment;
        } else {
          _draft.add(fragment);
          _fragmentCount++;
        }
        _usedNativeHandles = proposed;
        if (addedEntries != null) _nativeEntries.addAll(addedEntries);
        _nativeBytes += addedBytes;
        if (scene != null) scene.apply(sceneAddition!);
        _lastSceneReservation = scene;
        _sceneEntries = proposedSceneEntries;
        _sceneBytes = proposedSceneBytes;
        _lastFragmentNativeHandles = handles;
        _flowHeight = bottom;
        _usedHeight = math.max(_usedHeight, bottom);
        active.nextLine = end;
        active.scanLine = end;
        active.groupEnd = null;
        final paragraphComplete = end == active.endLine;
        if (paragraphComplete) {
          active.input.lease?.release();
          _active = null;
          _nextParagraphIndex++;
        }
        // A still-open rounded box can end at this exact edge. Resolve its
        // actual close/continuation before publishing immutable corner metadata.
        if (_usedHeight == height &&
            (!paragraphComplete || !_backgrounds.needsEndBoundary)) {
          _seal();
        }
        if (paragraphComplete ||
            inspected >= maxLines ||
            _pages.length != pagesBefore) {
          return _result(inspected, pagesBefore, paragraphComplete);
        }
      }
    } catch (_) {
      close();
      rethrow;
    }
  }

  ({int linesInspected, int pagesPublished, bool paragraphCompleted}) _result(
    int inspected,
    int pagesBefore,
    bool complete,
  ) => (
    linesInspected: inspected,
    pagesPublished: _pages.length - pagesBefore,
    paragraphCompleted: complete,
  );

  /// Called only after the upstream block stream reaches EOF. Completion does
  /// not independently prove that the caller consumed all original IR nodes.
  void finish() {
    _ensureOpen();
    if (!needsInput) throw StateError('Composition input is still pending');
    if (!_backgrounds.isBalanced) throw StateError('Unclosed page background');
    try {
      if (_draft.isNotEmpty || _usedHeight > 0) _seal();
      _complete = true;
      _snapshot = null;
    } catch (_) {
      close();
      rethrow;
    }
  }

  void _seal() {
    if (_pages.length >= maxPages) _fail(ForumBodyTextPageFailure.pageLimit);
    _pages.add(
      ForumBodyTextPage._(
        _pages.length,
        _draft,
        _rules,
        _backgrounds.seal(height),
        _usedHeight,
      ),
    );
    _draft.clear();
    _rules.clear();
    _usedNativeHandles = 0;
    _nativeEntries.clear();
    _nativeBytes = 0;
    _lastFragmentNativeHandles = 0;
    _sceneEntries = 0;
    _sceneBytes = 0;
    _lastSceneReservation = null;
    _usedHeight = 0;
    _flowHeight = 0;
    _snapshot = null;
  }

  Never _fail(ForumBodyTextPageFailure failure) =>
      throw ForumBodyTextPageException(failure);
  void _ensureOpen() {
    if (_closed || _complete) throw StateError('Page composition is closed');
  }

  /// Retire only unpublished work. Existing snapshots keep their fixed prefix.
  void close() {
    if (_closed) return;
    _closed = true;
    _active?.input.lease?.release();
    _active = null;
    _padding = null;
    _rule = null;
    _image = null;
    _fragmentCount -= _draft.length + _rules.length + _backgrounds.itemCount;
    _draft.clear();
    _rules.clear();
    _backgrounds.clear();
    _usedNativeHandles = 0;
    _nativeEntries.clear();
    _nativeBytes = 0;
    _lastFragmentNativeHandles = 0;
    _sceneEntries = 0;
    _sceneBytes = 0;
    _lastSceneReservation = null;
    _usedHeight = 0;
    _flowHeight = 0;
  }
}

final class _ActiveImage {
  const _ActiveImage(
    this.path,
    this.frame,
    this.index,
    this.fontRevision,
    this.styleRevision,
    this.left,
    this.spaceBefore,
  );
  final String path, fontRevision;
  final ForumBodyImageFrame frame;
  final int index, styleRevision;
  final double left, spaceBefore;
}

final class _ActiveRule {
  const _ActiveRule(
    this.path,
    this.left,
    this.width,
    this.thickness,
    this.color,
    this.spaceBefore,
    this.spaceAtPageStart,
  );
  final String path;
  final double left, width, thickness, spaceBefore, spaceAtPageStart;
  final Color color;
}

/// One private typed adapter for the sole active input. Only numeric fragment
/// records reach snapshots; no native layout, callback or child lease is stored
/// in a published page. Keep both public lease APIs concrete.
final class _CompositionParagraph {
  _CompositionParagraph.paragraph(ForumBodyParagraphLease current)
    : lease = current,
      nativeHandleCountInRange = null,
      nativeEntriesInRange = null,
      nativeCostsInRange = null,
      _text = current.layout,
      _inline = null,
      _emphasisEntries = null,
      _fitted = null,
      _frames = null,
      _emphasisGuard = null,
      identity = current.content.identity,
      path = current.content.path,
      fontRevision = current.content.fontRevision,
      styleRevision = current.content.styleRevision,
      projection = current.content.projection,
      kind = ForumBodyTextPageFragmentKind.paragraph {
    if (current.content.isSourceFree) {
      throw ArgumentError('Anonymous font struts are not document paragraphs');
    }
  }
  _CompositionParagraph.inline(
    ForumBodyInlineParagraphLease current,
    this.nativeHandleCountInRange,
    this.nativeEntriesInRange,
    this.nativeCostsInRange,
    this._frames,
  ) : lease = current,
      _text = null,
      _inline = current.layout,
      _emphasisEntries = null,
      _fitted = null,
      _emphasisGuard = null,
      identity = current.content.identity,
      path = current.content.path,
      fontRevision = current.content.fontRevision,
      styleRevision = current.content.styleRevision,
      projection = current.content.projection.display,
      kind = ForumBodyTextPageFragmentKind.inline {
    final frames = _frames;
    if (frames != null &&
        (!identical(
              frames.allocation.input.reference.naturalLines,
              current.layout.lines,
            ) ||
            !identical(frames.source.content, current.content) ||
            frames.width != current.layout.width)) {
      throw ArgumentError(
        'Allocated composition requires the current natural parent',
      );
    }
  }
  _CompositionParagraph.emphasis(
    ForumBodyEmphasisParagraphNativeEntries entries,
    void Function() ensureOwner,
  ) : lease = null,
      _text = null,
      _inline = null,
      _emphasisEntries = entries,
      _fitted = null,
      _frames = null,
      _emphasisGuard = ensureOwner,
      nativeHandleCountInRange = null,
      nativeEntriesInRange = null,
      nativeCostsInRange = null,
      identity = entries.paragraph.content.identity,
      path = entries.paragraph.content.path,
      fontRevision = entries.paragraph.content.fontRevision,
      styleRevision = entries.paragraph.content.styleRevision,
      projection = entries.paragraph.content.projection,
      kind = ForumBodyTextPageFragmentKind.emphasis {
    if (entries.groups.isEmpty) {
      throw ArgumentError('Empty struts require an actual paragraph input');
    }
  }
  final ForumBodyNativeParagraphLease? lease;
  _CompositionParagraph.fitted(
    ForumBodyFittedEmphasisPlan plan,
    void Function() ensureOwner,
  ) : lease = null,
      _text = null,
      _inline = null,
      _emphasisEntries = null,
      _fitted = plan,
      _frames = null,
      _emphasisGuard = ensureOwner,
      nativeHandleCountInRange = ((_, _) => 2),
      nativeEntriesInRange = null,
      nativeCostsInRange = ((_, _) => plan.nativeCosts),
      identity = plan.content.identity,
      path = plan.content.path,
      fontRevision = plan.content.fontRevision,
      styleRevision = plan.content.styleRevision,
      projection = plan.content.projection,
      kind = ForumBodyTextPageFragmentKind.fittedEmphasis;
  final ForumBodyFittedEmphasisPlan? _fitted;
  final ForumBodyInlineFontFramePlan? _frames;
  final ForumBodyEmphasisParagraphNativeEntries? _emphasisEntries;
  final void Function()? _emphasisGuard;
  final int Function(int startUtf16, int endUtf16)? nativeHandleCountInRange;
  final Iterable<Object> Function(int startUtf16, int endUtf16)?
  nativeEntriesInRange;
  final Iterable<ForumBodyNativeInputCost> Function(
    int startUtf16,
    int endUtf16,
  )?
  nativeCostsInRange;
  final ForumBodyParagraphLayout? _text;
  final ForumBodyInlineParagraphLayout? _inline;
  final ForumBodyIdentity identity;
  final String? path;
  final String fontRevision;
  final int styleRevision;
  final HtmlDisplayTextProjection projection;
  final ForumBodyTextPageFragmentKind kind;
  double get width =>
      _frames?.width ??
      _fitted?.metrics.width ??
      _emphasisEntries?.paragraph.width ??
      _text?.width ??
      _inline!.width;
  double get height =>
      _frames?.height ??
      _fitted?.metrics.height ??
      _emphasisEntries?.paragraph.height ??
      _text?.height ??
      _inline!.height;
  List<ForumBodyParagraphLine> get lines =>
      _frames?.lines ??
      _fitted?.lines ??
      _emphasisEntries?.paragraph.lines ??
      _text?.lines ??
      _inline!.lines;
  double get alphabeticBaseline =>
      (_frames?.lines.first.baseline) ??
      _fitted?.metrics.alphabeticBaseline ??
      _emphasisEntries?.paragraph.alphabeticBaseline ??
      _text?.alphabeticBaseline ??
      (_inline!.lines.isEmpty
          ? _inline.nativeAlphabeticBaseline
          : _inline.lines.first.baseline);
  void ensureActive() {
    if (_emphasisEntries != null || _fitted != null) {
      _emphasisGuard!();
      return;
    }
    if (!lease!.isActive || (_text?.isDisposed ?? _inline!.isDisposed)) {
      throw StateError('Composition paragraph lease is retired');
    }
  }

  ({int startLine, int endLine}) lineWindow(ForumBodyParagraphWindow window) {
    if (_fitted != null) {
      if (window != ForumBodyParagraphWindow.full) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.coverage,
        );
      }
      return (startLine: 0, endLine: 1);
    }
    return _emphasisEntries?.paragraph.lineWindow(window) ??
        _text?.lineWindow(window) ??
        _inline!.lineWindow(window);
  }

  ({double height, int coverageStartUtf16, int coverageEndUtf16}) fragment(
    int start,
    int end,
  ) {
    if (_fitted != null) {
      if (start != 0 || end != 1) {
        throw RangeError('Fitted line must stay complete');
      }
      return (
        height: _fitted.metrics.height,
        coverageStartUtf16: _fitted.lines.single.coverageStartUtf16,
        coverageEndUtf16: _fitted.lines.single.coverageEndUtf16,
      );
    }
    final emphasis = _emphasisEntries;
    if (emphasis != null) {
      final view = emphasis.paragraph.fragment(start, end);
      return (
        height: view.height,
        coverageStartUtf16: view.coverageStartUtf16,
        coverageEndUtf16: view.coverageEndUtf16,
      );
    }
    final text = _text;
    if (text != null) {
      final view = text.fragment(start, end);
      return (
        height: view.height,
        coverageStartUtf16: view.coverageStartUtf16,
        coverageEndUtf16: view.coverageEndUtf16,
      );
    }
    if (_frames case final frames?) {
      final view = frames.fragment(start, end);
      return (
        height: view.height,
        coverageStartUtf16: view.coverageStartUtf16,
        coverageEndUtf16: view.coverageEndUtf16,
      );
    }
    final view = _inline!.fragment(start, end);
    return (
      height: view.height,
      coverageStartUtf16: view.coverageStartUtf16,
      coverageEndUtf16: view.coverageEndUtf16,
    );
  }
}

final class _ActivePadding {
  _ActivePadding(this.remaining, this.spaceBefore, this.spaceAtPageStart);
  double remaining;
  final double spaceBefore;
  final double spaceAtPageStart;
  bool started = false;
}

final class _ActiveParagraph {
  _ActiveParagraph(
    this.input,
    this.index,
    this.left,
    this.spaceBefore,
    this.spaceAtPageStart,
    this.firstLine,
    this.endLine,
    this.listMarkers,
  ) : nextLine = firstLine,
      scanLine = firstLine;
  final _CompositionParagraph input;
  final int index;
  final double left;
  final double spaceBefore;
  final double spaceAtPageStart;
  final int firstLine;
  final int endLine;
  final ForumBodyListMarkerPlan? listMarkers;
  int nextLine;
  int scanLine;
  int? groupEnd;
}
