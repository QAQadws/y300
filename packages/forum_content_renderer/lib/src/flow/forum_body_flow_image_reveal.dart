part of 'forum_body_flow_sliver.dart';

typedef _FlowImageLocation = ({
  Rect bounds,
  ({String path, double offset})? tableTarget,
});

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
    final table = candidate.tableTarget;
    final key = table == null ? null : (slice, table.path);
    final previous = key == null
        ? null
        : widget.session.flowTableOffset(key.$1, key.$2);
    final request = _imageReveal = (slice: slice, request: Object());
    if (table != null) _setTableOffset(key!, table.offset);
    var found = false;
    try {
      return found = await revealAt(offset, layoutIsCurrent);
    } finally {
      if (_imageReveal == request) _imageReveal = null;
      if (!found && key != null && active()) {
        _setTableOffset(key, previous);
      }
    }
  }

  void _setTableOffset((int, String) key, double? offset) {
    ScrollController? horizontal;
    for (final table
        in _ready[key.$1]?.tables ?? const <_FlowTableDelivery>[]) {
      if (table.frame.path == key.$2) {
        horizontal = table.horizontal;
        break;
      }
    }
    if (horizontal != null &&
        horizontal.hasClients &&
        horizontal.position.hasContentDimensions) {
      final max = horizontal.position.maxScrollExtent;
      horizontal.jumpTo((offset ?? 0).clamp(0.0, max));
    }
    widget.session.setFlowTableOffset(key.$1, key.$2, offset);
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
        ? (bounds: _imageHintBounds(fragment), tableTarget: null)
        : null;
  }
  for (final frame in slice.tableFrames) {
    yield null;
    if (!path.startsWith('${frame.path}/')) continue;
    final table = session.tableLayoutForPage(slice.index, path: frame.path)!;
    for (final bounds in _tableImageBounds(table, path)) {
      if (bounds == null) {
        yield null;
        continue;
      }
      yield (
        bounds: bounds.shift(frame.bounds.topLeft),
        tableTarget: (
          path: frame.path,
          offset: bounds.left.clamp(
            0.0,
            math.max(0.0, table.size.width - frame.bounds.width),
          ),
        ),
      );
    }
  }
}

Iterable<Rect?> _tableImageBounds(
  ForumBodyTableLayout table,
  String path,
) sync* {
  for (final area in table.captions.followedBy(table.cells)) {
    yield null;
    if (!path.startsWith('${area.element.path}/')) continue;
    for (final page in area.snapshot) {
      yield null;
      final origin =
          area.contentBounds.topLeft + Offset(0, area.pageTop(page.index));
      for (final fragment in page.fragments) {
        yield fragment.imagePaths.contains(path)
            ? _imageHintBounds(fragment).shift(origin)
            : null;
      }
      for (final frame in page.tableFrames) {
        yield null;
        if (!path.startsWith('${frame.path}/')) continue;
        final nested = area.tableLayoutForPage(page.index, path: frame.path)!;
        final offset = area.flowTableOffset(page.index, frame.path) ?? 0;
        for (final bounds in _tableImageBounds(nested, path)) {
          yield bounds?.shift(
            origin + frame.bounds.topLeft - Offset(offset, 0),
          );
        }
      }
    }
  }
}

Rect _imageHintBounds(ForumBodyTextPageFragment fragment) {
  final origin = Offset(fragment.left, fragment.top);
  return fragment.imageFrame?.imageRect.shift(origin) ??
      origin & Size(fragment.width, fragment.height);
}
