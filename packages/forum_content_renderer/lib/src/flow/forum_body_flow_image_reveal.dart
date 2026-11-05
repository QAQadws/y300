part of 'forum_body_flow_sliver.dart';

typedef _FlowImageLocation = ({Rect bounds, double? tableOffset});

extension on _ForumBodyFlowState {
  void _bindImageLocator() {
    _detachImageLocator?.call();
    final box = widget;
    final session = box.session;
    _detachImageLocator = box is ForumBodyFlowBox
        ? box.imageAnchorController?.attachOffscreenReveal(
            _revealOffscreen,
            isCurrent: () =>
                mounted &&
                widget.isCurrentLayout &&
                identical(widget.session, session) &&
                !session.isClosed &&
                !session.isLayoutOwnerRetired &&
                _fits,
          )
        : null;
  }

  Future<bool> _revealOffscreen(
    int index,
    ScrollPosition position,
    bool Function() isCurrent,
    Future<bool> Function(double, bool Function()) revealAt,
  ) async {
    final session = widget.session;
    final path = (widget as ForumBodyFlowBox).imagePathForIndex?.call(index);
    bool layoutIsCurrent() =>
        mounted &&
        widget.isCurrentLayout &&
        _fits &&
        identical(widget.session, session) &&
        identical(_outerPosition, position) &&
        !session.isClosed &&
        !session.isLayoutOwnerRetired;
    bool active() => isCurrent() && layoutIsCurrent();
    if (path == null || !active()) return false;

    // Scan only the sealed prefix. Yield both while it is still growing and
    // when a wide table or a long prefix takes several turns to inspect.
    final clock = Stopwatch()..start();
    var slice = 0, waits = 0;
    Future<void> nextFrame() async {
      waits++;
      WidgetsBinding.instance.ensureVisualUpdate();
      await WidgetsBinding.instance.endOfFrame;
      clock.reset();
    }

    while (active() && waits < 32) {
      final prefix = widget.prefix;
      if (slice >= prefix.length) {
        if (prefix.isComplete) return false;
        await nextFrame();
        continue;
      }
      for (final candidate in _imageLocations(session, prefix[slice], path)) {
        if (candidate != null) {
          if (!active()) return false;
          return _revealLocation(
            slice,
            candidate,
            position,
            active,
            layoutIsCurrent,
            revealAt,
          );
        }
        if (clock.elapsedMicroseconds >= 2500) {
          await nextFrame();
          if (!active() || waits >= 32) return false;
        }
      }
      slice++;
    }
    return false;
  }

  Future<bool> _revealLocation(
    int slice,
    _FlowImageLocation candidate,
    ScrollPosition position,
    bool Function() active,
    bool Function() layoutIsCurrent,
    Future<bool> Function(double, bool Function()) revealAt,
  ) async {
    final box = _boxKey?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final viewport = forumBodyViewportForPosition(box, position);
    if (viewport == null) return false;
    final offset = viewport
        .getOffsetToReveal(
          box,
          0,
          rect: candidate.bounds.shift(Offset(0, _top(slice))),
        )
        .offset;
    final tableOffset = candidate.tableOffset;
    final previous = _tableOffsets[slice];
    final request = _imageReveal = (slice: slice, request: Object());
    if (tableOffset != null) _setTableOffset(slice, tableOffset);
    var found = false;
    try {
      return found = await revealAt(offset, layoutIsCurrent);
    } finally {
      if (_imageReveal == request) _imageReveal = null;
      if (!found && tableOffset != null && active()) {
        _setTableOffset(slice, previous);
      }
    }
  }

  void _setTableOffset(int slice, double? offset) {
    final horizontal = _ready[slice]?.horizontal;
    if (horizontal != null &&
        horizontal.hasClients &&
        horizontal.position.hasContentDimensions) {
      final max = horizontal.position.maxScrollExtent;
      horizontal.jumpTo((offset ?? 0).clamp(0.0, max));
    }
    if (offset == null) {
      _tableOffsets.remove(slice);
    } else {
      _tableOffsets[slice] = offset;
    }
  }
}

// Null entries are bounded scanning work. Only a matching published image
// path supplies geometry, including in a lazily mounted table cell.
Iterable<_FlowImageLocation?> _imageLocations(
  ForumBodyTextPageSession session,
  ForumBodyTextPage slice,
  String path,
) sync* {
  for (final fragment in slice.fragments) {
    yield fragment.imagePaths.contains(path)
        ? (bounds: _imageHintBounds(fragment), tableOffset: null)
        : null;
  }
  final frame = slice.table;
  if (frame == null || !path.startsWith('${frame.path}/')) {
    yield null;
    return;
  }
  final table = session.tableLayoutForPage(slice.index)!;
  for (final area in table.captions.followedBy(table.cells)) {
    yield null;
    if (!path.startsWith('${area.element.path}/')) continue;
    for (final page in area.snapshot) {
      yield null;
      for (final fragment in page.fragments) {
        if (!fragment.imagePaths.contains(path)) {
          yield null;
          continue;
        }
        final bounds = _imageHintBounds(fragment).shift(
          area.contentBounds.topLeft + Offset(0, area.pageTop(page.index)),
        );
        yield (
          bounds: bounds.shift(frame.bounds.topLeft),
          tableOffset: bounds.left.clamp(
            0.0,
            math.max(0.0, table.size.width - frame.bounds.width),
          ),
        );
      }
    }
  }
}

Rect _imageHintBounds(ForumBodyTextPageFragment fragment) {
  final origin = Offset(fragment.left, fragment.top);
  return fragment.imageFrame?.imageRect.shift(origin) ??
      origin & Size(fragment.width, fragment.height);
}
