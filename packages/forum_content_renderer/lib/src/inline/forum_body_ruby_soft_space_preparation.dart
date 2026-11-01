part of 'forum_body_ruby_soft_space_layout.dart';

enum ForumBodyRubySoftSpacePreparationState {
  active,
  ready,
  transferred,
  failed,
  closed,
}

/// Same single-text worker for glyph-only planning and visible ownership.
/// Metrics release each pin immediately; visible delivery admits the whole
/// footprint and validates one actual member per unit before publication.
final class ForumBodyRubySoftSpacePreparation {
  ForumBodyRubySoftSpacePreparation.forMetrics({
    required ForumBodyParagraphCache cache,
    required ForumBodyRubySoftSpaceRequest request,
    required void Function() ensureOwner,
    TextScaler textScaler = TextScaler.noScaling,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : this._(
         cache,
         request,
         ensureOwner,
         textScaler,
         additionalOwnedLeases,
         null,
       );
  ForumBodyRubySoftSpacePreparation.fromRequests({
    required ForumBodyParagraphCache cache,
    required ForumBodyRubySoftSpaceRequest request,
    required ForumBodyRubySoftSpaceMetrics metrics,
    required void Function() ensureOwner,
    TextScaler textScaler = TextScaler.noScaling,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : this._(
         cache,
         request,
         ensureOwner,
         textScaler,
         additionalOwnedLeases,
         metrics,
       );
  ForumBodyRubySoftSpacePreparation._(
    this._cache,
    this._request,
    this._ensureOwner,
    this._scaler,
    this._additionalOwned,
    this._target,
  ) : _paint = _target != null {
    if (_cache!.isClosed) throw StateError('Ruby soft-space owner is retired');
    if (_target != null) {
      validateForumBodyRubySoftSpaceTarget(_request!, _target!);
    }
  }
  ForumBodyParagraphCache? _cache;
  ForumBodyRubySoftSpaceRequest? _request;
  void Function()? _ensureOwner;
  TextScaler? _scaler;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  ForumBodyRubySoftSpaceMetrics? _target;
  final bool _paint;
  ForumBodyTextRequestPreparation? _member;
  ForumBodyRubySoftSpaceComposition? _composition;
  final _measured = <ForumBodyRubySoftSpaceMeasuredMember>[];
  List<ForumBodyTextLease> _leases = [];
  List<ForumBodyParagraphContent> _contents = [];
  ForumBodyRubySoftSpaceMetrics? _metrics;
  ForumBodyRubySoftSpaceLayout? _layout;
  ForumBodyParagraphBudgetProbe? _probe;
  Iterator<ForumBodyNativeParagraphLease>? _prefix;
  ForumBodyParagraphBudgetException? _rejection;
  ForumBodyTextRequest? _failedRequest;
  var _state = ForumBodyRubySoftSpacePreparationState.active;
  var _rank = 0;
  var _prepared = 0;
  var _workCount = 0;
  var _probeCursor = 0;
  var _blockedRevision = -1;
  var _budgetChecked = false;
  var _waiting = false;
  var _cacheMiss = false;
  var _operating = false;
  ForumBodyRubySoftSpacePreparationState get state => _state;
  bool get isReady => _state == ForumBodyRubySoftSpacePreparationState.ready;
  bool get cacheMiss => _cacheMiss;
  bool get waitingForLayoutBudget => _waiting;
  int get workCount => _workCount;
  int get preparedPartCount => _prepared;
  ForumBodyTextRequest? get failedRequest => _failedRequest;
  ForumBodyTextRequest? get currentRequest =>
      _request == null || _prepared == _request!.members.length
      ? null
      : _request!.members[_prepared].request;
  ForumBodyParagraphBudgetException? get lastBudgetRejection =>
      _waiting ? _rejection : null;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ..._leases,
    if (_member != null) ..._member!.nativeLeases,
  ];

  ForumBodyRubyGroupPreparationStep advance({int maxParts = 32}) {
    if (_state != ForumBodyRubySoftSpacePreparationState.active) {
      throw StateError('Ruby soft-space preparation is not active');
    }
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() => _advance(maxParts, false));
  }

  bool tryPrepareCached({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() {
      _guard();
      return isReady || _advance(maxParts, true).isReady;
    });
  }

  ForumBodyRubyGroupPreparationStep _advance(int maxParts, bool cachedOnly) {
    _guard();
    final cache = _cache!;
    final request = _request!;
    final builds = cache.layoutBuildCount;
    final pictures = cache.pictureBuildCount;
    final beforeParts = _prepared;
    var units = 0;
    var inspected = 0;
    _waiting = false;
    _cacheMiss = false;
    while (units < maxParts && !isReady) {
      if (cache.layoutBuildCount != builds ||
          cache.pictureBuildCount != pictures) {
        break;
      }
      if (_probe != null) {
        final used = _inspectBudget(maxParts - units);
        units += used;
        inspected += used;
        if (_probe != null || _waiting) break;
        continue;
      }
      if (_rejection != null &&
          _budgetChecked &&
          cache.budgetRevision == _blockedRevision) {
        _waiting = true;
        break;
      }
      _rejection = null;
      if (_paint && _rank < request.sides.length) {
        validateForumBodyRubySoftSpaceRank(request, _target!, _rank++);
        units++;
      } else if (_prepared < request.members.length) {
        final input = request.members[_prepared];
        if (_paint) {
          validateForumBodyRubySoftSpaceMember(request, _target!, _prepared);
        }
        final rejectedAt = cache.budgetRevision;
        final member = _member ??= ForumBodyTextRequestPreparation(
          cache: cache,
          request: input.request,
          ensureOwner: _guard,
          preparePaint: _paint,
          textScaler: _scaler!,
          width: request.maxWidth,
          additionalOwnedLeases: _otherOwned,
        );
        final step = member.advance(cachedOnly: cachedOnly);
        units += step.units;
        _guard();
        _cacheMiss = step.cacheMiss;
        if (step.waiting) {
          if (_paint) {
            _blocked(member.lastBudgetRejection!, rejectedAt);
          } else {
            _waiting = true;
            _rejection = member.lastBudgetRejection;
          }
        }
        if (member.isReady) {
          final lease = member.takeLease();
          _member = null;
          var retained = false;
          try {
            _guard();
            if (!identical(lease.content, input.request.content)) {
              throw const ForumBodyRubyGroupException(
                ForumBodyRubyGroupFailure.content,
              );
            }
            final measured = ForumBodyRubyAnnotationMetrics.measure(
              cache: cache,
              lease: lease,
              side: input.annotationIndex == null
                  ? ForumBodyRubySide.over
                  : request.sides[input.annotationIndex!],
              gap: input.gap,
            );
            if (_paint) {
              final target = _target!.members[_prepared].input.font;
              const tolerance = ForumBodyRubyGroupMetrics.geometryTolerance;
              final a = measured.bounds;
              final b = target.bounds;
              if (!lease.layout.isPaintPrepared ||
                  (measured.fontBaseline - target.fontBaseline).abs() >
                      tolerance ||
                  (a.left - b.left).abs() > tolerance ||
                  (a.top - b.top).abs() > tolerance ||
                  (a.right - b.right).abs() > tolerance ||
                  (a.bottom - b.bottom).abs() > tolerance) {
                throw const ForumBodyRubyGroupException(
                  ForumBodyRubyGroupFailure.geometry,
                );
              }
              _leases.add(lease);
              _contents.add(lease.content);
              retained = true;
            } else {
              _measured.add(
                ForumBodyRubySoftSpaceMeasuredMember(
                  annotationIndex: input.annotationIndex,
                  font: measured,
                ),
              );
            }
            _prepared++;
          } finally {
            if (!retained) lease.release();
          }
        } else if (_cacheMiss ||
            _waiting ||
            (step.units == 0 && _probe == null)) {
          break;
        }
      } else if (!_paint) {
        final composition = _composition ??= ForumBodyRubySoftSpaceComposition(
          members: _measured,
          sides: request.sides,
          direction: request.direction,
          maxWidth: request.maxWidth,
        );
        if (!composition.isComplete) {
          units += composition.advance(maxParts: maxParts - units);
          _guard();
        }
        if (composition.isComplete && units < maxParts) {
          _metrics = composition.result;
          _composition = null;
          _measured.clear();
          _ready();
          units++;
        }
      } else {
        _layout = ForumBodyRubySoftSpaceLayout._(_leases, _contents, _target!);
        _ready();
        units++;
      }
      _guard();
    }
    _workCount += units;
    return ForumBodyRubyGroupPreparationStep(
      partsPrepared: _prepared - beforeParts,
      partsInspected: inspected,
      layoutsBuilt: cache.layoutBuildCount - builds,
      picturesBuilt: cache.pictureBuildCount - pictures,
      formatUnitsPrepared: units,
      isReady: isReady,
      waitingForLayoutBudget: _waiting,
    );
  }

  void _ready() {
    _request = null;
    _target = null;
    _scaler = null;
    _additionalOwned = null;
    _state = ForumBodyRubySoftSpacePreparationState.ready;
  }

  Iterable<ForumBodyNativeParagraphLease> _otherOwned() => [
    ..._leases,
    ...?_additionalOwned?.call(),
  ];
  void _blocked(ForumBodyParagraphBudgetException error, int revision) {
    _rejection = error;
    _blockedRevision = revision;
    if (!_budgetChecked && _probe == null) {
      _probe = _cache!.createBudgetProbe();
      final prefix = _additionalOwned?.call();
      _guard();
      _prefix = prefix?.iterator;
      _guard();
    }
    _waiting = _budgetChecked && _cache!.budgetRevision == revision;
  }

  int _inspectBudget(int maxParts) {
    var units = 0;
    while (units < maxParts) {
      final prefix = _prefix;
      if (prefix != null) {
        final next = prefix.moveNext();
        _guard();
        if (next) {
          _probe!.includeLease(prefix.current);
          _guard();
          units++;
          continue;
        }
        _prefix = null;
      }
      if (_probeCursor == _request!.nativeRequests.length) break;
      _request!.nativeRequests[_probeCursor].includeBudget(
        _probe!,
        width: _request!.maxWidth,
        textScaler: _scaler!,
      );
      _guard();
      _probeCursor++;
      units++;
    }
    if (_prefix == null && _probeCursor == _request!.nativeRequests.length) {
      _probe!.close();
      _probe = null;
      _budgetChecked = true;
      _waiting = _cache!.budgetRevision == _blockedRevision;
    }
    return units;
  }

  ForumBodyRubySoftSpaceMetrics takeMetrics() {
    if (_paint) throw StateError('Ruby soft-space result is a visible layout');
    return _operate(() {
      _guard();
      if (!isReady || _paint) {
        throw StateError('Ruby soft-space metrics are incomplete');
      }
      final result = _metrics!;
      _metrics = null;
      _state = ForumBodyRubySoftSpacePreparationState.transferred;
      _dropOwner();
      return result;
    });
  }

  ForumBodyRubySoftSpaceLayout takeLayout() {
    if (!_paint) throw StateError('Ruby soft-space result is numeric metrics');
    return _operate(() {
      _guard();
      if (!isReady || !_paint) {
        throw StateError('Ruby soft-space layout is incomplete');
      }
      final result = _layout!;
      _layout = null;
      _leases = [];
      _contents = [];
      _state = ForumBodyRubySoftSpacePreparationState.transferred;
      _dropOwner();
      return result;
    });
  }

  T _operate<T>(T Function() action) {
    if (_operating) {
      throw StateError('Ruby soft-space preparation is reentrant');
    }
    _operating = true;
    try {
      return action();
    } catch (error) {
      final failed = error is ForumBodyTextBandLayoutException
          ? currentRequest
          : null;
      _retire(ForumBodyRubySoftSpacePreparationState.failed);
      _failedRequest = failed;
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_state != ForumBodyRubySoftSpacePreparationState.active && !isReady) {
      throw StateError('Ruby soft-space preparation is retired');
    }
    _ensureOwner!();
    if ((_state != ForumBodyRubySoftSpacePreparationState.active && !isReady) ||
        _cache!.isClosed) {
      throw StateError('Ruby soft-space owner is retired');
    }
    for (final lease in nativeLeases) {
      if (!_cache!.ownsLease(lease)) {
        throw StateError('Ruby soft-space glyph is retired');
      }
    }
  }

  void _retire(ForumBodyRubySoftSpacePreparationState state) {
    if (_state != ForumBodyRubySoftSpacePreparationState.active && !isReady) {
      return;
    }
    _state = state;
    _member?.close();
    _member = null;
    _layout?.close();
    _layout = null;
    for (final l in _leases) {
      l.release();
    }
    _leases = [];
    _contents = [];
    _composition = null;
    _measured.clear();
    _metrics = null;
    _dropOwner();
  }

  void _dropOwner() {
    _probe?.close();
    _probe = null;
    _prefix = null;
    _cache = null;
    _request = null;
    _target = null;
    _ensureOwner = null;
    _scaler = null;
    _additionalOwned = null;
    _waiting = false;
    _cacheMiss = false;
    _rejection = null;
  }

  void close() {
    _failedRequest = null;
    _retire(ForumBodyRubySoftSpacePreparationState.closed);
  }
}
