import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../pagination/forum_body_text_page_content.dart';
import '../paragraph/forum_body_text_request.dart';
import 'forum_body_inline_plan_input.dart';
import 'forum_body_ruby_group_metrics.dart';
import 'forum_body_ruby_group_preparation.dart';
import 'forum_body_ruby_row_alignment.dart';
import 'forum_body_text_band_content.dart';
import 'forum_body_text_band_layout.dart';

enum _State { active, ready, transferred, closed }

/// The session's one pending mixed format, using its cache/guard/scheduler.
/// Pair glyph metrics and the parent shape occur in distinct bounded units;
/// published input is pure and only the actual parent lease enters composer.
final class ForumBodyInlinePlanPreparation {
  ForumBodyInlinePlanPreparation({
    required ForumBodyInlinePlanInput input,
    required ForumBodyParagraphCache cache,
    required TextScaler textScaler,
    required void Function() ensureOwner,
  }) : _input = input,
       _cache = cache,
       _textScaler = textScaler,
       _ensureOwner = ensureOwner,
       width = input.width;

  ForumBodyInlinePlanInput? _input;
  ForumBodyParagraphCache? _cache;
  TextScaler? _textScaler;
  void Function()? _ensureOwner;
  final double width;
  final _metrics = <ForumBodyRubyGroupMetrics>[];
  ForumBodyRubyRowAlignment? _alignment;
  final _retriedBands = Set<ForumBodyTextBandContent>.identity();
  ForumBodyRubyGroupPreparation? _pair;
  ForumBodyInlineParagraphLease? _parent;
  ForumBodyInlineParagraphLease? _probe;
  ForumBodyInlinePageContent? _result;
  var _state = _State.active;
  var _operating = false;
  bool get isReady => _state == _State.ready;

  ({int partsPrepared, bool isReady, bool waitingForLayoutBudget}) advance({
    int maxParts = 32,
  }) {
    if (_state != _State.active) throw StateError('Inline plan is not active');
    if (maxParts <= 0) throw ArgumentError.value(maxParts, 'maxParts');
    return _operate(() {
      _guard();
      final cache = _cache!;
      final before = cache.layoutBuildCount;
      var parts = 0;
      var waiting = false;
      while (_metrics.length < _input!.groups.length && parts < maxParts) {
        final request = _input!.groups[_metrics.length];
        final pair = _pair ??= ForumBodyRubyGroupPreparation.forLayerMetrics(
          cache: cache,
          base: request.base,
          annotations: request.annotations,
          ensureOwner: _guard,
          textScaler: _textScaler!,
          maxWidth: request.maxWidth,
        );
        try {
          final revisionBefore = cache.budgetRevision;
          final step = pair.advance(maxParts: maxParts - parts);
          final budgetChanged = cache.budgetRevision != revisionBefore;
          parts += step.formatUnitsPrepared;
          if (step.formatUnitsPrepared == 0 &&
              (step.madeProgress || budgetChanged)) {
            parts++;
          }
          if (step.isReady) {
            _metrics.add(pair.takeMetrics());
            pair.close();
            _pair = null;
          }
          waiting = step.waitingForLayoutBudget;
          if (!step.madeProgress) {
            if (!waiting && !budgetChanged) {
              throw StateError('Inline metric preparation made no progress');
            }
            break;
          }
          if (waiting || cache.layoutBuildCount != before) break;
        } on ForumBodyTextBandLayoutException catch (error) {
          _guard();
          // Native child counts omit empty ranks, just like admission. Numeric
          // finalization cannot throw a native band isolation exception.
          if (pair.preparedPartCount >= request.nativeRequests.length) rethrow;
          final failed = request.nativeRequests[pair.preparedPartCount];
          if (failed is! ForumBodyTextBandChildRequest) rethrow;
          pair.close();
          _pair = null;
          final hint = error.requiredGutter;
          final retry =
              error.failure == ForumBodyTextBandLayoutFailure.isolation &&
              hint != null &&
              hint.isFinite &&
              hint > 0 &&
              hint <= 16384 &&
              _retriedBands.add(failed.band);
          _input!.replaceBand(
            failed.band,
            // Keep one logical pixel beyond the measured minimum so native
            // float rounding cannot repeatedly miss the isolation boundary.
            retry ? (hint + 1).clamp(1.0, 16384.0) : null,
          );
          // A failed native band never triggers another shape in this unit.
          parts++;
          break;
        }
      }
      if (_metrics.length == _input!.groups.length &&
          parts < maxParts &&
          cache.layoutBuildCount == before) {
        final step = _advanceLayout(maxParts: maxParts - parts);
        parts += step.partsPrepared;
        waiting = step.waitingForLayoutBudget;
      }
      return (
        partsPrepared: parts,
        isReady: isReady,
        waitingForLayoutBudget: waiting,
      );
    });
  }

  ({int partsPrepared, bool waitingForLayoutBudget}) _advanceLayout({
    required int maxParts,
  }) {
    final alignment = _alignment ??= ForumBodyRubyRowAlignment(
      columns: _metrics,
      levelIds: _input!.rubyLevelIds,
      atomOffsets: _input!.atomEngineOffsets,
    );
    var parts = 0;
    if (!alignment.isComplete && !alignment.needsRows) {
      parts += alignment.advance(maxParts: maxParts);
      _guard();
      if (parts == maxParts) {
        return (partsPrepared: parts, waitingForLayoutBudget: false);
      }
    }
    if (alignment.needsRows) {
      final step = _acquireParent(alignment, provisional: true);
      return (
        partsPrepared: parts + step.partsPrepared,
        waitingForLayoutBudget: step.waitingForLayoutBudget,
      );
    }
    if (!alignment.isComplete) {
      return (partsPrepared: parts, waitingForLayoutBudget: false);
    }
    if (!alignment.hasChanges) {
      if (_probe != null) {
        _parent = _probe;
        _probe = null;
        _makeReady(alignment);
        return (partsPrepared: parts + 1, waitingForLayoutBudget: false);
      }
      final step = _acquireParent(alignment, provisional: false);
      return (
        partsPrepared: parts + step.partsPrepared,
        waitingForLayoutBudget: step.waitingForLayoutBudget,
      );
    }
    if (_probe != null) {
      // Only the last alias evicts this unneeded provisional shape. Release
      // before the final acquisition so it cannot displace a warm glyph band.
      _probe!.releaseProvisional();
      _probe = null;
      _guard();
      return (partsPrepared: parts + 1, waitingForLayoutBudget: false);
    }
    if (_parent == null) {
      final step = _acquireParent(alignment, provisional: false);
      return (
        partsPrepared: parts + step.partsPrepared,
        waitingForLayoutBudget: step.waitingForLayoutBudget,
      );
    }
    parts += alignment.verifyRows(
      _parent!.layout.lines,
      maxParts: maxParts - parts,
    );
    _guard();
    if (alignment.isVerified) _makeReady(alignment);
    return (partsPrepared: parts, waitingForLayoutBudget: false);
  }

  ({int partsPrepared, bool waitingForLayoutBudget}) _acquireParent(
    ForumBodyRubyRowAlignment alignment, {
    required bool provisional,
  }) {
    final cache = _cache!;
    final rejectedAt = cache.budgetRevision;
    ForumBodyInlineParagraphLease? parent;
    void release() {
      if (identical(_parent, parent)) _parent = null;
      if (identical(_probe, parent)) _probe = null;
      if (provisional) {
        parent?.releaseProvisional();
      } else {
        parent?.release();
      }
    }

    try {
      parent = cache.acquireInline(
        content: _input!.content,
        width: width,
        dimensions: alignment.dimensions,
        textScaler: _textScaler!,
      );
      _guard();
      if (provisional) {
        _probe = parent;
        alignment.attachRows(parent.layout.lines);
      } else {
        _parent = parent;
        if (!alignment.hasChanges) _makeReady(alignment);
      }
      return (partsPrepared: 1, waitingForLayoutBudget: false);
    } on ForumBodyParagraphBudgetException catch (error) {
      release();
      _guard();
      if (error.failure != ForumBodyParagraphBudgetFailure.pinned) rethrow;
      final waiting = cache.budgetRevision == rejectedAt;
      return (partsPrepared: waiting ? 0 : 1, waitingForLayoutBudget: waiting);
    } catch (_) {
      release();
      rethrow;
    }
  }

  void _makeReady(ForumBodyRubyRowAlignment alignment) {
    _guard();
    _result = ForumBodyInlinePageContent(
      content: _input!.content,
      dimensions: alignment.dimensions,
      rubyGroups: _input!.groups,
      rubyLevelMetrics: alignment.targets,
    );
    _guard();
    _state = _State.ready;
  }

  ({ForumBodyInlinePageContent content, ForumBodyInlineParagraphLease lease})
  take() {
    if (!isReady) throw StateError('Inline plan is not ready');
    return _operate(() {
      _guard();
      final result = (content: _result!, lease: _parent!);
      _parent = null;
      _state = _State.transferred;
      _drop();
      return result;
    });
  }

  T _operate<T>(T Function() action) {
    if (_operating) throw StateError('Inline plan operation is reentrant');
    _operating = true;
    try {
      return action();
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_state != _State.active && !isReady) {
      throw StateError('Inline plan is retired');
    }
    _ensureOwner!();
    if ((_state != _State.active && !isReady) ||
        _cache!.isClosed ||
        (_probe != null && !_cache!.ownsLease(_probe!)) ||
        (_parent != null && !_cache!.ownsLease(_parent!))) {
      throw StateError('Inline plan owner is retired');
    }
  }

  void _drop() {
    _pair?.close();
    _pair = null;
    _parent?.release();
    _parent = null;
    _probe?.releaseProvisional();
    _probe = null;
    _input = null;
    _result = null;
    _metrics.clear();
    _alignment = null;
    _retriedBands.clear();
    _cache = null;
    _textScaler = null;
    _ensureOwner = null;
  }

  void close() {
    if (_state != _State.active && !isReady) return;
    _state = _State.closed;
    _drop();
  }
}
