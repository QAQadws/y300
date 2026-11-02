import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_text_request.dart';
import '../style/forum_body_style_options.dart' show ForumBodyRubySide;
import 'forum_body_ruby_group_layout.dart';
import 'forum_body_ruby_group_metrics.dart';

enum ForumBodyRubyGroupPreparationState {
  active,
  ready,
  transferred,
  failed,
  closed,
}

enum ForumBodyRubyGroupPreparationFailure { intrinsicBudget }

final class ForumBodyRubyGroupPreparationException implements Exception {
  const ForumBodyRubyGroupPreparationException(this.failure);
  final ForumBodyRubyGroupPreparationFailure failure;
  @override
  String toString() =>
      'ForumBodyRubyGroupPreparationException(${failure.name})';
}

final class ForumBodyRubyGroupPreparationStep {
  const ForumBodyRubyGroupPreparationStep({
    required this.partsPrepared,
    required this.layoutsBuilt,
    required this.partsInspected,
    required this.isReady,
    required this.waitingForLayoutBudget,
    this.picturesBuilt = 0,
    this.formatUnitsPrepared = 0,
  });
  final int partsPrepared;
  final int layoutsBuilt;
  final int picturesBuilt;
  final int partsInspected;
  final int formatUnitsPrepared;
  final bool isReady;
  final bool waitingForLayoutBudget;
  bool get madeProgress =>
      formatUnitsPrepared > 0 ||
      partsPrepared > 0 ||
      partsInspected > 0 ||
      layoutsBuilt > 0 ||
      picturesBuilt > 0 ||
      isReady;
}

/// One format-local ownership transaction for an already grouped column.
/// Native work stops after its first shape OR picture. Cache scanning, budget
/// inspection and final layer positioning share the caller's bounded quantum.
/// No scheduler, timer, DOM or persistent reading position is owned here.
final class ForumBodyRubyGroupPreparation {
  /// A segment member can be an empty native font strut under an annotation
  /// spanning several bases. Missing annotation slots own no glyph or source.
  factory ForumBodyRubyGroupPreparation.forSegmentBase({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextRequest base,
    required List<ForumBodyRubySide> sides,
    required void Function() ensureOwner,
    TextScaler textScaler = TextScaler.noScaling,
    double maxWidth = 16384,
    bool preparePaint = false,
    ForumBodyRubyLevelMetrics? level,
    ForumBodyParagraphContent? missingAnnotation,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) {
    final content = base.content;
    final empty =
        missingAnnotation ??
        ForumBodyParagraphContent.anonymousInline(
          identity: content.identity,
          fontRevision: content.fontRevision,
          styleRevision: content.styleRevision,
          style: content.style,
        );
    if (!empty.isSourceFree || empty.projection.text.isNotEmpty) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.content,
      );
    }
    return _open(
      cache: cache,
      base: base,
      annotations: [
        for (final side in sides)
          (
            request: ForumBodyTextRequest.paragraph(empty),
            gap: 0.0,
            side: side,
          ),
      ],
      ensureOwner: ensureOwner,
      textScaler: textScaler,
      maxWidth: maxWidth,
      preparePaint: preparePaint,
      level: level,
      additionalOwnedLeases: additionalOwnedLeases,
      allowEmptyBase: true,
    );
  }
  factory ForumBodyRubyGroupPreparation({
    required ForumBodyParagraphCache cache,
    required ForumBodyParagraphContent base,
    required ForumBodyParagraphContent annotation,
    required void Function() ensureOwner,
    TextScaler textScaler = TextScaler.noScaling,
    double gap = 0,
    double maxWidth = 16384,
    ForumBodyRubySide side = ForumBodyRubySide.over,
  }) => ForumBodyRubyGroupPreparation.fromRequests(
    cache: cache,
    base: ForumBodyTextRequest.paragraph(base),
    annotation: ForumBodyTextRequest.paragraph(annotation),
    ensureOwner: ensureOwner,
    textScaler: textScaler,
    gap: gap,
    maxWidth: maxWidth,
    side: side,
  );

  factory ForumBodyRubyGroupPreparation.fromRequests({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextRequest base,
    required ForumBodyTextRequest annotation,
    required void Function() ensureOwner,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
    TextScaler textScaler = TextScaler.noScaling,
    double gap = 0,
    double maxWidth = 16384,
    ForumBodyRubySide side = ForumBodyRubySide.over,
    ForumBodyRubyLevelMetrics? level,
  }) => ForumBodyRubyGroupPreparation.fromLayerRequests(
    cache: cache,
    base: base,
    annotations: [(request: annotation, gap: gap, side: side)],
    ensureOwner: ensureOwner,
    additionalOwnedLeases: additionalOwnedLeases,
    textScaler: textScaler,
    maxWidth: maxWidth,
    level: level,
  );

  factory ForumBodyRubyGroupPreparation.fromLayerRequests({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextRequest base,
    required List<
      ({ForumBodyTextRequest request, double gap, ForumBodyRubySide side})
    >
    annotations,
    required void Function() ensureOwner,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
    TextScaler textScaler = TextScaler.noScaling,
    double maxWidth = 16384,
    ForumBodyRubyLevelMetrics? level,
  }) => _open(
    cache: cache,
    base: base,
    annotations: annotations,
    ensureOwner: ensureOwner,
    additionalOwnedLeases: additionalOwnedLeases,
    textScaler: textScaler,
    maxWidth: maxWidth,
    level: level,
    preparePaint: true,
  );

  factory ForumBodyRubyGroupPreparation.forMetrics({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextRequest base,
    required ForumBodyTextRequest annotation,
    required void Function() ensureOwner,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
    TextScaler textScaler = TextScaler.noScaling,
    double gap = 0,
    double maxWidth = 16384,
    ForumBodyRubySide side = ForumBodyRubySide.over,
  }) => ForumBodyRubyGroupPreparation.forLayerMetrics(
    cache: cache,
    base: base,
    annotations: [(request: annotation, gap: gap, side: side)],
    ensureOwner: ensureOwner,
    additionalOwnedLeases: additionalOwnedLeases,
    textScaler: textScaler,
    maxWidth: maxWidth,
  );

  factory ForumBodyRubyGroupPreparation.forLayerMetrics({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextRequest base,
    required List<
      ({ForumBodyTextRequest request, double gap, ForumBodyRubySide side})
    >
    annotations,
    required void Function() ensureOwner,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
    TextScaler textScaler = TextScaler.noScaling,
    double maxWidth = 16384,
  }) => _open(
    cache: cache,
    base: base,
    annotations: annotations,
    ensureOwner: ensureOwner,
    additionalOwnedLeases: additionalOwnedLeases,
    textScaler: textScaler,
    maxWidth: maxWidth,
    preparePaint: false,
  );

  static ForumBodyRubyGroupPreparation _open({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextRequest base,
    required List<
      ({ForumBodyTextRequest request, double gap, ForumBodyRubySide side})
    >
    annotations,
    required void Function() ensureOwner,
    required Iterable<ForumBodyNativeParagraphLease> Function()?
    additionalOwnedLeases,
    required TextScaler textScaler,
    required double maxWidth,
    required bool preparePaint,
    ForumBodyRubyLevelMetrics? level,
    bool allowEmptyBase = false,
  }) {
    if (cache.isClosed) throw StateError('Ruby preparation owner is retired');
    final inputs = List.of(annotations);
    final assembly = ForumBodyRubyGroupAssembly(
      cache: cache,
      base: base.content,
      annotations: [
        for (final item in inputs)
          (content: item.request.content, gap: item.gap, side: item.side),
      ],
      maxWidth: maxWidth,
      level: level,
      preparePaint: preparePaint,
      allowEmptyBase: allowEmptyBase,
    );
    return ForumBodyRubyGroupPreparation._(
      cache,
      [base, ...inputs.map((item) => item.request)],
      [for (final item in inputs) item.gap],
      [for (final item in inputs) item.side],
      ensureOwner,
      textScaler,
      additionalOwnedLeases,
      maxWidth,
      preparePaint,
      assembly,
    );
  }

  ForumBodyRubyGroupPreparation._(
    this._cache,
    this._requests,
    List<double> gaps,
    List<ForumBodyRubySide> sides,
    this._ensureOwner,
    this._textScaler,
    this._additionalOwnedLeases,
    this.maxWidth,
    this._preparePaint,
    this._assembly,
  ) : _gaps = List.unmodifiable(gaps),
      _sides = List.unmodifiable(sides),
      _budgetSlots = [
        for (var i = 0; i < _requests.length; i++)
          if (i == 0 || _requests[i].content.projection.text.isNotEmpty) i,
      ] {
    expectedPartCount = _budgetSlots.length;
  }
  ForumBodyParagraphCache? _cache;
  List<ForumBodyTextRequest> _requests;
  final List<double> _gaps;
  final List<ForumBodyRubySide> _sides;
  final List<int> _budgetSlots;
  void Function()? _ensureOwner;
  TextScaler? _textScaler;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwnedLeases;
  ForumBodyRubyGroupAssembly? _assembly;
  ForumBodyTextLease? _pending;
  ForumBodyParagraphBudgetProbe? _probe;
  ForumBodyParagraphBudgetException? _budgetRejection;
  final double maxWidth;
  double get gap => _gaps.single;
  ForumBodyRubySide get side => _sides.single;
  late final int expectedPartCount;
  final bool _preparePaint;
  ForumBodyRubyGroupLayout? _group;
  ForumBodyRubyGroupMetrics? _metrics;
  var _state = ForumBodyRubyGroupPreparationState.active;
  var _nextSlot = 0;
  var _preparedParts = 0;
  var _probeCursor = 0;
  var _blockedRevision = 0;
  var _workCount = 0;
  var _waiting = false;
  var _cacheMiss = false;
  var _budgetChecked = false;
  var _operating = false;

  ForumBodyRubyGroupPreparationState get state => _state;
  bool get isReady => _state == ForumBodyRubyGroupPreparationState.ready;
  bool get waitingForLayoutBudget => _waiting;

  /// A cache-only quantum ended on an absent glyph or unrecorded picture,
  /// rather than merely exhausting its numeric/scanning work allowance.
  bool get cacheMiss => _cacheMiss;
  int get preparedPartCount => _preparedParts;
  int get workCount => _workCount;
  ForumBodyParagraphBudgetException? get lastBudgetRejection =>
      _waiting ? _budgetRejection : null;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_pending,
    if (_assembly != null) ..._assembly!.nativeLeases,
    if (_group != null) ..._group!.nativeLeases,
  ];

  ForumBodyRubyGroupPreparationStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (_state != ForumBodyRubyGroupPreparationState.active) {
      throw StateError('Ruby preparation is not active');
    }
    if (maxParts <= 0) throw ArgumentError.value(maxParts, 'maxParts');
    return _operate(() => _advance(cachedOnly: cachedOnly, maxParts: maxParts));
  }

  /// A bounded cache-only quantum. False may mean an incomplete warm scan or
  /// numeric positioning, as well as an actual miss. No native work is issued.
  bool tryPrepareCached({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts, 'maxParts');
    return _operate(() {
      _guard();
      return isReady || _advance(cachedOnly: true, maxParts: maxParts).isReady;
    });
  }

  ForumBodyRubyGroupPreparationStep _advance({
    required bool cachedOnly,
    required int maxParts,
  }) {
    _guard();
    final cache = _cache!;
    final partsBefore = _preparedParts;
    final buildsBefore = cache.layoutBuildCount;
    final picturesBefore = cache.pictureBuildCount;
    var inspected = 0;
    var units = 0;
    var rejectedAt = cache.budgetRevision;
    _waiting = false;
    _cacheMiss = false;
    if (_probe != null) {
      inspected = _inspectBudget(maxParts);
      units += inspected;
      _waiting = _budgetChecked && cache.budgetRevision == _blockedRevision;
    } else {
      _budgetRejection = null;
      try {
        while (_nextSlot < _requests.length && units < maxParts) {
          final empty =
              _nextSlot != 0 &&
              _requests[_nextSlot].content.projection.text.isEmpty;
          if (!empty) {
            if (cache.layoutBuildCount != buildsBefore ||
                cache.pictureBuildCount != picturesBefore) {
              break;
            }
            rejectedAt = cache.budgetRevision;
            if (_pending == null && !_acquire(cachedOnly: cachedOnly)) {
              _cacheMiss = cachedOnly;
              break;
            }
            if (_preparePaint && !_pending!.layout.isPaintPrepared) {
              if (cachedOnly) {
                _cacheMiss = true;
                break;
              }
              if (cache.layoutBuildCount != buildsBefore) break;
              cache.prepareBandChildPaint(
                _pending! as ForumBodyTextBandChildLease,
              );
              _guard();
            }
          }
          final lease = _pending;
          _pending = null;
          if (_nextSlot == 0) {
            _assembly!.addBase(lease!);
          } else {
            _assembly!.addAnnotation(lease);
          }
          _nextSlot++;
          if (!empty) _preparedParts++;
          units++;
          _guard();
        }
        if (_nextSlot == _requests.length && units < maxParts) {
          units += _assembly!.advance(maxParts: maxParts - units);
          _guard();
          _finishIfReady();
        }
      } on ForumBodyParagraphBudgetException catch (error) {
        _guard();
        if (error.failure != ForumBodyParagraphBudgetFailure.pinned) rethrow;
        _budgetRejection = error;
        final additional =
            _additionalOwnedLeases?.call() ??
            const <ForumBodyNativeParagraphLease>[];
        _guard();
        final external = cache.isBlockedByExternalPins(error, [
          ...nativeLeases,
          ...additional,
        ]);
        _guard();
        if (!external) {
          throw const ForumBodyRubyGroupPreparationException(
            ForumBodyRubyGroupPreparationFailure.intrinsicBudget,
          );
        }
        _blockedRevision = rejectedAt;
        if (!_budgetChecked) {
          _probe ??= cache.createBudgetProbe();
          inspected = _inspectBudget(maxParts - units);
          units += inspected;
        }
        _waiting = _budgetChecked && cache.budgetRevision == rejectedAt;
      }
    }
    final nativeWork =
        cache.layoutBuildCount -
        buildsBefore +
        cache.pictureBuildCount -
        picturesBefore;
    if (nativeWork > 0 && units == 0) units = 1;
    _workCount += units;
    return ForumBodyRubyGroupPreparationStep(
      partsPrepared: _preparedParts - partsBefore,
      layoutsBuilt: cache.layoutBuildCount - buildsBefore,
      picturesBuilt: cache.pictureBuildCount - picturesBefore,
      partsInspected: inspected,
      formatUnitsPrepared: units,
      isReady: isReady,
      waitingForLayoutBudget: _waiting,
    );
  }

  bool _acquire({required bool cachedOnly}) {
    final lease = _requests[_nextSlot].acquire(
      _cache!,
      width: maxWidth,
      textScaler: _textScaler!,
      cachedOnly: cachedOnly,
    );
    try {
      _guard();
    } catch (_) {
      lease?.release();
      rethrow;
    }
    if (lease == null) return false;
    _pending = lease;
    return true;
  }

  int _inspectBudget(int maxParts) {
    var inspected = 0;
    try {
      while (_probeCursor < _budgetSlots.length && inspected < maxParts) {
        _requests[_budgetSlots[_probeCursor]].includeBudget(
          _probe!,
          width: maxWidth,
          textScaler: _textScaler!,
        );
        _guard();
        _probeCursor++;
        inspected++;
      }
      if (_probeCursor == _budgetSlots.length) {
        _probe?.close();
        _probe = null;
        _budgetChecked = true;
      }
      return inspected;
    } on ForumBodyParagraphBudgetException {
      throw const ForumBodyRubyGroupPreparationException(
        ForumBodyRubyGroupPreparationFailure.intrinsicBudget,
      );
    }
  }

  void _finishIfReady() {
    if (!_assembly!.isReady) return;
    _guard();
    if (_preparePaint) {
      final group = _assembly!.takeLayout();
      _assembly = null;
      try {
        _guard();
      } catch (_) {
        group.close();
        rethrow;
      }
      _group = group;
    } else {
      final metrics = _assembly!.takeMetrics();
      _assembly = null;
      _guard();
      _metrics = metrics;
    }
    _requests = const [];
    _textScaler = null;
    _state = ForumBodyRubyGroupPreparationState.ready;
  }

  ForumBodyRubyGroupLayout takeLayout() {
    if (!isReady) throw StateError('Ruby preparation is not ready');
    if (!_preparePaint) throw StateError('Ruby preparation contains metrics');
    return _operate(() {
      _guard();
      final group = _group!;
      _group = null;
      _state = ForumBodyRubyGroupPreparationState.transferred;
      _dropOwner();
      return group;
    });
  }

  ForumBodyRubyGroupMetrics takeMetrics() {
    if (!isReady) throw StateError('Ruby preparation is not ready');
    if (_preparePaint) throw StateError('Ruby preparation contains a layout');
    return _operate(() {
      _guard();
      final metrics = _metrics!;
      _metrics = null;
      _state = ForumBodyRubyGroupPreparationState.transferred;
      _dropOwner();
      return metrics;
    });
  }

  T _operate<T>(T Function() action) {
    if (_operating) throw StateError('Ruby preparation operation is reentrant');
    _operating = true;
    try {
      return action();
    } catch (_) {
      _retire(ForumBodyRubyGroupPreparationState.failed);
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_state != ForumBodyRubyGroupPreparationState.active && !isReady) {
      throw StateError('Ruby preparation is retired');
    }
    _ensureOwner!();
    if ((_state != ForumBodyRubyGroupPreparationState.active && !isReady) ||
        _cache!.isClosed) {
      throw StateError('Ruby preparation owner is retired');
    }
    for (final lease in nativeLeases) {
      if (!_cache!.ownsLease(lease)) {
        throw StateError('Ruby preparation child is retired');
      }
    }
  }

  void _retire(ForumBodyRubyGroupPreparationState state) {
    if (_state != ForumBodyRubyGroupPreparationState.active && !isReady) return;
    _state = state;
    final pending = _pending;
    _pending = null;
    pending?.release();
    _assembly?.close();
    _assembly = null;
    _group?.close();
    _group = null;
    _metrics = null;
    _dropOwner();
  }

  void _dropOwner() {
    _probe?.close();
    _probe = null;
    _cache = null;
    _requests = const [];
    _textScaler = null;
    _ensureOwner = null;
    _additionalOwnedLeases = null;
    _budgetRejection = null;
    _waiting = false;
    _cacheMiss = false;
  }

  void close() => _retire(ForumBodyRubyGroupPreparationState.closed);
}
