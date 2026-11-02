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
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _input = input,
       _metrics = metrics,
       _cache = cache,
       _ensureOwner = ensureOwner,
       _additionalOwned = additionalOwnedLeases {
    if (!identical(input, metrics.input)) {
      throw ArgumentError('Ruby tree input differs from its measured graph');
    }
  }
  ForumBodyRubyTreeInput? _input;
  ForumBodyRubyTreeMetrics? _metrics;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  ForumBodyParagraphBudgetProbe? _probe;
  Iterator<ForumBodyNativeParagraphLease>? _prefix;
  bool _probeStarted = false;
  bool _budgetChecked = false;
  int _probeCursor = 0;
  int _nextNode = 0;
  ForumBodyTextRequestPreparation? _member;
  Map<int, ForumBodyTextLease> _leases = {};
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
      _member?.lastBudgetRejection;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ..._leases.values,
    if (_member != null) ..._member!.nativeLeases,
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
        final used = !_budgetChecked
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

  int _inspectBudget() {
    if (!_probeStarted) {
      _probe = _cache!.createBudgetProbe();
      final owned = _additionalOwned?.call();
      _guard();
      _prefix = owned?.iterator;
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
    if (_probeCursor < _input!.nativeRequests.length) {
      _input!.nativeRequests[_probeCursor].includeBudget(
        _probe!,
        width: _input!.maxWidth,
        textScaler: _metrics!.textScaler,
      );
      _guard();
      _probeCursor++;
      return 1;
    }
    _probe!.close();
    _probe = null;
    _budgetChecked = true;
    return 1;
  }

  int _advanceBinding(bool cachedOnly) {
    if (_nextNode < _input!.nodes.length) {
      final id = _nextNode;
      final node = _input!.nodes[id];
      if (node is ForumBodyRubyTreeText && node.needsNative) {
        final member = _member ??= ForumBodyTextRequestPreparation(
          cache: _cache!,
          request: node.request,
          ensureOwner: _guard,
          preparePaint: true,
          width: _input!.maxWidth,
          textScaler: _metrics!.textScaler,
          additionalOwnedLeases: () => [
            ..._leases.values,
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
        ForumBodyRubyTreeFrame() => _hasText[node.child]!,
        ForumBodyRubyTreeGroup() =>
          _hasText[node.base]! ||
              node.annotations.any(
                (a) => a.child != null && _hasText[a.child!]!,
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
    final origin = work.offset + Offset(0, box.frame.childTop);
    final container = node as ForumBodyRubyTreeContainer;
    switch (container) {
      case ForumBodyRubyTreeFrame():
        _positions.removeLast();
        _positions.add(_TreePosition(container.child, origin));
      case ForumBodyRubyTreeGroup():
        if (work.rank == -1) {
          work.rank = 0;
          _positions.add(
            _TreePosition(container.base, origin + box.group!.baseOffset),
          );
        } else if (work.rank < container.annotations.length) {
          final rank = work.rank++;
          final child = container.annotations[rank].child;
          if (child != null) {
            _positions.add(
              _TreePosition(
                child,
                origin + box.group!.annotations[rank].offset,
              ),
            );
          }
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
    _member?.close();
    _member = null;
    _probe?.close();
    _probe = null;
    _prefix = null;
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
    _dropOwner();
  }

  void close() => _retire(_TreeState.closed);
}

final class _TreePosition {
  _TreePosition(this.id, this.offset);
  final int id;
  final Offset offset;
  bool started = false;
  int rank = -1;
}
