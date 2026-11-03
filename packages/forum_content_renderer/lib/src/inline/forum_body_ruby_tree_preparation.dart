part of 'forum_body_ruby_tree_layout.dart';

enum _TreeState { active, ready, transferred, failed, closed }

/// Visible ownership transaction. Probe the full native footprint, adopt each
/// real leaf under the SAME captured native scaling inputs, qualify geometry,
/// then prepare source-order offsets/surfaces. No paint-time work is deferred.
final class ForumBodyRubyTreePreparation {
  ForumBodyRubyTreePreparation({
    required ForumBodyRubyTreeInput input,
    required ForumBodyRubyTreeMetrics metrics,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    TextScaler? expectedTextScaler,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _input = input,
       _metrics = metrics,
       _cache = cache,
       _ensureOwner = ensureOwner,
       _additionalOwned = additionalOwnedLeases,
       _expectedScaler = expectedTextScaler,
       _scaleSamples = expectedTextScaler == null
           ? null
           : metrics.effectiveScales.entries.iterator,
       _scalesChecked = expectedTextScaler == null {
    if (!identical(input, metrics.input)) {
      throw ArgumentError('Ruby tree input differs from its measured graph');
    }
  }
  ForumBodyRubyTreeInput? _input;
  ForumBodyRubyTreeMetrics? _metrics;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  TextScaler? _expectedScaler;
  Iterator<MapEntry<double, double>>? _scaleSamples;
  bool _scalesChecked;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  ForumBodyParagraphBudgetProbe? _probe;
  Iterator<ForumBodyNativeParagraphLease>? _prefix;
  bool _probeStarted = false;
  bool _budgetChecked = false;
  Iterator<ForumBodyNativeBudgetSlot>? _probeRequests;
  int _nextNode = 0;
  ForumBodyTextRequestPreparation? _member;
  Map<int, ForumBodyTextLease> _leases = {};
  ForumBodyInlinePagePreparation? _inline;
  Map<int, ForumBodyInlineParagraphView> _inlineViews = {};
  Map<int, Map<ForumBodyParagraphContent, ForumBodyInlineContext>>
  _inlineWindows = {};
  Map<ForumBodyParagraphContent, ForumBodyInlineContext> _inlineIndex =
      Map.identity();
  int _inlineIndexed = 0;
  Map<int, Map<ForumBodyParagraphContent, int>> _inlineIds = {};
  List<({int id, Offset offset})> _paintNodes = [];
  ForumBodyParagraphBudgetException? _inlineRejection;
  int _inlineBlockedAt = -1;
  Map<int, bool> _hasText = {};
  List<ForumBodyRubyTreeMember> _members = [];
  Map<int, ForumBodyRubyTreeMember> _byNode = {};
  List<({Rect rect, ForumBodyRubyContainerFontBox font})> _backgrounds = [];
  List<_TreePosition> _positions = [];
  bool _positioning = false;
  ForumBodyRubyTreeLayout? _result;
  var _state = _TreeState.active;
  bool _operating = false;
  bool _waiting = false;
  bool _cacheMiss = false;
  int _workCount = 0;
  bool get isReady => _state == _TreeState.ready;
  bool get cacheMiss => _cacheMiss;
  int get workCount => _workCount;
  ForumBodyParagraphBudgetException? get lastBudgetRejection =>
      _member?.lastBudgetRejection ?? (_waiting ? _inlineRejection : null);
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ..._leases.values,
    if (_member != null) ..._member!.nativeLeases,
    for (final view in _inlineViews.values) ...view.nativeLeases,
    if (_inline != null) ..._inline!.nativeLeases,
  ];

  ForumBodyRubyGroupPreparationStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() {
      _guard();
      final cache = _cache!;
      final builds = cache.layoutBuildCount;
      final pictures = cache.pictureBuildCount;
      var units = 0;
      _waiting = false;
      _cacheMiss = false;
      while (!isReady && units < maxParts) {
        final used = !_scalesChecked
            ? _inspectScale()
            : !_budgetChecked
            ? _inspectBudget()
            : _advanceBinding(cachedOnly);
        units += used;
        _workCount += used;
        _guard();
        if (_waiting ||
            _cacheMiss ||
            used == 0 ||
            cache.layoutBuildCount != builds ||
            cache.pictureBuildCount != pictures) {
          break;
        }
      }
      return ForumBodyRubyGroupPreparationStep(
        partsPrepared: 0,
        partsInspected: 0,
        formatUnitsPrepared: units,
        layoutsBuilt: cache.layoutBuildCount - builds,
        picturesBuilt: cache.pictureBuildCount - pictures,
        isReady: isReady,
        waitingForLayoutBudget: _waiting,
      );
    });
  }

  int _inspectScale() {
    if (!_scaleSamples!.moveNext()) {
      _scaleSamples = null;
      _scalesChecked = true;
    } else {
      final sample = _scaleSamples!.current;
      final actual = _expectedScaler!.scale(sample.key);
      _guard();
      if (actual != sample.value) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.scale,
        );
      }
    }
    return 1;
  }

  int _inspectBudget() {
    if (!_probeStarted) {
      _probe = _cache!.createBudgetProbe();
      final owned = [...nativeLeases, ...?_additionalOwned?.call()];
      _guard();
      _prefix = owned.iterator;
      _guard();
      _probeStarted = true;
      return 1;
    }
    final prefix = _prefix;
    if (prefix != null) {
      final hasNext = prefix.moveNext();
      _guard();
      if (hasNext) {
        _probe!.includeLease(prefix.current);
        _guard();
      } else {
        _prefix = null;
      }
      return 1;
    }
    // A component's font/scene budget inputs need not match its final retained
    // handles. Inspect the complete actual sequence, one contribution per part.
    final requests = _probeRequests ??=
        _metrics!.nativeBudgetFootprint.iterator;
    final hasNext = requests.moveNext();
    _guard();
    if (hasNext) {
      final slot = requests.current;
      slot.request.includeBudget(
        _probe!,
        width: slot.width,
        minimumLineCount: slot.minimumLineCount,
        textScaler: _metrics!.textScaler,
      );
      _guard();
      return 1;
    }
    _probe!.close();
    _probe = null;
    _probeRequests = null;
    _budgetChecked = true;
    _waiting =
        _inlineRejection != null && _cache!.budgetRevision == _inlineBlockedAt;
    return 1;
  }

  int _advanceBinding(bool cachedOnly) {
    if (_nextNode < _input!.nodes.length) {
      final id = _nextNode;
      final node = _input!.nodes[id];
      if (node is ForumBodyRubyTreeInline) {
        return _advanceInline(id, node, cachedOnly);
      }
      if (node is ForumBodyRubyTreeText && node.needsNative) {
        final member = _member ??= ForumBodyTextRequestPreparation(
          cache: _cache!,
          request: node.request,
          ensureOwner: _guard,
          preparePaint: true,
          width: _input!.maxWidth,
          textScaler: _metrics!.textScaler,
          additionalOwnedLeases: () => [
            ...nativeLeases,
            ...?_additionalOwned?.call(),
          ],
        );
        final step = member.advance(cachedOnly: cachedOnly);
        _waiting = step.waiting;
        _cacheMiss = step.cacheMiss;
        _guard();
        if (member.isReady) {
          final lease = member.takeLease();
          _member = null;
          member.close();
          try {
            _guard();
            final actual = ForumBodyRubyChildMetrics.measure(
              cache: _cache!,
              lease: lease,
              content: node.content,
            );
            final expected = _metrics!.nodes[id].box!;
            const tolerance = ForumBodyRubyGroupMetrics.geometryTolerance;
            if ((actual.bounds.left - expected.bounds.left).abs() > tolerance ||
                (actual.bounds.top - expected.bounds.top).abs() > tolerance ||
                (actual.bounds.right - expected.bounds.right).abs() >
                    tolerance ||
                (actual.bounds.bottom - expected.bounds.bottom).abs() >
                    tolerance ||
                (actual.alphabeticBaseline - expected.alphabeticBaseline)
                        .abs() >
                    tolerance ||
                !lease.layout.isPaintPrepared) {
              throw const ForumBodyRubyGroupException(
                ForumBodyRubyGroupFailure.geometry,
              );
            }
            _leases[id] = lease;
          } catch (_) {
            lease.release();
            rethrow;
          }
          _hasText[id] = node.content.projection.text.isNotEmpty;
          _nextNode++;
        }
        return step.units;
      }
      _hasText[id] = switch (node) {
        ForumBodyRubyTreeText() => false,
        ForumBodyRubyTreeInline() => throw StateError(
          'Inline binding is not ready',
        ),
        ForumBodyRubyTreeFrame() => _hasText[node.child]!,
        ForumBodyRubyTreeGroup() =>
          _hasText[node.base]! ||
              node.annotations.any(
                (a) => a.child != null && _hasText[a.child!]!,
              ),
        ForumBodyRubyTreeSegment() => node.children.any(
          (child) => _hasText[child.node]!,
        ),
      };
      _nextNode++;
      return 1;
    }
    if (!_positioning) {
      _positions.add(_TreePosition(_input!.root, Offset.zero));
      _positioning = true;
      return 1;
    }
    if (_positions.isNotEmpty) {
      _positionOne();
      return 1;
    }
    _result = ForumBodyRubyTreeLayout._(
      input: _input!,
      metrics: _metrics!,
      members: _members,
      byNode: _byNode,
      hasText: _hasText,
      inlineViews: _inlineViews,
      inlineIds: _inlineIds,
      paintNodes: _paintNodes,
      backgrounds: _backgrounds,
    );
    if (!_result!.isOwnedBy(_cache!)) {
      throw StateError('Ruby tree native owner is retired');
    }
    _state = _TreeState.ready;
    return 1;
  }

  void _positionOne() {
    final work = _positions.last;
    final node = _input!.nodes[work.id];
    final numeric = _metrics!.nodes[work.id];
    if (node is ForumBodyRubyTreeText) {
      final member = ForumBodyRubyTreeMember._(
        work.id,
        node.content,
        _leases[work.id],
        work.offset,
      );
      _members.add(member);
      _byNode[work.id] = member;
      if (member.lease != null) {
        _paintNodes.add((id: work.id, offset: work.offset));
      }
      _positions.removeLast();
      return;
    }
    final box = numeric as ForumBodyRubyTreeContainerMetrics;
    if (!work.started) {
      final font = box.backgroundFont;
      if (font != null) {
        final rect = Rect.fromLTWH(
          work.offset.dx,
          work.offset.dy + box.frame.baseline - font.alphabeticBaseline,
          box.frame.size.width,
          font.height,
        );
        if (!rect.isEmpty) _backgrounds.add((rect: rect, font: font));
      }
      work.started = true;
      return;
    }
    final origin = work.offset + box.frame.childOffset;
    final container = node as ForumBodyRubyTreeContainer;
    switch (container) {
      case ForumBodyRubyTreeSegment() ||
          ForumBodyRubyTreeGroup() ||
          ForumBodyRubyTreeFrame():
        if (work.rank == -1) work.rank = 0;
        if (work.rank == forumBodyRubyTreeChildSlotCount(container)) {
          _positions.removeLast();
        } else {
          final edge = forumBodyRubyTreeChildGeometryAt(
            container,
            box,
            work.rank++,
          );
          if (edge != null) {
            _positions.add(_TreePosition(edge.node, origin + edge.offset));
          }
        }
      case ForumBodyRubyTreeInline():
        final view = _inlineViews[work.id]!;
        if (work.background < view.backgroundSurfaces.length) {
          final surface = view.backgroundSurfaces[work.background++];
          _backgrounds.add((
            rect: surface.rect.shift(origin),
            font: surface.font,
          ));
        } else if (work.rank == -1) {
          _paintNodes.add((id: work.id, offset: origin));
          _inlineIds[work.id] = Map.identity();
          work.rank = 0;
        } else if (work.rank < container.sources.length) {
          final source = container.sources[work.rank++];
          final window = _inlineWindows[work.id]![source.content];
          if (window == null) {
            throw StateError('Inline member has no actual source window');
          }
          final member = ForumBodyRubyTreeMember._inline(
            source.id,
            source.content,
            view,
            window,
            origin,
          );
          _members.add(member);
          _byNode[source.id] = member;
          _inlineIds[work.id]![source.content] = source.id;
        } else {
          _positions.removeLast();
        }
    }
  }

  ForumBodyRubyTreeLayout takeLayout() => _operate(() {
    _guard();
    if (!isReady) throw StateError('Ruby tree preparation is incomplete');
    final result = _result!;
    if (!result.isOwnedBy(_cache!)) {
      throw StateError('Ruby tree owner is retired');
    }
    _result = null;
    _leases = {};
    _inlineViews = {};
    _state = _TreeState.transferred;
    _dropOwner();
    return result;
  });
  void _guard() {
    if (_state != _TreeState.active && !isReady) {
      throw StateError('Ruby tree preparation is retired');
    }
    _ensureOwner!();
    if ((_state != _TreeState.active && !isReady) || _cache!.isClosed) {
      throw StateError('Ruby tree owner is retired');
    }
  }

  T _operate<T>(T Function() action) {
    if (_operating) throw StateError('Ruby tree preparation is reentrant');
    _operating = true;
    try {
      return action();
    } catch (_) {
      _retire(_TreeState.failed);
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _dropOwner() {
    _inline?.close();
    _inline = null;
    _member?.close();
    _member = null;
    _probe?.close();
    _probe = null;
    _probeRequests = null;
    _prefix = null;
    _scaleSamples = null;
    _expectedScaler = null;
    _input = null;
    _metrics = null;
    _cache = null;
    _ensureOwner = null;
    _additionalOwned = null;
    _members = [];
    _byNode = {};
    _hasText = {};
    _backgrounds = [];
    _positions = [];
    _inlineWindows = {};
    _inlineIndex = Map.identity();
    _inlineIds = {};
    _paintNodes = [];
    _inlineRejection = null;
  }

  void _retire(_TreeState state) {
    if (_state != _TreeState.active && !isReady) return;
    _state = state;
    _result?.close();
    _result = null;
    for (final lease in _leases.values) {
      lease.release();
    }
    _leases = {};
    for (final view in _inlineViews.values) {
      view.close();
    }
    _inlineViews = {};
    _dropOwner();
  }

  void close() => _retire(_TreeState.closed);

  int _advanceInline(int id, ForumBodyRubyTreeInline node, bool cachedOnly) {
    var view = _inlineViews[id];
    if (view == null) {
      if (_inlineRejection != null &&
          _cache!.budgetRevision == _inlineBlockedAt) {
        _waiting = true;
        return 0;
      }
      _inlineRejection = null;
      final target =
          (_metrics!.nodes[id] as ForumBodyRubyTreeContainerMetrics).inline!;
      final job = _inline ??= ForumBodyInlinePagePreparation(
        input: target.input,
        fragment: target.fragment,
        identity: target.input.identity,
        cache: _cache!,
        textScaler: _metrics!.textScaler,
        ensureOwner: _guard,
        ownedPageLeases: () => [...nativeLeases, ...?_additionalOwned?.call()],
      );
      final before = job.workCount;
      final rejectedAt = _cache!.budgetRevision;
      try {
        final step = job.advance(cachedOnly: cachedOnly, maxParts: 1);
        _guard();
        _cacheMiss = step.cacheMiss;
        view = step.view;
        if (view != null) {
          _inlineViews[id] = view;
          _inline = null;
          const tolerance = ForumBodyRubyGroupMetrics.geometryTolerance;
          if ((view.width - target.size.width).abs() > tolerance ||
              (view.height - target.size.height).abs() > tolerance ||
              view.lines.length != 1 ||
              (view.lines.single.baseline - target.baseline).abs() >
                  tolerance) {
            throw const ForumBodyRubyGroupException(
              ForumBodyRubyGroupFailure.geometry,
            );
          }
          _inlineIndexed = 0;
          _inlineIndex = Map.identity();
        }
        final used = job.workCount - before;
        return used == 0 ? 1 : used;
      } on ForumBodyParagraphBudgetException catch (error) {
        _guard();
        if (error.failure != ForumBodyParagraphBudgetFailure.pinned) rethrow;
        if (!_cache!.isBlockedByExternalPins(error, [
          ...nativeLeases,
          ...?_additionalOwned?.call(),
        ])) {
          throw ForumBodyParagraphBudgetException(
            ForumBodyParagraphBudgetFailure.content,
            requiredEstimatedBytes: error.requiredEstimatedBytes,
            requiredAdditionalEntries: error.requiredAdditionalEntries,
          );
        }
        _inlineRejection = error;
        _inlineBlockedAt = rejectedAt;
        _probe?.close();
        _probe = null;
        _probeStarted = false;
        _budgetChecked = false;
        _probeRequests = null;
        _prefix = null;
        return 1;
      }
    }
    if (_inlineIndexed < view.content.contexts.length) {
      final window = view.content.contexts[_inlineIndexed++];
      if (_inlineIndex.containsKey(window.content)) {
        throw StateError('Ambiguous actual inline source window');
      }
      _inlineIndex[window.content] = window;
      return 1;
    }
    _inlineWindows[id] = UnmodifiableMapView(_inlineIndex);
    _inlineIndex = Map.identity();
    _hasText[id] = view.content.projection.display.text.isNotEmpty;
    _nextNode++;
    return 1;
  }
}

final class _TreePosition {
  _TreePosition(this.id, this.offset);
  final int id;
  final Offset offset;
  bool started = false;
  int rank = -1;
  int background = 0;
}
