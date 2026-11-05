import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../models/novel_reader_native_anchor_map.dart';
import '../models/novel_reader_native_page_coverage.dart';

enum NovelReaderNativeCoverageState { active, complete, failed, closed }

enum NovelReaderNativeCoverageFailure { identity, budget, retired }

final class NovelReaderNativeCoverageException implements Exception {
  const NovelReaderNativeCoverageException(this.failure);
  final NovelReaderNativeCoverageFailure failure;
  @override
  String toString() => 'NovelReaderNativeCoverageException(${failure.name})';
}

final class NovelReaderNativeCoverageLimits {
  const NovelReaderNativeCoverageLimits({
    this.maxFragments = 256,
    this.maxGraphemes = 16384,
    this.maxPoints = 8192,
    this.maxResources = 1024,
  });
  final int maxFragments;
  final int maxGraphemes;
  final int maxPoints;
  final int maxResources;
}

final class NovelReaderNativeCoverageStep {
  const NovelReaderNativeCoverageStep(
    this.graphemesChecked,
    this.fragmentsCompleted,
    this.isComplete, {
    this.resourcesChecked = 0,
  });
  final int graphemesChecked;
  final int fragmentsCompleted;
  final bool isComplete;
  final int resourcesChecked;
  bool get madeProgress =>
      graphemesChecked > 0 ||
      resourcesChecked > 0 ||
      fragmentsCompleted > 0 ||
      isComplete;
}

/// Borrows a prepared page's live leases; never shapes, acquires or releases
/// them. Partial proof stays private. Terminal cursors drop all owner/native
/// references. The caller schedules advances outside Widget build.
final class NovelReaderNativePageCoverageCursor {
  factory NovelReaderNativePageCoverageCursor({
    required NovelReaderNativeAnchorMap anchors,
    required ForumBodyTextPageSnapshot snapshot,
    required int pageIndex,
    required String layoutId,
    required List<ForumBodyParagraphLease> leases,
    NovelReaderNativeCoverageLimits limits =
        const NovelReaderNativeCoverageLimits(),
  }) {
    validateForumBodyTextPageBinding(
      snapshot: snapshot,
      pageIndex: pageIndex,
      layoutId: layoutId,
      leases: leases,
    );
    return NovelReaderNativePageCoverageCursor.prepared(
      anchors: anchors,
      snapshot: snapshot,
      pageIndex: pageIndex,
      layoutId: layoutId,
      fragments: [
        for (final (index, lease) in leases.indexed)
          ForumBodyPreparedTextFragment.paragraph(
            lease: lease,
            startLine: snapshot[pageIndex].fragments[index].startLine,
            endLine: snapshot[pageIndex].fragments[index].endLine,
          ),
      ],
      limits: limits,
    );
  }

  factory NovelReaderNativePageCoverageCursor.prepared({
    required NovelReaderNativeAnchorMap anchors,
    required ForumBodyTextPageSnapshot snapshot,
    required int pageIndex,
    required String layoutId,
    required List<ForumBodyPreparedTextFragment> fragments,
    Rect? viewportClip,
    NovelReaderNativeCoverageLimits limits =
        const NovelReaderNativeCoverageLimits(),
  }) {
    if (limits.maxFragments < 0 ||
        limits.maxGraphemes < 0 ||
        limits.maxPoints < 0 ||
        limits.maxResources < 0) {
      throw ArgumentError('Invalid native coverage limits');
    }
    if (anchors.identity != snapshot.identity) {
      _fail(NovelReaderNativeCoverageFailure.identity);
    }
    if (viewportClip != null &&
        (!viewportClip.isFinite || viewportClip.isEmpty)) {
      throw ArgumentError.value(viewportClip, 'viewportClip');
    }
    if (snapshot[pageIndex].itemCount > limits.maxFragments) {
      _fail(NovelReaderNativeCoverageFailure.budget);
    }
    validateForumBodyPreparedTextPageBinding(
      snapshot: snapshot,
      pageIndex: pageIndex,
      layoutId: layoutId,
      fragments: fragments,
    );
    return NovelReaderNativePageCoverageCursor._(
      anchors,
      snapshot,
      pageIndex,
      layoutId,
      List.unmodifiable(fragments),
      limits,
      viewportClip,
    );
  }

  NovelReaderNativePageCoverageCursor._(
    this._anchors,
    this._snapshot,
    this.pageIndex,
    this.layoutId,
    this._fragments,
    this.limits,
    this._viewportClip,
  );

  NovelReaderNativeAnchorMap? _anchors;
  ForumBodyTextPageSnapshot? _snapshot;
  List<ForumBodyPreparedTextFragment> _fragments;
  final int pageIndex;
  final String layoutId;
  final NovelReaderNativeCoverageLimits limits;
  final Rect? _viewportClip;
  final _points = <NovelReaderNativeCoveragePoint>[];
  final _images = <NovelReaderNativeImageCoverage>[];
  NovelReaderNativeCoverageState _state = NovelReaderNativeCoverageState.active;
  NovelReaderNativePageCoverage? _result;
  int _fragmentIndex = 0;
  int _graphemes = 0;
  int _resourceCount = 0;
  Iterator<_ImageCoverageInput>? _resources;
  bool _resourcesComplete = false;
  bool _hasClippedGlyphs = false;
  bool _hasClippedResources = false;
  bool _hasUnanchoredImages = false;
  Iterator<({int startUtf16, int endUtf16})>? _ranges;
  ForumBodyPreparedTextFragment? _fragment;
  HtmlDisplayTextProjection? _projection;
  List<ForumBodyParagraphRun> _runs = const [];
  Rect _clip = Rect.zero;

  NovelReaderNativeCoverageState get state => _state;
  int get checkedGraphemes => _graphemes;
  NovelReaderNativePageCoverage get result =>
      _state == NovelReaderNativeCoverageState.complete
      ? _result!
      : throw StateError('Native page coverage is not complete');

  NovelReaderNativeCoverageStep advance({
    required int maxGraphemes,
    required int maxFragments,
    int maxResources = 32,
  }) {
    if (_state != NovelReaderNativeCoverageState.active) {
      throw StateError('Native coverage cursor is retired');
    }
    if (maxGraphemes <= 0 || maxFragments <= 0 || maxResources <= 0) {
      throw ArgumentError('Native coverage work budgets must be positive');
    }
    var checked = 0;
    var fragments = 0;
    var resources = 0;
    try {
      _ensureLive();
      final page = _snapshot![pageIndex];
      while (checked < maxGraphemes && fragments < maxFragments) {
        if (_fragmentIndex == page.fragments.length) {
          _finish();
          break;
        }
        _ranges ??= _openFragment(page.fragments[_fragmentIndex]);
        if (!_resourcesComplete) {
          if (resources >= maxResources) break;
          if (_resources!.moveNext()) {
            if (_resourceCount >= limits.maxResources) {
              _fail(NovelReaderNativeCoverageFailure.budget);
            }
            _resourceCount++;
            resources++;
            _includeImage(_resources!.current);
            continue;
          }
          _resources = null;
          _resourcesComplete = true;
        }
        if (!_ranges!.moveNext()) {
          _fragmentIndex++;
          fragments++;
          _ranges = null;
          _fragment = null;
          _projection = null;
          _runs = const [];
          continue;
        }
        if (_graphemes >= limits.maxGraphemes) {
          _fail(NovelReaderNativeCoverageFailure.budget);
        }
        _graphemes++;
        checked++;
        final range = _ranges!.current;
        _includeGrapheme(range.startUtf16, range.endUtf16);
      }
      if (_fragmentIndex == page.fragments.length &&
          _state == NovelReaderNativeCoverageState.active) {
        _finish();
      }
      return NovelReaderNativeCoverageStep(
        checked,
        fragments,
        _state == NovelReaderNativeCoverageState.complete,
        resourcesChecked: resources,
      );
    } catch (_) {
      _state = NovelReaderNativeCoverageState.failed;
      _dropBorrowed();
      rethrow;
    }
  }

  Iterator<({int startUtf16, int endUtf16})> _openFragment(
    ForumBodyTextPageFragment fragment,
  ) {
    final prepared = _fragments[_fragmentIndex];
    _fragment = prepared;
    _resourcesComplete = fragment.imageCount == 0;
    _resources = _resourcesComplete ? null : _imageInputs(prepared).iterator;
    // These inputs are immutable for this delivery. Re-reading mixed fragment
    // getters per grapheme repeatedly scans every child lease. Native geometry
    // and the per-step lifetime guard still validate the current ownership.
    final projection = _projection = prepared.projection;
    _runs = prepared.runs;
    final snapshot = _snapshot!;
    var pageClip = Rect.fromLTWH(0, 0, snapshot.width, snapshot.height);
    if (_viewportClip case final viewport?) {
      pageClip = pageClip.intersect(viewport);
    }
    pageClip = pageClip.shift(Offset(-fragment.left, -fragment.top));
    for (final box in prepared.decorationBounds) {
      if (box.left < pageClip.left - precisionErrorTolerance ||
          box.right > pageClip.right + precisionErrorTolerance ||
          box.top < pageClip.top - precisionErrorTolerance ||
          box.bottom > pageClip.bottom + precisionErrorTolerance) {
        _hasClippedGlyphs = true;
      }
    }
    _clip = Rect.fromLTWH(
      0,
      0,
      fragment.width,
      fragment.height,
    ).intersect(pageClip);
    if (fragment.kind == ForumBodyTextPageFragmentKind.image) {
      return const <({int startUtf16, int endUtf16})>[].iterator;
    }
    if (_clip.isEmpty) {
      return const <({int startUtf16, int endUtf16})>[].iterator;
    }
    return projection
        .graphemeRanges(
          startUtf16: fragment.coverageStartUtf16,
          endUtf16: fragment.coverageEndUtf16,
        )
        .iterator;
  }

  void _includeGrapheme(int start, int end) {
    final prepared = _fragment!;
    final projection = _projection!;
    if (!_visibleStyles(projection, _runs, start, end)) return;
    final boxes = prepared.glyphBoxes(start, end);
    Rect? bounds;
    if (boxes.isEmpty) {
      // An explicit separator belongs to the preceding physical row, even
      // when the engine emits no selection box. Require that entire measured
      // row to fit; do not invent a caret or blank-line height.
      for (final line in prepared.lines) {
        if (line.endUtf16 != start || line.coverageEndUtf16 != end) continue;
        final row = Rect.fromLTRB(
          line.left,
          line.top,
          line.left + line.width,
          line.bottom,
        );
        if (_contains(row)) {
          bounds = row;
          break;
        }
      }
      if (bounds == null) return;
    } else {
      for (final box in boxes) {
        final rect = box.toRect();
        if (!_contains(rect)) {
          _hasClippedGlyphs = true;
          return;
        }
        if (_viewportClip != null) {
          bounds = bounds?.expandToInclude(rect) ?? rect;
        }
      }
    }
    final captured = _viewportClip == null ? null : bounds;
    _addPoint(projection, start, HtmlProjectionAffinity.downstream, captured);
    _addPoint(projection, end, HtmlProjectionAffinity.upstream, captured);
  }

  bool _contains(Rect box) =>
      box.height > 0 &&
      box.left >= _clip.left - precisionErrorTolerance &&
      box.right <= _clip.right + precisionErrorTolerance &&
      box.top >= _clip.top - precisionErrorTolerance &&
      box.bottom <= _clip.bottom + precisionErrorTolerance;

  void _addPoint(
    HtmlDisplayTextProjection projection,
    int offset,
    HtmlProjectionAffinity affinity,
    Rect? bounds,
  ) {
    final source = projection.sourceAtUtf16(offset, affinity: affinity);
    final anchor = _anchors!.anchorAtSourceRune(
      source.sourceRune,
      affinity: affinity,
      requireAdjacentOrigin: true,
    );
    if (anchor == null) return;
    if (_points.length + _images.length >= limits.maxPoints) {
      _fail(NovelReaderNativeCoverageFailure.budget);
    }
    _points.add(
      NovelReaderNativeCoveragePoint(
        anchor: anchor,
        fragmentIndex: _fragmentIndex,
        displayUtf16: offset,
        sourceRune: source.sourceRune,
        affinity: affinity,
        fragmentBounds: bounds,
      ),
    );
  }

  void _includeImage(_ImageCoverageInput image) {
    final source = _anchors!.imageAtPath(image.path), entry = image.entry;
    if (image.isSticker) {
      if (entry != null || source != null || image.atomIndex == null) {
        _fail(NovelReaderNativeCoverageFailure.identity);
      }
      _hasUnanchoredImages = true;
      _hasClippedResources |= !_contains(image.rect);
      return;
    }
    if (source == null ||
        entry == null ||
        source.rawSource != entry.rawSrc ||
        source.url != entry.url ||
        source.imageIndex != entry.index) {
      _fail(NovelReaderNativeCoverageFailure.identity);
    }
    if (!_contains(image.rect)) {
      _hasClippedResources = true;
      return;
    }
    if (_points.length + _images.length >= limits.maxPoints) {
      _fail(NovelReaderNativeCoverageFailure.budget);
    }
    _images.add(
      NovelReaderNativeImageCoverage(
        anchor: source.anchor,
        fragmentIndex: _fragmentIndex,
        path: source.path,
        imageIndex: source.imageIndex,
        rect: image.rect,
        inlineAtomIndex: image.atomIndex,
        parentDisplayFenceUtf16: image.fence,
      ),
    );
  }

  void _ensureLive() {
    if (_fragments.any((fragment) => !fragment.isActive)) {
      _fail(NovelReaderNativeCoverageFailure.retired);
    }
  }

  void _finish() {
    _ensureLive();
    _result = NovelReaderNativePageCoverage(
      identity: _snapshot!.identity,
      layoutId: layoutId,
      pageIndex: pageIndex,
      hasClippedGlyphs: _hasClippedGlyphs,
      hasClippedResources: _hasClippedResources,
      hasUnanchoredImages: _hasUnanchoredImages,
      points: _points,
      images: _images,
    );
    _state = NovelReaderNativeCoverageState.complete;
    _dropBorrowed();
  }

  void _dropBorrowed() {
    _points.clear();
    _images.clear();
    _anchors = null;
    _snapshot = null;
    _fragments = const [];
    _ranges = null;
    _resources = null;
    _fragment = null;
    _projection = null;
    _runs = const [];
  }

  void close() {
    if (_state == NovelReaderNativeCoverageState.closed) return;
    _state = NovelReaderNativeCoverageState.closed;
    _result = null;
    _dropBorrowed();
  }
}

typedef _ImageCoverageInput = ({
  String path,
  ForumHtmlReadableImageEntry? entry,
  bool isSticker,
  Rect rect,
  int? atomIndex,
  int? fence,
});

Iterable<_ImageCoverageInput> _imageInputs(
  ForumBodyPreparedTextFragment prepared,
) sync* {
  final body = prepared is ForumBodyPreparedListItemFragment
      ? prepared.body
      : prepared;
  if (body is ForumBodyPreparedImageFragment) {
    yield (
      path: body.content.input.element.path,
      entry: body.content.input.entry,
      isSticker: false,
      rect: body.content.frame.imageRect,
      atomIndex: null,
      fence: null,
    );
  } else if (body is ForumBodyPreparedInlineFragment) {
    final view = body.view;
    for (final image in view.images.values) {
      final atom = view.content.projection.atoms[image.atomIndex];
      yield (
        path: image.input.element.path,
        entry: image.input.entry,
        isSticker: image.input.image.isSticker,
        rect: image.rect,
        atomIndex: image.atomIndex,
        fence: atom.displayStartUtf16,
      );
    }
  }
}

bool _visibleStyles(
  HtmlDisplayTextProjection projection,
  List<ForumBodyParagraphRun> runs,
  int start,
  int end,
) {
  final parts = projection.parts;
  var low = 0;
  var high = parts.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (parts[middle].utf16Start + parts[middle].text.length <= start) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  for (
    var index = low;
    index < parts.length && parts[index].utf16Start < end;
    index++
  ) {
    if (runs[parts[index].runIndex].style.visibilityHidden) {
      return false;
    }
  }
  return low < parts.length;
}

Never _fail(NovelReaderNativeCoverageFailure failure) =>
    throw NovelReaderNativeCoverageException(failure);
