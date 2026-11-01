import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_text_request.dart';
import '../paragraph/forum_body_text_request_preparation.dart';
import 'forum_body_ruby_group_layout.dart';
import 'forum_body_ruby_group_metrics.dart';
import 'forum_body_ruby_group_preparation.dart';
import 'forum_body_ruby_segment_layout.dart';
import 'forum_body_ruby_segment_request.dart';
import 'forum_body_text_band_layout.dart';

enum ForumBodyRubySegmentPreparationState {
  active,
  ready,
  transferred,
  failed,
  closed,
}

/// Visible ownership transaction for one original span component. All glyphs
/// remain in the existing cache; native shape OR picture work is limited to one
/// per quantum. The sole page transaction still owns scheduling and rollback.
final class ForumBodyRubySegmentPreparation {
  ForumBodyRubySegmentPreparation({
    required ForumBodyParagraphCache cache,
    required ForumBodyRubySegmentRequest request,
    required ForumBodyRubySegmentMetrics metrics,
    required void Function() ensureOwner,
    TextScaler textScaler = TextScaler.noScaling,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _cache = cache,
       _request = request,
       _metrics = metrics,
       _ensureOwner = ensureOwner,
       _scaler = textScaler,
       _additionalOwned = additionalOwnedLeases,
       expectedPartCount = request.nativeHandleCount,
       _missing = [
         for (final base in request.bases)
           ForumBodyParagraphContent.anonymousInline(
             identity: base.content.identity,
             fontRevision: base.content.fontRevision,
             styleRevision: base.content.styleRevision,
             style: base.content.style,
           ),
       ] {
    if (cache.isClosed) throw StateError('Segment owner is retired');
    if (metrics.direction != request.direction ||
        metrics.size.width > request.maxWidth ||
        metrics.level.annotations.length != request.sides.length) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.geometry,
      );
    }
    _assembly = ForumBodyRubySegmentAssembly(
      cache: cache,
      metrics: metrics,
      ensureOwner: _guard,
      columns: [
        for (final (index, base) in request.bases.indexed)
          (
            base: base.content,
            annotations: [for (final _ in request.sides) _missing[index]],
          ),
      ],
      spans: [for (final span in request.spans) span.request.content],
    );
  }

  ForumBodyParagraphCache? _cache;
  ForumBodyRubySegmentRequest? _request;
  ForumBodyRubySegmentMetrics? _metrics;
  void Function()? _ensureOwner;
  TextScaler? _scaler;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  List<ForumBodyParagraphContent> _missing;
  ForumBodyRubySegmentAssembly? _assembly;
  ForumBodyRubyGroupPreparation? _base;
  ForumBodyTextRequestPreparation? _span;
  ForumBodyParagraphBudgetProbe? _probe;
  Iterator<ForumBodyNativeParagraphLease>? _prefix;
  ForumBodyParagraphBudgetException? _rejection;
  ForumBodyTextRequest? _failedRequest;
  final int expectedPartCount;
  var _state = ForumBodyRubySegmentPreparationState.active;
  var _columns = 0;
  var _spans = 0;
  var _preparedParts = 0;
  var _workCount = 0;
  var _probeCursor = 0;
  var _blockedRevision = -1;
  var _budgetChecked = false;
  var _waiting = false;
  var _cacheMiss = false;
  var _operating = false;
  ForumBodyRubySegmentPreparationState get state => _state;
  bool get isReady => _state == ForumBodyRubySegmentPreparationState.ready;
  bool get cacheMiss => _cacheMiss;
  bool get waitingForLayoutBudget => _waiting;
  int get workCount => _workCount;
  int get preparedPartCount => _preparedParts;
  int get preparedColumnCount => _columns;
  int get preparedSpanCount => _spans;
  ForumBodyTextRequest? get failedRequest => _failedRequest;
  ForumBodyTextRequest? get currentRequest => _request == null
      ? null
      : _columns < _request!.bases.length
      ? _request!.bases[_columns]
      : _spans < _request!.spans.length
      ? _request!.spans[_spans].request
      : null;
  ForumBodyParagraphBudgetException? get lastBudgetRejection =>
      _waiting ? _rejection : null;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    if (_assembly != null) ..._assembly!.nativeLeases,
    if (_base != null) ..._base!.nativeLeases,
    if (_span != null) ..._span!.nativeLeases,
  ];

  ForumBodyRubyGroupPreparationStep advance({int maxParts = 32}) {
    if (_state != ForumBodyRubySegmentPreparationState.active) {
      throw StateError('Segment preparation is not active');
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
    final partsBefore = _preparedParts;
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
      final assembly = _assembly!;
      if (assembly.hasPendingMember ||
          (_columns == request.bases.length &&
              _spans == request.spans.length)) {
        units += assembly.advance(maxParts: maxParts - units);
        _guard();
        _columns = assembly.preparedColumnCount;
        _spans = assembly.preparedSpanCount;
        if (assembly.isReady) {
          _request = null;
          _metrics = null;
          _scaler = null;
          _missing = const [];
          _additionalOwned = null;
          _state = ForumBodyRubySegmentPreparationState.ready;
        }
        continue;
      }
      final rejectedAt = cache.budgetRevision;
      if (_columns < request.bases.length) {
        final base = _base ??= ForumBodyRubyGroupPreparation.forSegmentBase(
          cache: cache,
          base: request.bases[_columns],
          sides: request.sides,
          missingAnnotation: _missing[_columns],
          preparePaint: true,
          level: _metrics!.level,
          maxWidth: request.maxWidth,
          ensureOwner: _guard,
          textScaler: _scaler!,
          additionalOwnedLeases: _otherOwned,
        );
        final before = base.workCount;
        final parts = base.preparedPartCount;
        if (cachedOnly) {
          base.tryPrepareCached(maxParts: maxParts - units);
        } else {
          base.advance(maxParts: maxParts - units);
        }
        final used = base.workCount - before;
        units += used;
        _preparedParts += base.preparedPartCount - parts;
        _guard();
        _cacheMiss = base.cacheMiss;
        if (base.waitingForLayoutBudget) {
          _blocked(base.lastBudgetRejection!, rejectedAt);
        }
        final complete = base.isReady;
        if (complete) {
          final column = base.takeLayout();
          _base = null;
          try {
            _guard();
          } catch (_) {
            column.close();
            rethrow;
          }
          assembly.addColumn(column);
        }
        if (_cacheMiss ||
            _waiting ||
            (!complete && used == 0 && _probe == null)) {
          break;
        }
      } else {
        final span = request.spans[_spans];
        _checkSpan(span);
        if (span.request.content.projection.text.isEmpty) {
          assembly.addSpan((content: span.request.content, lease: null));
          units++;
        } else {
          final member = _span ??= ForumBodyTextRequestPreparation(
            cache: cache,
            request: span.request,
            ensureOwner: _guard,
            preparePaint: true,
            textScaler: _scaler!,
            width: request.maxWidth,
            additionalOwnedLeases: _otherOwned,
          );
          final step = member.advance(cachedOnly: cachedOnly);
          units += step.units;
          _guard();
          _cacheMiss = step.cacheMiss;
          if (step.waiting) _blocked(member.lastBudgetRejection!, rejectedAt);
          if (member.isReady) {
            final lease = member.takeLease();
            _span = null;
            try {
              _guard();
            } catch (_) {
              lease.release();
              rethrow;
            }
            assembly.addSpan((content: span.request.content, lease: lease));
            _preparedParts++;
          } else if (_cacheMiss ||
              _waiting ||
              (step.units == 0 && _probe == null)) {
            break;
          }
        }
      }
    }
    _workCount += units;
    return ForumBodyRubyGroupPreparationStep(
      partsPrepared: _preparedParts - partsBefore,
      partsInspected: inspected,
      layoutsBuilt: cache.layoutBuildCount - builds,
      picturesBuilt: cache.pictureBuildCount - pictures,
      formatUnitsPrepared: units,
      isReady: isReady,
      waitingForLayoutBudget: _waiting,
    );
  }

  void _checkSpan(ForumBodyRubySpanRequest span) {
    final input = _metrics!.spans[_spans].input;
    if (input.startColumn != span.startColumn ||
        input.endColumn != span.endColumn ||
        input.annotationIndex != span.annotationIndex ||
        input.annotation.side != _request!.sides[span.annotationIndex] ||
        input.annotation.gap != span.gap) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.geometry,
      );
    }
  }

  Iterable<ForumBodyNativeParagraphLease> _otherOwned() => [
    ..._assembly!.nativeLeases,
    ...?_additionalOwned?.call(),
  ];

  void _blocked(ForumBodyParagraphBudgetException error, int revision) {
    _rejection = error;
    _blockedRevision = revision;
    if (!_budgetChecked && _probe == null) {
      // A leaf can fit while the complete component plus owned page prefix
      // cannot. Probe every native slot, deduplicating actual shared-band keys.
      _probe = _cache!.createBudgetProbe();
      final prefix = _additionalOwned?.call();
      _guard();
      final iterator = prefix?.iterator;
      _guard();
      _prefix = iterator;
    }
    _waiting = _budgetChecked && _cache!.budgetRevision == revision;
  }

  int _inspectBudget(int maxParts) {
    var units = 0;
    while (units < maxParts) {
      final prefix = _prefix;
      if (prefix != null) {
        final hasNext = prefix.moveNext();
        _guard();
        if (hasNext) {
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
      // A release during a partial probe must resume the original cursor;
      // successful lower-bound admission does not reserve cache capacity.
      _waiting = _cache!.budgetRevision == _blockedRevision;
    }
    return units;
  }

  ForumBodyRubySegmentLayout takeLayout() => _operate(() {
    _guard();
    if (!isReady) throw StateError('Segment preparation is incomplete');
    final layout = _assembly!.takeLayout();
    _assembly = null;
    _state = ForumBodyRubySegmentPreparationState.transferred;
    _dropOwner();
    return layout;
  });

  T _operate<T>(T Function() action) {
    if (_operating) throw StateError('Segment preparation is reentrant');
    _operating = true;
    try {
      return action();
    } on ForumBodyRubyGroupPreparationException {
      _retire(ForumBodyRubySegmentPreparationState.failed);
      throw const ForumBodyParagraphBudgetException(
        ForumBodyParagraphBudgetFailure.content,
      );
    } catch (error) {
      final failed = error is ForumBodyTextBandLayoutException
          ? currentRequest
          : null;
      _retire(ForumBodyRubySegmentPreparationState.failed);
      _failedRequest = failed;
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_state != ForumBodyRubySegmentPreparationState.active && !isReady) {
      throw StateError('Segment preparation is retired');
    }
    _ensureOwner!();
    if ((_state != ForumBodyRubySegmentPreparationState.active && !isReady) ||
        _cache!.isClosed) {
      throw StateError('Segment preparation owner is retired');
    }
    for (final lease in nativeLeases) {
      if (!_cache!.ownsLease(lease)) {
        throw StateError('Segment glyph is retired');
      }
    }
  }

  void _retire(ForumBodyRubySegmentPreparationState state) {
    if (_state != ForumBodyRubySegmentPreparationState.active && !isReady) {
      return;
    }
    _state = state;
    _base?.close();
    _base = null;
    _span?.close();
    _span = null;
    _assembly?.close();
    _assembly = null;
    _dropOwner();
  }

  void _dropOwner() {
    _probe?.close();
    _probe = null;
    _prefix = null;
    _cache = null;
    _request = null;
    _metrics = null;
    _scaler = null;
    _ensureOwner = null;
    _additionalOwned = null;
    _missing = const [];
    _rejection = null;
    _waiting = false;
    _cacheMiss = false;
  }

  void close() {
    _failedRequest = null;
    _retire(ForumBodyRubySegmentPreparationState.closed);
  }
}
