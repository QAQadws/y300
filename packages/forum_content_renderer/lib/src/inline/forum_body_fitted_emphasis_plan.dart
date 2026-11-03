import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_native_request.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_layout.dart';
import 'forum_body_emphasis_line_layout.dart';

/// One complete, actually fitted source line and its exact font/scene costs.
/// Pure admission input only; the visible transaction requalifies its source.
final class ForumBodyFittedEmphasisPlan {
  ForumBodyFittedEmphasisPlan._(this.metrics, this.nativeCosts) {
    final source = metrics.paragraphLine!;
    lines = List.unmodifiable([
      ForumBodyParagraphLine(
        top: 0,
        bottom: metrics.height,
        baseline: metrics.alphabeticBaseline,
        left: source.left + metrics.baseOffset.dx,
        width: source.width,
        startUtf16: source.startUtf16,
        endUtf16: source.endUtf16,
        coverageStartUtf16: source.coverageStartUtf16,
        coverageEndUtf16: source.coverageEndUtf16,
        engineStartUtf16: source.engineStartUtf16,
        engineEndUtf16: source.engineEndUtf16,
        engineCoverageStartUtf16: source.engineCoverageStartUtf16,
        engineCoverageEndUtf16: source.engineCoverageEndUtf16,
        unpaintedTrailingSpaceStartUtf16:
            source.unpaintedTrailingSpaceStartUtf16,
        engineUnpaintedTrailingSpaceStartUtf16:
            source.engineUnpaintedTrailingSpaceStartUtf16,
        canBreakBefore: source.canBreakBefore,
        canBreakAfter: source.canBreakAfter,
      ),
    ]);
  }
  static const revision = 1;
  final ForumBodyEmphasisLineMetrics metrics;
  final List<ForumBodyNativeInputCost> nativeCosts;
  late final List<ForumBodyParagraphLine> lines;
  ForumBodyParagraphContent get content => metrics.input.content;
}

enum _Phase { fonts, scene, publish, ready, closed }

/// The same aggregate probe as visible delivery, one actual font/scene per
/// part. No alias, shape, picture, cache hit or source authority is acquired.
final class ForumBodyFittedEmphasisPlanPreparation {
  ForumBodyFittedEmphasisPlanPreparation({
    required ForumBodyEmphasisLineMetrics metrics,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
  }) : _metrics = metrics,
       _cache = cache,
       _ensureOwner = ensureOwner {
    final line = metrics.paragraphLine, content = metrics.input.content;
    if (metrics.rowInput != null ||
        content.isSourceFree ||
        content.layoutMode != ForumBodyParagraphLayoutMode.fitSingleLine ||
        line == null ||
        line.coverageStartUtf16 != 0 ||
        line.coverageEndUtf16 != content.projection.text.length ||
        !line.canBreakBefore ||
        !line.canBreakAfter) {
      throw ArgumentError(
        'Fitted emphasis requires an actual complete paragraph line',
      );
    }
  }
  ForumBodyEmphasisLineMetrics? _metrics;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  Iterator<ForumBodyNativeRequestSlot>? _requests;
  ForumBodyParagraphBudgetProbe? _probe;
  ForumBodyFittedEmphasisPlan? _result;
  var _phase = _Phase.fonts;
  bool _operating = false;
  bool get isReady => _phase == _Phase.ready;
  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Fitted emphasis plan is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      if (isReady) return 0;
      _probe ??= _cache!.createBudgetProbe(captureInputEstimates: true);
      while (!isReady && used < maxParts) {
        switch (_phase) {
          case _Phase.fonts:
            _requests ??= _metrics!.nativeFootprint.iterator;
            if (_requests!.moveNext()) {
              final slot = _requests!.current;
              slot.request.includeBudget(
                _probe!,
                width: slot.width,
                minimumLineCount: slot.minimumLineCount,
                textScaler: _metrics!.textScaler,
              );
            } else {
              _requests = null;
              _phase = _Phase.scene;
            }
          case _Phase.scene:
            _probe!.includeTextPicture(_metrics!.pictureInput);
            _phase = _Phase.publish;
          case _Phase.publish:
            _result = ForumBodyFittedEmphasisPlan._(
              _metrics!,
              _probe!.snapshotNativeEstimates(),
            );
            _probe!.close();
            _probe = null;
            _phase = _Phase.ready;
          case _Phase.ready:
          case _Phase.closed:
            throw StateError('Fitted emphasis plan is retired');
        }
        used++;
        _guard();
      }
      return used;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ForumBodyFittedEmphasisPlan take() {
    if (_operating) throw StateError('Fitted emphasis plan is reentrant');
    _guard();
    if (!isReady) throw StateError('Fitted emphasis plan is incomplete');
    final result = _result!;
    close();
    return result;
  }

  void _guard() {
    if (_phase == _Phase.closed) {
      throw StateError('Fitted emphasis plan is retired');
    }
    _ensureOwner!();
    if (_phase == _Phase.closed || _cache?.isClosed != false) {
      throw StateError('Fitted emphasis owner is retired');
    }
  }

  void close() {
    if (_phase == _Phase.closed) return;
    _phase = _Phase.closed;
    _probe?.close();
    _probe = null;
    _requests = null;
    _result = null;
    _metrics = null;
    _cache = null;
    _ensureOwner = null;
  }
}
