part of 'forum_body_text_page_composer.dart';

extension ForumBodyFloatPlacement on ForumBodyTextPageComposer {
  /// Place a whole measured float in the current draft without consuming its
  /// height in normal flow. A full draft seals before the caller retries the
  /// same measured input. Existing numeric pages remain immutable.
  bool placeMeasuredFloat({
    required ForumBodyFloatBodyLayout layout,
    required int inputCount,
    required double left,
    required double containingWidth,
    required double spaceBefore,
  }) {
    _ensureFloatBoundary();
    final child = layout.snapshot;
    final occupied = layout.occupiedSize;
    final style = layout.source.event.style;
    final side = style.floatSide;
    if (layout.isClosed ||
        child.identity != identity ||
        !child.isComplete ||
        inputCount < 0 ||
        !occupied.isFinite ||
        !left.isFinite ||
        left < 0 ||
        !containingWidth.isFinite ||
        containingWidth <= 0 ||
        left + containingWidth > width + precisionErrorTolerance ||
        !spaceBefore.isFinite ||
        style.clear == ForumBodyClear.unsupported ||
        (side != ForumBodyFloatSide.left && side != ForumBodyFloatSide.right)) {
      _fail(ForumBodyTextPageFailure.invalidGeometry);
    }
    if (occupied.width > containingWidth + precisionErrorTolerance) {
      _fail(ForumBodyTextPageFailure.oversizedGroup);
    }

    final atStart = _usedHeight == 0 && _draft.isEmpty && _rules.isEmpty;
    final top = math.max(
      math.max(0.0, _flowHeight + (atStart ? 0 : spaceBefore)),
      _floats.lastOrNull?.bounds.top ?? 0,
    );
    final position = _findFloatPosition(
      side: side,
      left: left,
      right: left + containingWidth,
      top: _clearFloatTop(style.clear, top),
      size: occupied,
    );
    if (position.bottom > height && !(_flowing && atStart)) {
      return _retryFloat(atStart, ForumBodyTextPageFailure.oversizedGroup);
    }

    final background = layout.background;
    var items = (background?.a ?? 0) > 0 ? 1 : 0;
    var fragments = 0, handles = 0, entries = 0, bytes = 0, images = 0;
    for (final page in child) {
      final usage = page.nativeUsage;
      if (page.table != null || usage == null) {
        _fail(ForumBodyTextPageFailure.invalidGeometry);
      }
      items += page.itemCount;
      fragments += page.fragments.length;
      handles += usage.handles;
      entries += usage.entries;
      bytes += usage.bytes;
      images += usage.images;
    }
    if (items > maxFragments - _fragmentCount ||
        _floats.length >= maxFragments) {
      _fail(ForumBodyTextPageFailure.fragmentLimit);
    }
    if (maxDeliveriesPerPage case final limit?
        when _draft.length + fragments > limit) {
      return _retryFloat(atStart, ForumBodyTextPageFailure.fragmentLimit);
    }
    if (maxNativeHandlesPerPage case final limit?
        when _usedNativeHandles + handles > limit) {
      return _retryFloat(atStart, ForumBodyTextPageFailure.nativeHandleLimit);
    }
    if (maxNativeEntriesPerPage case final limit?
        when _nativeEntries.length + _sceneEntries + entries > limit) {
      return _retryFloat(atStart, ForumBodyTextPageFailure.nativeEntryLimit);
    }
    if (maxNativeEstimatedBytesPerPage case final limit?
        when _nativeBytes + _sceneBytes + bytes > limit) {
      return _retryFloat(atStart, ForumBodyTextPageFailure.nativeByteLimit);
    }
    if (maxImagesPerPage case final limit? when _usedImages + images > limit) {
      return _retryFloat(atStart, ForumBodyTextPageFailure.imageLimit);
    }

    _touchBackgrounds(position.top);
    if (items > maxFragments - _fragmentCount) {
      _fail(ForumBodyTextPageFailure.fragmentLimit);
    }
    final borderOrigin =
        position.topLeft + Offset(layout.margin.left, layout.margin.top);
    final contentOrigin = borderOrigin + layout.contentBounds.topLeft;
    if ((background?.a ?? 0) > 0) {
      _floatBackgrounds.add(
        ForumBodyTextPageBackground._(
          layout.source.element.path,
          borderOrigin.dx,
          borderOrigin.dy,
          layout.borderBoxSize.width,
          layout.borderBoxSize.height,
          background!,
          null,
          true,
          true,
        ),
      );
    }
    for (final (index, page) in child.indexed) {
      final offset = contentOrigin + Offset(0, layout.pageTop(index));
      _draft.addAll(
        page.fragments.map(
          (fragment) =>
              _shiftFloatFragment(fragment, offset, _nextParagraphIndex),
        ),
      );
      _rules.addAll(
        page.rules.map(
          (rule) => ForumBodyTextPageRule._(
            path: rule.path,
            left: rule.left + offset.dx,
            top: rule.top + offset.dy,
            width: rule.width,
            thickness: rule.thickness,
            color: rule.color,
          ),
        ),
      );
      _floatBackgrounds.addAll(
        page.backgrounds.map(
          (box) => ForumBodyTextPageBackground._(
            box.path,
            box.left + offset.dx,
            box.top + offset.dy,
            box.width,
            box.height,
            box.color,
            box.quoteDecoration,
            box.startsBox,
            box.endsBox,
          ),
        ),
      );
    }
    _nextParagraphIndex += inputCount;
    _fragmentCount += items;
    _usedNativeHandles += handles;
    // Imported entries may share cache keys with normal flow. Counting the
    // child totals conservatively keeps admission bounded without its keys.
    _sceneEntries += entries;
    _sceneBytes += bytes;
    _usedImages += images;
    _flowHeight = position.top;
    _usedHeight = math.max(_usedHeight, position.bottom);
    if (position.height > 0) _floats.add((side: side, bounds: position));
    return true;
  }

  void clearMeasuredFloats(ForumBodyClear clear) {
    _ensureFloatBoundary();
    _flowHeight = _clearFloatTop(clear, _flowHeight);
  }

  bool hasFloatExclusion(double spaceBefore) => _floats.any(
    (float) => float.bounds.bottom > math.max(0.0, _flowHeight + spaceBefore),
  );

  void _ensureFloatBoundary() {
    _ensureOpen();
    if (!needsInput || _collapseHeader != null) {
      throw StateError('Float placement requires a free flow cursor');
    }
  }

  bool _retryFloat(bool atStart, ForumBodyTextPageFailure failure) {
    if (atStart) _fail(failure);
    _seal();
    return false;
  }

  double _clearFloatTop(ForumBodyClear clear, double top) {
    for (final float in _floats) {
      if (clear == ForumBodyClear.both ||
          (clear == ForumBodyClear.left &&
              float.side == ForumBodyFloatSide.left) ||
          (clear == ForumBodyClear.right &&
              float.side == ForumBodyFloatSide.right)) {
        top = math.max(top, float.bounds.bottom);
      }
    }
    return top;
  }

  Rect _findFloatPosition({
    required ForumBodyFloatSide side,
    required double left,
    required double right,
    required double top,
    required Size size,
  }) {
    while (true) {
      var bandLeft = left, bandRight = right, next = double.infinity;
      for (final float in _floats) {
        final bounds = float.bounds;
        if (bounds.bottom <= top ||
            bounds.right <= left ||
            bounds.left >= right) {
          continue;
        }
        if (float.side == ForumBodyFloatSide.left) {
          bandLeft = math.max(bandLeft, bounds.right);
        } else {
          bandRight = math.min(bandRight, bounds.left);
        }
        next = math.min(next, bounds.bottom);
      }
      if (bandRight - bandLeft + precisionErrorTolerance >= size.width) {
        return (Offset(
              side == ForumBodyFloatSide.left
                  ? bandLeft
                  : bandRight - size.width,
              top,
            ) &
            size);
      }
      if (!next.isFinite || next <= top) {
        _fail(ForumBodyTextPageFailure.invalidGeometry);
      }
      top = next;
    }
  }
}

ForumBodyTextPageFragment _shiftFloatFragment(
  ForumBodyTextPageFragment fragment,
  Offset offset,
  int inputOffset,
) {
  final header = fragment.collapseHeader;
  return ForumBodyTextPageFragment._(
    paragraphIndex: fragment.paragraphIndex + inputOffset,
    path: fragment.path,
    fontRevision: fragment.fontRevision,
    styleRevision: fragment.styleRevision,
    startLine: fragment.startLine,
    endLine: fragment.endLine,
    coverageStartUtf16: fragment.coverageStartUtf16,
    coverageEndUtf16: fragment.coverageEndUtf16,
    sourceHint: fragment.sourceHint,
    left: fragment.left + offset.dx,
    top: fragment.top + offset.dy,
    width: fragment.width,
    height: fragment.height,
    kind: fragment.kind,
    listMarker: fragment.listMarker,
    collapseHeader: header == null
        ? null
        : (
            id: header.id,
            titlePath: header.titlePath,
            expanded: header.expanded,
            direction: header.direction,
            bounds: header.bounds.shift(offset),
          ),
    imageFrame: fragment.imageFrame,
    engineRange: fragment.engineRange,
    imageCount: fragment.imageCount,
    imagePaths: fragment.imagePaths,
  );
}
