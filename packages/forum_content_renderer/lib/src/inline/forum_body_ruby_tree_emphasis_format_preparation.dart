import 'package:flutter/painting.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_text_request.dart';
import 'forum_body_emphasis_line_layout.dart';
import 'forum_body_ruby_group_preparation.dart';
import 'forum_body_ruby_tree_input.dart';

/// Rebuild the complete emphasis plan from an actually measured/aligned glyph
/// root. Every stage uses its existing cooperative worker and shared cache;
/// old source positions, decoration bands and marker transforms are not reused.
/// This pure-plan transaction retains temporary fonts only, never visible paint.
final class ForumBodyRubyTreeEmphasisFormatPreparation {
  ForumBodyRubyTreeEmphasisFormatPreparation({
    required ForumBodyRubyGlyphTreeMetrics glyphMetrics,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    required TextScaler expectedTextScaler,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _cache = cache,
       _ensureOwner = ensureOwner,
       _scaler = expectedTextScaler,
       _additionalOwned = additionalOwnedLeases {
    _geometry = ForumBodyRubyGlyphTreeGeometryPreparation(
      metrics: glyphMetrics,
      ensureOwner: _guard,
    );
  }

  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  TextScaler? _scaler;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  ForumBodyRubyGlyphTreeGeometryPreparation? _geometry;
  ForumBodyRubyGlyphTreeBandsPreparation? _bands;
  ForumBodyRubyEmptyAnnotationFontsPreparation? _empty;
  ForumBodyRubyTreeEmphasisMetricsPreparation? _metrics;
  ForumBodyRubyTreeDecorationBandsPreparation? _decoration;
  ForumBodyRubyTreeEmphasisPlacementPreparation? _placement;
  ForumBodyRubyTreeEmphasisPlanPreparation? _plan;
  ForumBodyRubyTreeEmphasisPlan? _result;
  ForumBodyTextRequest? _failedRequest;
  bool _closed = false,
      _operating = false,
      _cacheMiss = false,
      _waiting = false;
  bool get isReady => _result != null;
  bool get cacheMiss => _cacheMiss;
  ForumBodyTextRequest? get failedRequest =>
      _failedRequest ?? _metrics?.failedRequest;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases =>
      _empty?.nativeLeases ?? _metrics?.nativeLeases ?? const [];

  ForumBodyRubyGroupPreparationStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() {
      _guard();
      final cache = _cache!,
          layouts = cache.layoutBuildCount,
          pictures = cache.pictureBuildCount;
      var parts = 0;
      _cacheMiss = _waiting = false;
      while (!isReady && parts < maxParts) {
        final used = _advance(cachedOnly);
        parts += used;
        _guard();
        if (used == 0 ||
            _cacheMiss ||
            _waiting ||
            cache.layoutBuildCount != layouts ||
            cache.pictureBuildCount != pictures) {
          break;
        }
      }
      return ForumBodyRubyGroupPreparationStep(
        partsPrepared: 0,
        partsInspected: 0,
        formatUnitsPrepared: parts,
        layoutsBuilt: cache.layoutBuildCount - layouts,
        picturesBuilt: cache.pictureBuildCount - pictures,
        isReady: isReady,
        waitingForLayoutBudget: _waiting,
      );
    });
  }

  int _advance(bool cachedOnly) {
    if (_geometry case final work?) {
      final used = work.advance(maxParts: 1);
      _guard();
      if (work.isReady) {
        final value = work.takeGeometry();
        _guard();
        work.close();
        _geometry = null;
        _bands = ForumBodyRubyGlyphTreeBandsPreparation(
          geometry: value,
          ensureOwner: _guard,
        );
      }
      return used;
    }
    if (_bands case final work?) {
      final used = work.advance(maxParts: 1);
      _guard();
      if (work.isReady) {
        final value = work.takeBands();
        _guard();
        work.close();
        _bands = null;
        _empty = ForumBodyRubyEmptyAnnotationFontsPreparation(
          bands: value,
          cache: _cache!,
          ensureOwner: _guard,
          expectedTextScaler: _scaler!,
          additionalOwnedLeases: _additionalOwned,
        );
      }
      return used;
    }
    if (_empty case final work?) {
      final step = work.advance(maxParts: 1, cachedOnly: cachedOnly);
      _guard();
      _cacheMiss = work.cacheMiss;
      _waiting = step.waitingForLayoutBudget;
      if (work.isReady) {
        final value = work.takeFonts();
        _guard();
        work.close();
        _empty = null;
        _metrics = ForumBodyRubyTreeEmphasisMetricsPreparation(
          emptyFonts: value,
          cache: _cache!,
          ensureOwner: _guard,
          expectedTextScaler: _scaler!,
          additionalOwnedLeases: _additionalOwned,
        );
        // The metrics worker now owns sampling all remaining actual half fonts.
        _scaler = null;
        _additionalOwned = null;
      }
      return step.formatUnitsPrepared;
    }
    if (_metrics case final work?) {
      final step = work.advance(maxParts: 1, cachedOnly: cachedOnly);
      _guard();
      _cacheMiss = work.cacheMiss;
      _waiting = step.waitingForLayoutBudget;
      if (work.isReady) {
        final value = work.takeMetrics();
        _guard();
        work.close();
        _metrics = null;
        _decoration = ForumBodyRubyTreeDecorationBandsPreparation(
          input: value,
          ensureOwner: _guard,
        );
      }
      return step.formatUnitsPrepared;
    }
    if (_decoration case final work?) {
      final used = work.advance(maxParts: 1);
      _guard();
      if (work.isReady) {
        final value = work.takeBands();
        _guard();
        work.close();
        _decoration = null;
        _placement = ForumBodyRubyTreeEmphasisPlacementPreparation(
          input: value,
          ensureOwner: _guard,
        );
      }
      return used;
    }
    if (_placement case final work?) {
      final used = work.advance(maxParts: 1);
      _guard();
      if (work.isReady) {
        final value = work.takePlacement();
        _guard();
        work.close();
        _placement = null;
        _plan = ForumBodyRubyTreeEmphasisPlanPreparation(
          placement: value,
          ensureOwner: _guard,
        );
      }
      return used;
    }
    final work = _plan!;
    final used = work.advance(maxParts: 1);
    _guard();
    if (work.isReady) {
      _result = work.takePlan();
      _guard();
      work.close();
      _plan = null;
    }
    return used;
  }

  ForumBodyRubyTreeEmphasisPlan takePlan() => _operate(() {
    _guard();
    if (!isReady) throw StateError('Ruby emphasis format is incomplete');
    final result = _result!;
    close();
    return result;
  });

  T _operate<T>(T Function() action) {
    if (_operating) throw StateError('Ruby emphasis format is reentrant');
    _operating = true;
    try {
      return action();
    } catch (_) {
      _failedRequest ??= _metrics?.failedRequest;
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_closed) throw StateError('Ruby emphasis format is retired');
    _ensureOwner!();
    if (_closed || _cache!.isClosed) {
      throw StateError('Ruby emphasis format owner is retired');
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    final releases = <void Function()>[
      if (_geometry != null) _geometry!.close,
      if (_bands != null) _bands!.close,
      if (_empty != null) _empty!.close,
      if (_metrics != null) _metrics!.close,
      if (_decoration != null) _decoration!.close,
      if (_placement != null) _placement!.close,
      if (_plan != null) _plan!.close,
    ];
    _geometry = null;
    _bands = null;
    _empty = null;
    _metrics = null;
    _decoration = null;
    _placement = null;
    _plan = null;
    _result = null;
    _cache = null;
    _ensureOwner = null;
    _scaler = null;
    _additionalOwned = null;
    // Exactly one child is active. Detach first so callback retirement cannot
    // reenter ownership of its temporary native fonts.
    for (final release in releases) {
      release();
    }
  }
}
