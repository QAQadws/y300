part of 'forum_body_text_page_composer.dart';

typedef ForumBodyFloatLineBand = ({
  double left,
  double width,
  double spaceBefore,
  double bottom,
});

typedef ForumBodyPendingFloatLine = ({
  double top,
  double spaceBefore,
  double width,
  int handles,
  int entries,
  int bytes,
  int images,
});

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
    ForumBodyPendingFloatLine? precedingLine,
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

    final atStart = _usedHeight == 0 && _draftDeliveries == 0 && _rules.isEmpty;
    final top = math.max(
      math.max(0.0, _flowHeight + (atStart ? 0 : spaceBefore)),
      _floats.lastOrNull?.bounds.top ?? 0,
    );
    final position = _findFloatPosition(
      side: side,
      left: left,
      right: left + containingWidth,
      top: _clearFloatTop(
        style.clear,
        math.max(top, precedingLine?.top ?? top),
      ),
      size: occupied,
    );
    bool retryBudget(ForumBodyTextPageFailure failure) =>
        precedingLine == null && _retryFloat(failure, forceScreen: true);
    if (precedingLine != null) {
      final band = nextFloatTextBand(
        left: left,
        width: containingWidth,
        spaceBefore: precedingLine.top - _flowHeight,
      );
      final remaining = band.width - (position.height > 0 ? position.width : 0);
      if (position.top != precedingLine.top ||
          precedingLine.width > remaining + precisionErrorTolerance) {
        return false;
      }
    }
    if (position.bottom > height && !(_flowing && atStart)) {
      return precedingLine == null &&
          _retryFloat(ForumBodyTextPageFailure.oversizedGroup);
    }

    final background = layout.background;
    var items = (background?.a ?? 0) > 0 ? 1 : 0;
    var deliveries = 0, handles = 0, entries = 0, bytes = 0, images = 0;
    var tableItems = 0;
    for (final page in child) {
      final usage = page.nativeUsage;
      if ((!_flowing && page.table != null) || usage == null) {
        _fail(ForumBodyTextPageFailure.invalidGeometry);
      }
      items += page.itemCount;
      deliveries += page.fragments.length;
      if (page.table != null) {
        final tableUsage = layout.tableLayoutForPage(page.index)!.usage;
        final retained = tableUsage.items + tableUsage.pages;
        items += retained;
        tableItems += retained + 1;
        deliveries++;
      }
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
        when _screenDeliveries + deliveries + (precedingLine == null ? 0 : 1) >
            limit) {
      return retryBudget(ForumBodyTextPageFailure.fragmentLimit);
    }
    if (maxNativeHandlesPerPage case final limit?
        when _usedNativeHandles + handles + (precedingLine?.handles ?? 0) >
            limit) {
      return retryBudget(ForumBodyTextPageFailure.nativeHandleLimit);
    }
    if (maxNativeEntriesPerPage case final limit?
        when _nativeEntries.length +
                _sceneEntries +
                entries +
                (precedingLine?.entries ?? 0) >
            limit) {
      return retryBudget(ForumBodyTextPageFailure.nativeEntryLimit);
    }
    if (maxNativeEstimatedBytesPerPage case final limit?
        when _nativeBytes + _sceneBytes + bytes + (precedingLine?.bytes ?? 0) >
            limit) {
      return retryBudget(ForumBodyTextPageFailure.nativeByteLimit);
    }
    if (maxImagesPerPage case final limit?
        when _usedImages + images + (precedingLine?.images ?? 0) > limit) {
      return retryBudget(ForumBodyTextPageFailure.imageLimit);
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
      if (page.table case final table?) {
        _floatedTables.add(_shiftTable(table, offset));
      }
      _draft.addAll(
        page.fragments.map(
          (fragment) => _shiftFragment(
            fragment,
            offset,
            floatInputOffset: _nextParagraphIndex,
          ),
        ),
      );
      _rules.addAll(page.rules.map((rule) => rule._shift(offset)));
      _floatBackgrounds.addAll(
        page.backgrounds.map((box) => box._shift(offset)),
      );
    }
    _nextParagraphIndex += inputCount;
    _fragmentCount += items;
    _floatedTableItems += tableItems;
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

  /// Full-width resources and rules cannot share an exclusion band. Consume
  /// their pending gap once before moving their entire box below the floats.
  double clearForFullWidthBlock(double spaceBefore) {
    if (!hasFloatExclusion(spaceBefore)) return spaceBefore;
    _ensureFloatBoundary();
    final top = math.max(0.0, _flowHeight + spaceBefore);
    final cleared = _clearFloatTop(ForumBodyClear.both, top);
    _flowHeight = cleared;
    return 0;
  }

  bool hasFloatExclusion(double spaceBefore) => _floats.any(
    (float) => float.bounds.bottom > math.max(0.0, _flowHeight + spaceBefore),
  );

  /// Only a box that currently determines an edge can end this band. A
  /// contained box may end earlier without changing the line's usable width.
  ForumBodyFloatLineBand nextFloatTextBand({
    required double left,
    required double width,
    required double spaceBefore,
  }) {
    _ensureFloatBoundary();
    final right = left + width;
    final top = math.max(0.0, _flowHeight + spaceBefore);
    var bandTop = top;
    for (final float in _floats) {
      final bounds = float.bounds;
      if (bounds.bottom > top && bounds.right > left && bounds.left < right) {
        // A signed block gap cannot place a new line above the start of an
        // already placed float and then let that line overlap it from above.
        bandTop = math.max(bandTop, bounds.top);
      }
    }
    var bandLeft = left, bandRight = right;
    double? leftEnd, rightEnd;
    for (final float in _floats) {
      final bounds = float.bounds;
      if (bounds.bottom <= bandTop ||
          bounds.right <= left ||
          bounds.left >= right) {
        continue;
      }
      if (float.side == ForumBodyFloatSide.left && bounds.right >= bandLeft) {
        leftEnd = bounds.right == bandLeft && leftEnd != null
            ? math.max(leftEnd, bounds.bottom)
            : bounds.bottom;
        bandLeft = bounds.right;
      } else if (float.side == ForumBodyFloatSide.right &&
          bounds.left <= bandRight) {
        rightEnd = bounds.left == bandRight && rightEnd != null
            ? math.max(rightEnd, bounds.bottom)
            : bounds.bottom;
        bandRight = bounds.left;
      }
    }
    return (
      left: bandLeft,
      width: math.max(0, bandRight - bandLeft),
      spaceBefore: bandTop - _flowHeight,
      bottom: math.min(leftEnd ?? double.infinity, rightEnd ?? double.infinity),
    );
  }

  void moveBelowFloatTextBand(double bottom) {
    _ensureFloatBoundary();
    _flowHeight = math.max(_flowHeight, bottom);
  }

  /// Retire the old native width only when its physical band or page is over.
  /// If no legal row was consumed, leave the rendered ordinal available for
  /// the next width. The source caller can then discard the tentative input.
  ({
    int? endUtf16,
    int? engineEndUtf16,
    bool blocked,
    ForumBodyPendingFloatLine? heldLine,
  })?
  retireFloatTextBand({required double bottom, required bool pageSealed}) {
    final active = _active;
    if (active == null ||
        (!pageSealed &&
            !active.outsideFloatBand &&
            active.heldFloatLine == null &&
            _flowHeight < bottom)) {
      return null;
    }
    final consumed = active.nextLine > active.firstLine;
    final result = (
      endUtf16: consumed
          ? active.input.lines[active.nextLine - 1].coverageEndUtf16
          : null,
      engineEndUtf16: consumed
          ? active.input.lines[active.nextLine - 1].engineCoverageEndUtf16
          : null,
      blocked: active.outsideFloatBand,
      heldLine: active.heldFloatLine,
    );
    active.input.lease?.release();
    _active = null;
    if (consumed) _nextParagraphIndex++;
    return result;
  }

  void _ensureFloatBoundary() {
    _ensureOpen();
    if (!needsInput || _collapseHeader != null) {
      throw StateError('Float placement requires a free flow cursor');
    }
  }

  bool _retryFloat(
    ForumBodyTextPageFailure failure, {
    bool forceScreen = false,
  }) {
    if (!(forceScreen ? _hasScreenContent : _hasColumnContent)) {
      _fail(failure);
    }
    _seal(forceScreen: forceScreen);
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

ForumBodyTextPageFragment _shiftFragment(
  ForumBodyTextPageFragment fragment,
  Offset offset, {
  int? floatInputOffset,
}) {
  final header = fragment.collapseHeader;
  return ForumBodyTextPageFragment._(
    paragraphIndex: fragment.paragraphIndex + (floatInputOffset ?? 0),
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
    isFloated: floatInputOffset != null || fragment.isFloated,
  );
}
