import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../pagination/forum_body_text_page_content.dart';
import '../paragraph/forum_body_text_request.dart';
import 'forum_body_inline_plan_input.dart';
import 'forum_body_ruby_group_preparation.dart';
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
  final _dimensions = <PlaceholderDimensions>[];
  final _retriedBands = Set<ForumBodyTextBandContent>.identity();
  ForumBodyRubyGroupPreparation? _pair;
  ForumBodyInlineParagraphLease? _parent;
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
      while (_dimensions.length < _input!.groups.length && parts < maxParts) {
        final request = _input!.groups[_dimensions.length];
        final pair = _pair ??= ForumBodyRubyGroupPreparation.forMetrics(
          cache: cache,
          base: request.base,
          annotation: request.annotation,
          ensureOwner: _guard,
          textScaler: _textScaler!,
          gap: request.gap,
          maxWidth: request.maxWidth,
        );
        try {
          final revisionBefore = cache.budgetRevision;
          final step = pair.advance();
          final budgetChanged = cache.budgetRevision != revisionBefore;
          if (step.madeProgress || budgetChanged) parts++;
          if (step.isReady) {
            _dimensions.add(pair.takeMetrics().placeholderDimensions);
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
          final failed = pair.preparedPartCount == 0
              ? request.base
              : request.annotation;
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
      if (_dimensions.length == _input!.groups.length && parts == 0) {
        ForumBodyInlineParagraphLease? parent;
        final rejectedAt = cache.budgetRevision;
        try {
          parent = cache.acquireInline(
            content: _input!.content,
            width: width,
            dimensions: _dimensions,
            textScaler: _textScaler!,
          );
          _guard();
          _parent = parent;
          _result = ForumBodyInlinePageContent(
            content: _input!.content,
            dimensions: _dimensions,
            rubyGroups: _input!.groups,
          );
          _state = _State.ready;
          parts++;
        } on ForumBodyParagraphBudgetException catch (error) {
          parent?.release();
          _guard();
          if (error.failure != ForumBodyParagraphBudgetFailure.pinned) rethrow;
          waiting = cache.budgetRevision == rejectedAt;
          if (!waiting) parts++;
        } catch (_) {
          parent?.release();
          rethrow;
        }
      }
      return (
        partsPrepared: parts,
        isReady: isReady,
        waitingForLayoutBudget: waiting,
      );
    });
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
        (_parent != null && !_cache!.ownsLease(_parent!))) {
      throw StateError('Inline plan owner is retired');
    }
  }

  void _drop() {
    _pair?.close();
    _pair = null;
    _parent?.release();
    _parent = null;
    _input = null;
    _result = null;
    _dimensions.clear();
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
